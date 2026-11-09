#!/bin/bash
#
# guard-session-scope.sh - UserPromptSubmit hook for Claude Code
#
# Enforces one /deliver ticket per session. A second /deliver in the same
# session keeps the main loop's context growing (responses at 800K+ context
# were the bulk of one session's cost), so it is blocked with a pointer to
# start a fresh session. `--same-session` in the prompt overrides.
#
# How it decides: the prompt must start with `/deliver` and lack
# `--same-session`. Then transcript_path (JSONL) is grepped for an earlier user
# turn that invoked the command. Slash commands are stored as
#   "role":"user","content":"<command-message>deliver</command-message>\n<command-name>/deliver</command-name>...
# The transcript is written asynchronously, so the current prompt may already
# be on disk. A /deliver entry with no assistant entry after it is therefore
# treated as ambiguous (possibly the current prompt) and does not count.
#
# Every error or ambiguity (no stdin, bad JSON, missing/unreadable transcript)
# passes through.
#
# Block = stdout JSON {"decision":"block","reason":...} and exit 0. Else exit 0.
#

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# Prints transcript_path only when the prompt is a /deliver without --same-session.
TRANSCRIPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    prompt = d.get('prompt') or ''
    path = d.get('transcript_path') or ''
    if not isinstance(prompt, str) or not isinstance(path, str):
        sys.exit(0)
    if not re.match(r'^\s*/deliver(\s|$)', prompt):
        sys.exit(0)
    if re.search(r'(^|\s)--same-session(\s|$)', prompt):
        sys.exit(0)
    print(path)
except Exception:
    pass
" 2>/dev/null) || exit 0
[ -z "$TRANSCRIPT" ] && exit 0
[ -r "$TRANSCRIPT" ] || exit 0

# Line numbers of every /deliver user turn already in the transcript (one grep pass).
LINES=$(grep -n -F '"role":"user","content":"<command-message>deliver</command-message>\n<command-name>/deliver</command-name>' "$TRANSCRIPT" 2>/dev/null | cut -d: -f1)
[ -z "$LINES" ] && exit 0

# Exactly one entry may be the current prompt itself (already flushed to disk):
# count it only if an assistant reply follows it. Two or more means at least
# one is an earlier turn.
if [ "$(printf '%s\n' "$LINES" | wc -l)" -lt 2 ]; then
  tail -n +"$LINES" "$TRANSCRIPT" 2>/dev/null | grep -q -F '"type":"assistant"' || exit 0
fi

printf '%s\n' '{"decision":"block","reason":"This session already ran /deliver. Start a fresh session (/clear or a new window) for the next ticket: one ticket per session keeps the main loop'"'"'s context small. Add --same-session to override."}'
exit 0
