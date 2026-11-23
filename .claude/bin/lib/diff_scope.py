"""diff_scope: the git, base-branch and file-kind helpers shared by review-signals and risk-score.

One place for how a change is scoped, so the two scripts agree on it:

- git() / out()      run git with literal pathspecs and no path quoting; GitError on failure.
- resolve_ref / resolve_base
                     the base branch rule (origin/HEAD, else master, else main; the default
                     prefers origin/<branch> over a possibly stale local one, as review-context does).
- enter_repo()       chdir to -C DIR, then to the repo toplevel.
- merge_base()       merge base of the base ref and HEAD.
- diff_text() / changed_names() / read_untracked()
                     the merge-base-to-working-tree diff (committed, staged, unstaged) and the
                     untracked files, or, with to_rev, the plain from_rev..to_rev tree diff.
- SOURCE_EXTS, TEST_FILE_RE, PATH_RES / path_labels()
                     which files count as source, which are tests, and which paths look like
                     persistence schemas (*.v1.json, migration, transform, schema, .sql).

Standard library only. Import with
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib"))
"""

import os
import re
import subprocess

I = re.IGNORECASE

MAX_UNTRACKED_BYTES = 2_000_000

# Line patterns only run on changed lines of these source files. Everything else (docs,
# logs, XML/POM, YAML, JSON, lockfiles...) is ignored for line patterns; path patterns
# below still apply to any file.
SOURCE_EXTS = frozenset(
    ".ts .tsx .js .jsx .mjs .cjs .java .kt .py .go .tf .sql .scala .cs .rb".split()
)
# Test files: *.test.*, *.spec.*, or under test/tests/__tests__.
TEST_FILE_RE = re.compile(r"\.(?:test|spec)\.|/(?:test|tests|__tests__)/", I)

PATH_RES = [
    ("*.v1.json", re.compile(r"\.v1\.json$", I)),
    ("migration path", re.compile(r"/migration", I)),
    ("transform path", re.compile(r"/transform", I)),
    ("schema path", re.compile(r"schema[^/]*(?:/.*)?\.(?:json|ts|java|sql)$", I)),
    ("sql file", re.compile(r"\.sql$", I)),
]

DIFF_FLAGS = [
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--no-renames",
    "--src-prefix=a/",
    "--dst-prefix=b/",
]


class GitError(Exception):
    pass


def git(args, check=True):
    p = subprocess.run(
        ["git", "--literal-pathspecs", "-c", "core.quotepath=off"] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and p.returncode != 0:
        msg = p.stderr.decode("utf-8", "replace").strip().splitlines()
        raise GitError(
            "git %s failed: %s" % (args[0], msg[0] if msg else "rc=%d" % p.returncode)
        )
    return p


def out(args):
    return git(args).stdout.decode("utf-8", "replace")


def resolve_ref(name, prefer_origin=False):
    order = ["origin/" + name, name] if prefer_origin else [name, "origin/" + name]
    for ref in order:
        if (
            git(
                ["rev-parse", "--verify", "-q", ref + "^{commit}"], check=False
            ).returncode
            == 0
        ):
            return ref
    return ""


def resolve_base(base_arg):
    if base_arg:
        ref = resolve_ref(base_arg)
        if not ref:
            raise GitError("base branch not found: " + base_arg)
        return ref
    p = git(["symbolic-ref", "-q", "refs/remotes/origin/HEAD"], check=False)
    name = (
        p.stdout.decode().strip().replace("refs/remotes/origin/", "", 1)
        if p.returncode == 0
        else ""
    )
    ref = resolve_ref(name, True) if name else ""
    if not ref:
        for cand in ("master", "main"):
            ref = resolve_ref(cand, True)
            if ref:
                break
    if not ref:
        raise GitError("base branch not found (tried origin/HEAD, master, main)")
    return ref


def enter_repo(dir_):
    """chdir to DIR (if given), then to the repo toplevel; returns the toplevel."""
    if dir_:
        try:
            os.chdir(dir_)
        except OSError:
            raise GitError("cannot cd to " + dir_)
    root = git(["rev-parse", "--show-toplevel"]).stdout.decode().strip()
    os.chdir(root)
    return root


def merge_base(base_ref):
    mb = git(["merge-base", base_ref, "HEAD"], check=False)
    from_rev = mb.stdout.decode().strip()
    if mb.returncode != 0 or not from_rev:
        raise GitError("no merge base with " + base_ref)
    return from_rev


def pathspec(files):
    """git pathspec tail restricting a diff to FILES (repo-root-relative); [] for all files."""
    only = [f[2:] if f.startswith("./") else f for f in files]
    return ["--"] + only if only else []


def diff_text(from_rev, spec, to_rev=None, unified=0):
    """The diff from from_rev to the working tree (or to to_rev), as unified text."""
    revs = [from_rev, to_rev] if to_rev else [from_rev]
    return out(DIFF_FLAGS + ["-U%d" % unified] + revs + spec)


def changed_names(from_rev, spec, to_rev=None):
    revs = [from_rev, to_rev] if to_rev else [from_rev]
    return [
        n
        for n in out(
            DIFF_FLAGS[:1] + ["--no-renames", "--name-only", "-z"] + revs + spec
        ).split("\0")
        if n
    ]


def read_untracked(spec):
    """(path, text) for each untracked, non-ignored file; text is None when the file was
    skipped (unreadable, over MAX_UNTRACKED_BYTES, or binary) but still exists as a path."""
    found = []
    for path in [
        n
        for n in out(["ls-files", "--others", "--exclude-standard", "-z"] + spec).split(
            "\0"
        )
        if n
    ]:
        if os.path.isdir(path) and not os.path.islink(path):
            continue
        text = None
        try:
            if os.path.getsize(path) <= MAX_UNTRACKED_BYTES:
                with open(path, "rb") as fh:
                    data = fh.read()
                if b"\0" not in data:
                    text = data.decode("utf-8", "replace")
        except OSError:
            pass
        found.append((path, text))
    return found


def path_labels(path):
    """Labels of the PATH_RES persistence-path rules that match a repo-relative path."""
    probe = "/" + path
    return [label for label, rx in PATH_RES if rx.search(probe)]
