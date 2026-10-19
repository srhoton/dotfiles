#!/bin/bash
#
# guard-pr-state.sh - PreToolUse(Bash) hook for Claude Code
#
# Blocks `git push` when the current branch belongs to a PR that is already
# MERGED or CLOSED. Commits have been pushed to merged-PR branches, where they
# reach no open review. CLAUDE.md already says "never update a closed PR" —
# this enforces it.
#
# Passes through when: there is no PR for the branch, `gh` is unavailable, or
# anything is ambiguous. A brand-new branch must always be pushable.
#
# Exit 2 = block, stderr is fed back to Claude. Exit 0 = allow.
#

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

CMD=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or d.get('input') or {}
    print(ti.get('command', ''))
except Exception:
    pass
" 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0

# `gh` does not expand `@path` in a body/message argument: --body "@file.md"
# posts the literal text "@file.md". Block it before anything else (this check
# is local; it never calls the network). Only inspects commands where `gh` is a
# command word (start, after a separator or `(`, after whitespace such as an env
# assignment, after a path `/`, or quoted), not any text containing "gh".
GH_WORD_RE='(^|[;&|(/[:space:]'"'"'"])gh([[:space:]'"'"'"]|$)'
if printf '%s' "$CMD" | grep -qE "$GH_WORD_RE"; then
    GH_MSG=$(CMD="$CMD" python3 -c '
import os, re, shlex, sys
try:
    lex = shlex.shlex(os.environ["CMD"], posix=True, punctuation_chars=";&|()\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    seps = set(";&|()\n")
    segs, cur = [], []
    for tok in lex:
        if tok and set(tok) <= seps:
            if cur:
                segs.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        segs.append(cur)
except Exception:
    sys.exit(0)
BODY_FLAGS = {"--body", "-b", "--message", "-m", "--comment"}
FIELD_FLAGS = {"-f", "--raw-field"}


def has_pair(args, first, seconds):
    return any(a == first and b in seconds for a, b in zip(args, args[1:]))


for seg in segs:
    i = 0
    while i < len(seg) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[i]):
        i += 1
    if i >= len(seg) or os.path.basename(seg[i]) != "gh":
        continue
    args = seg[i + 1:]
    body_flags = set(BODY_FLAGS)
    if has_pair(args, "pr", {"merge"}):
        # `gh pr merge -m` is --merge (a boolean), not a message; keep --body/-b.
        body_flags -= {"-m", "--message"}
    if has_pair(args, "release", {"create", "edit"}):
        body_flags |= {"--notes", "-n"}
    short_flags = {f for f in body_flags if len(f) == 2}
    for j, a in enumerate(args):
        nxt = args[j + 1] if j + 1 < len(args) else ""
        val = None
        if a in body_flags or a in FIELD_FLAGS:
            val = nxt
            if a in FIELD_FLAGS:
                val = nxt[5:] if nxt.startswith("body=") else None
        elif a.startswith("--") and "=" in a:
            name, _, v = a.partition("=")
            if name in body_flags:
                val = v
            elif name == "--raw-field" and v.startswith("body="):
                val = v[5:]
        elif len(a) > 2 and not a.startswith("--") and a[:2] in short_flags:
            val = a[2:]
        elif a.startswith("-fbody="):
            val = a[7:]
        if val is not None and val.startswith("@"):
            print(a)
            sys.exit(0)
' 2>/dev/null)
    if [ -n "$GH_MSG" ]; then
      {
        echo "BLOCKED: gh does not expand @path ('$GH_MSG' was given a value starting with @)."
        echo "The literal text would be posted instead of the file contents."
        echo "Use  --body-file <file>  (gh pr/issue create|edit|comment, ...), or for"
        echo "gh api use  --input <payload.json>."
      } >&2
      exit 2
    fi
fi

# Only `git push`.
echo "$CMD" | grep -qE '(^|[;&|]|&&)[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push\b' || exit 0

command -v gh >/dev/null 2>&1 || exit 0

TARGET=$(echo "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
if [ -z "$TARGET" ]; then
  TARGET=$(echo "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&;|]+).*/\1/p' | head -1)
fi
[ -z "$TARGET" ] && TARGET="$PWD"
TARGET="${TARGET/#\~/$HOME}"
TARGET="${TARGET%\"}"; TARGET="${TARGET#\"}"
TARGET="${TARGET%\'}"; TARGET="${TARGET#\'}"

git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  exit 0
fi

STATE=$(cd "$TARGET" 2>/dev/null && gh pr view "$BRANCH" --json state -q .state 2>/dev/null)
[ -z "$STATE" ] && exit 0   # no PR, or gh couldn't tell us -> allow

case "$STATE" in
  MERGED|CLOSED)
    URL=$(cd "$TARGET" 2>/dev/null && gh pr view "$BRANCH" --json url -q .url 2>/dev/null)
    {
      echo "BLOCKED: branch '$BRANCH' belongs to a PR that is already $STATE."
      [ -n "$URL" ] && echo "  $URL"
      echo ""
      echo "Pushing here reaches no open review. Per CLAUDE.md, a closed/merged PR"
      echo "requires a NEW branch and a NEW PR:"
      echo "    git -C \"$TARGET\" checkout -b <new-branch>"
      echo "    git -C \"$TARGET\" push -u origin <new-branch>"
      echo "then open a fresh PR against the default branch."
    } >&2
    exit 2
    ;;
esac
exit 0
