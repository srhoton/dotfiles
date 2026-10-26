"""numbered_diff: unified diff text -> per-file hunks with NEW-file line numbers.

Shared by review-context --diff (a local `git diff`), pr-context --diff (`gh pr diff`)
and pr-review-post (which needs the set of RIGHT-side lines a review comment can anchor
to). One hunk walker serves all three, so the numbers a reviewer reads are the numbers
pr-review-post accepts.

Rendering, per file:

    === path (+ADDED -DELETED) ===
    12| +added line
    13|  context line
        -| -deleted line            (deleted lines have no new-file number)

The header gains a suffix inside the parentheses for new/deleted/renamed files
(`+3 -0, new file`, `+0 -5, deleted`, `+1 -1, renamed from old/path`). A binary file is
one line, `path: binary file changed`. A `\\ No newline at end of file` marker is kept,
unnumbered. A trailing CR (CRLF files) is dropped from the displayed text. Nothing is
truncated.

Standard library only. Also runnable: `numbered_diff.py [--only PATH]...` reads a unified
diff on stdin and prints the rendering (restricted to the given paths, matched against
either side of a rename).
"""

from __future__ import annotations

import re
import sys
from typing import NamedTuple

# `@@ -1 +1 @@`, `@@ -1,3 +1,4 @@ func()` and `@@ -0,0 +1,2 @@`: counts are optional.
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
NO_NEWLINE = "\\"


class Line(NamedTuple):
    kind: str  # "+" added, " " context, "-" deleted, "\\" no-newline marker
    new: int | None  # new-file line number; None for "-" and "\\"
    text: str  # the line without its one-character prefix, trailing CR dropped


class FileDiff(NamedTuple):
    path: str  # the new path (the old one for a deletion)
    old_path: str | None  # set only for a rename
    status: str  # "modified" | "added" | "deleted" | "renamed"
    binary: bool
    lines: list[Line]

    @property
    def added(self) -> int:
        return sum(1 for ln in self.lines if ln.kind == "+")

    @property
    def deleted(self) -> int:
        return sum(1 for ln in self.lines if ln.kind == "-")


def split_rows(text: str) -> list[str]:
    """Split on "\\n" only: str.splitlines() also breaks on \\x0c, \\x1c-\\x1e, \\x85 and U+2028/9,
    which can occur inside a source line and would shift every later line number."""
    rows = text.split("\n")
    if rows and rows[-1] == "":
        rows.pop()
    return rows


def walk_hunks(rows: list[str]) -> list[Line]:
    """Every body line of every hunk in `rows`, numbered on the new side. Rows before the
    first hunk header (file headers) are ignored. Any row that is not "-" or "\\" counts as
    an added or context line, as GitHub's patch format allows a bare empty context row."""
    out: list[Line] = []
    right: int | None = None
    for raw in rows:
        m = HUNK.match(raw)
        if m:
            right = int(m.group(1))
            continue
        if right is None:
            continue
        text = raw[1:].removesuffix("\r")
        if raw.startswith(NO_NEWLINE):
            out.append(Line(NO_NEWLINE, None, raw.removesuffix("\r")))
        elif raw.startswith("-"):
            out.append(Line("-", None, text))
        else:
            out.append(Line("+" if raw.startswith("+") else " ", right, text))
            right += 1
    return out


def commentable_lines(patch: str) -> set[int]:
    """RIGHT-side line numbers a review comment can anchor to: added and context lines."""
    return {ln.new for ln in walk_hunks(split_rows(patch)) if ln.new is not None}


# ---- full diffs -----------------------------------------------------------------

_ESCAPES = {
    "t": 9,
    "n": 10,
    "r": 13,
    "a": 7,
    "b": 8,
    "f": 12,
    "v": 11,
    "\\": 92,
    '"': 34,
}


def _unquote(value: str) -> str:
    """Undo git's C-style quoting of a path ("a\\tb", "\\303\\251")."""
    if len(value) < 2 or not (value.startswith('"') and value.endswith('"')):
        return value
    body, out, i = value[1:-1], bytearray(), 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            octal = re.match(r"[0-7]{3}", body[i + 1 :])
            if octal:
                out.append(int(octal.group(), 8))
                i += 4
                continue
            out.append(_ESCAPES.get(body[i + 1], ord(body[i + 1]) & 0xFF))
            i += 2
            continue
        out += c.encode("utf-8")
        i += 1
    return out.decode("utf-8", errors="replace")


def _side(row: str, prefix: str) -> str | None:
    """Path from a `--- a/x` / `+++ b/x` row; None for /dev/null.

    Git appends a TAB to unquoted paths that contain spaces.
    """
    value = row[4:].rstrip("\r")
    value = _unquote(value) if value.startswith('"') else value.split("\t")[0]
    if value == "/dev/null":
        return None
    return value.removeprefix(prefix)


