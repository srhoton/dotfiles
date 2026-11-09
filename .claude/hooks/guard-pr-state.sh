#!/bin/bash
#
# guard-pr-state.sh - PreToolUse(Bash) hook for Claude Code
#
# Blocks `git push` when the current branch belongs to a PR that is already
# MERGED or CLOSED. Commits have been pushed to merged-PR branches, where they
# reach no open review. CLAUDE.md already says "never update a closed PR" —
# this enforces it.
#
# Also blocks raw PR approvals (`gh pr review --approve|-a`, `gh api` posting a
# review with event APPROVE): approve through `~/.claude/bin/pr-approve --sha`,
# which refuses when the head moved since the review. And on `git push` to a
# branch whose open PR already has APPROVED reviews, emits a non-blocking
# additionalContext warning that the push may dismiss them.
#
# Passes through when: there is no PR for the branch, `gh` is unavailable, or
# anything is ambiguous. A brand-new branch must always be pushable.
#
# Exit 2 = block, stderr is fed back to Claude. Exit 0 = allow (stdout may carry
# hookSpecificOutput JSON).
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
# gh pr review flags that take a separate value: that value is text, not a flag.
REVIEW_VALUE_FLAGS = {"-b", "--body", "-F", "--body-file", "-R", "--repo"}
# gh api flags that carry a key=value field.
API_FIELD_FLAGS = {"-f", "-F", "--field", "--raw-field"}
REVIEWS_PATH_RE = re.compile(r"pulls/[^/\s]+/reviews")
APPROVE_EVENT_RE = re.compile(r"^event=APPROVE$", re.I)
JSON_APPROVE_RE = re.compile(r"\"event\"\s*:\s*\"APPROVE\"", re.I)


def has_pair(args, first, seconds):
    return any(a == first and b in seconds for a, b in zip(args, args[1:]))


def pr_review_approves(args):
    """`gh pr review ... --approve|-a` (a value following -b/--body/... is text, not a flag)."""
    if not has_pair(args, "pr", {"review"}):
        return False
    prev = ""
    for a in args:
        if prev not in REVIEW_VALUE_FLAGS and (
            a in ("--approve", "-a") or a.startswith("--approve=")
        ):
            return True
        prev = a
    return False


def api_event_values(args):
    """Yield every `key=value` field string passed to gh api, in any flag spelling."""
    for j, a in enumerate(args):
        nxt = args[j + 1] if j + 1 < len(args) else ""
        if a in API_FIELD_FLAGS:
            yield nxt
        elif a.startswith("--") and "=" in a and a.partition("=")[0] in API_FIELD_FLAGS:
            yield a.partition("=")[2]
        elif len(a) > 2 and a[:2] in ("-f", "-F"):
            yield a[2:]


def api_approves(args, cmd):
    """`gh api` posting a review with event APPROVE (REST pulls/N/reviews, or GraphQL)."""
    if "api" not in args:
        return False
    fields = list(api_event_values(args))
    if any(REVIEWS_PATH_RE.search(a) for a in args):
        if any(APPROVE_EVENT_RE.match(f) for f in fields):
            return True
        # --input <file>: read the payload when it is a readable local JSON file.
        for j, a in enumerate(args):
            if a == "--input" and j + 1 < len(args):
                src = args[j + 1]
                if src == "-":
                    # payload comes from stdin (heredoc/pipe): look at the command text.
                    if JSON_APPROVE_RE.search(cmd):
                        return True
                else:
                    try:
                        with open(os.path.expanduser(src)) as fh:
                            if JSON_APPROVE_RE.search(fh.read(1 << 20)):
                                return True
                    except Exception:
                        pass
    if "graphql" in args and any(
        re.search(r"(addPullRequestReview|submitPullRequestReview)", f) and re.search(r"\bAPPROVE\b", f)
        for f in args
    ):
        return True
    return False


for seg in segs:
    i = 0
    while i < len(seg) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[i]):
        i += 1
    if i >= len(seg) or os.path.basename(seg[i]) != "gh":
        continue
    args = seg[i + 1:]
    if pr_review_approves(args) or api_approves(args, os.environ["CMD"]):
        print("APPROVE")
        sys.exit(0)
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
    if [ "$GH_MSG" = "APPROVE" ]; then
      {
        echo "BLOCKED: raw PR approvals bypass the reviewed-SHA check (they cannot pin the commit that was reviewed)."
        echo "Use  ~/.claude/bin/pr-approve <PR#> --sha <reviewed-sha> [-R owner/repo] [--body-file <file>]"
        echo "(-n is a dry run). The reviewed SHA is the 'Reviewed SHA' /reviewit printed."
      } >&2
      exit 2
    elif [ -n "$GH_MSG" ]; then
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

# Open PR: a push can dismiss existing approvals (repos with "dismiss stale
# approvals"). Warn, never block. Count the latest review per author that is
# APPROVED. Any gh failure or unexpected output -> stay silent (allow).
APPROVALS=$(cd "$TARGET" 2>/dev/null && gh pr view "$BRANCH" --json number,latestReviews \
  -q '"\(.number) \([.latestReviews[]? | select(.state == "APPROVED")] | length)"' 2>/dev/null)
if [[ "$APPROVALS" =~ ^([0-9]+)\ ([0-9]+)$ ]] && [ "${BASH_REMATCH[2]}" -gt 0 ]; then
  MSG="PR #${BASH_REMATCH[1]} has ${BASH_REMATCH[2]} approval(s); this push may dismiss them. Tell the user the PR needs re-approval (via ~/.claude/bin/pr-approve after a re-review) once the push lands." \
    python3 -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":os.environ["MSG"]}}))' 2>/dev/null
fi
exit 0