def _header_paths(diff_line: str, header: list[str]) -> tuple[str | None, str | None]:
    """(old, new) paths of one file section; None for the side that does not exist."""
    old = new = None
    rename_from = rename_to = None
    for row in header:
        row = row.rstrip("\r")
        if row.startswith("rename from "):
            rename_from = _unquote(row[len("rename from ") :])
        elif row.startswith("rename to "):
            rename_to = _unquote(row[len("rename to ") :])
        elif row.startswith("--- "):
            old = _side(row, "a/")
        elif row.startswith("+++ "):
            new = _side(row, "b/")
    if rename_from is not None and rename_to is not None:
        return rename_from, rename_to
    saw_sides = any(r.startswith("--- ") for r in header) and any(
        r.startswith("+++ ") for r in header
    )
    if saw_sides:
        return old, new
    # No ---/+++ rows (binary, mode-only, empty new file): both sides share the path,
    # so `a/P b/P` splits at the middle even when P contains spaces.
    rest = diff_line[len("diff --git ") :].rstrip("\r")
    n = len(rest) - 5
    if (
        n > 0
        and n % 2 == 0
        and rest[:2] == "a/"
        and rest[2 + n // 2 : 5 + n // 2] == " b/"
        and rest[2 : 2 + n // 2] == rest[5 + n // 2 :]
    ):
        path = rest[2 : 2 + n // 2]
    else:
        m = re.match(r'^"?a/(.*?)"? "?b/(.*?)"?$', rest)
        path = _unquote('"' + m.group(2) + '"') if m else rest
    return path, path


def parse_diff(text: str) -> list[FileDiff]:
    """Parse a multi-file unified diff (`git diff`, `gh pr diff`) into FileDiff records."""
    sections: list[list[str]] = []
    for row in split_rows(text):
        if row.startswith("diff --git "):
            sections.append([row])
        elif sections:
            sections[-1].append(row)
    files: list[FileDiff] = []
    for section in sections:
        diff_line, rows = section[0], section[1:]
        first_hunk = next((i for i, r in enumerate(rows) if HUNK.match(r)), len(rows))
        header = rows[:first_hunk]
        old, new = _header_paths(diff_line, header)
        # The mode headers decide new/deleted even when there are no ---/+++ rows (an
        # empty new or deleted file), where both path sides come back equal.
        is_new = any(r.startswith("new file mode") for r in header) or (
            old is None and new is not None
        )
        is_deleted = any(r.startswith("deleted file mode") for r in header) or (
            new is None and old is not None
        )
        binary = any(
            r.startswith(("Binary files ", "GIT binary patch")) for r in header
        )
        if is_deleted:
            status, path, old_path = "deleted", old or new or "", None
        elif is_new:
            status, path, old_path = "added", new or old or "", None
        elif old is not None and new is not None and old != new:
            status, path, old_path = "renamed", new, old
        else:
            status, path, old_path = "modified", new or old or "", None
        files.append(
            FileDiff(path, old_path, status, binary, walk_hunks(rows[first_hunk:]))
        )
    return files


def render_file(f: FileDiff) -> str:
    if f.binary:
        return f"{f.path}: binary file changed"
    extra = {
        "added": ", new file",
        "deleted": ", deleted",
        "renamed": f", renamed from {f.old_path}",
    }.get(f.status, "")
    out = [f"=== {f.path} (+{f.added} -{f.deleted}{extra}) ==="]
    for ln in f.lines:
        if ln.kind == "-":
            out.append(f"    -| -{ln.text}")
        elif ln.kind == NO_NEWLINE:
            out.append(f"    \\| {ln.text}")
        else:
            out.append(f"{ln.new}| {ln.kind}{ln.text}")
    return "\n".join(out)


def render(files: list[FileDiff], only: list[str] | None = None) -> str:
    """The numbered diff of `files` (a rename matches `only` by either path)."""
    if only:
        wanted = set(only)
        files = [f for f in files if f.path in wanted or (f.old_path in wanted)]
    if not files:
        return "(no changes)"
    return "\n\n".join(render_file(f) for f in files)


def render_diff(text: str, only: list[str] | None = None) -> str:
    return render(parse_diff(text), only)


def main(argv: list[str]) -> int:
    only: list[str] = []
    args = list(argv)
    while args:
        if args[0] == "--only" and len(args) >= 2:
            only.append(args[1])
            args = args[2:]
        else:
            print(
                "usage: numbered_diff.py [--only PATH]... < unified.diff",
                file=sys.stderr,
            )
            return 2
    text = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    print(render_diff(text, only or None))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
