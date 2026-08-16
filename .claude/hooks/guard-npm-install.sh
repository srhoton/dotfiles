#!/bin/bash
#
# guard-npm-install.sh - PreToolUse(Bash) hook for Claude Code
#
# Blocks BARE package-manager installs (pnpm install / npm install / npm i /
# yarn / yarn install — no package arguments) when the target repo's lockfile
# already has uncommitted modifications. A bare install would regenerate the
# lockfile and silently clobber or compound those changes.
#
# Installs that add a named package (`npm install lodash`) and installs on a
# clean lockfile pass through.
#
# Motivation: a stray `pnpm install` once rewrote a lockfile mid-session,
# mixing an unintended regeneration into uncommitted work.
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

# Detect a BARE install: the install token is followed only by flags (-...)
# until the end of the command or the next shell operator. A non-flag word
# after install/add means a named package -> allow.
BARE=$(printf '%s' "$CMD" | python3 -c "
import sys, re, shlex
cmd = sys.stdin.read()
# Split on shell operators; inspect each simple command.
for seg in re.split(r'[;&|]+', cmd):
    try:
        toks = shlex.split(seg)
    except ValueError:
        toks = seg.split()
    if not toks:
        continue
    # skip leading env assignments (FOO=bar cmd)
    while toks and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', toks[0]):
        toks = toks[1:]
    if not toks:
        continue
    pm = toks[0]
    if pm not in ('npm', 'pnpm', 'yarn'):
        continue
    rest = toks[1:]
    if pm == 'yarn':
        # bare 'yarn' or 'yarn install' installs everything
        sub = rest[0] if rest and not rest[0].startswith('-') else None
        if sub is None or sub == 'install':
            args = rest[1:] if sub else rest
        else:
            continue
    else:
        if not rest:
            continue
        sub = rest[0]
        # 'npm ci' installs strictly from the lockfile and never writes it
        if sub not in ('install', 'i'):
            continue
        args = rest[1:]
    # lockfile-read-only modes never rewrite the lockfile -> allow
    if any(a in ('--frozen-lockfile', '--immutable') for a in args):
        continue
    # any non-flag argument means a named package -> not bare
    if any(not a.startswith('-') for a in args):
        continue
    print(pm)
    break
" 2>/dev/null)
[ -z "$BARE" ] && exit 0

# ---- Which repo does this act on? (same resolution as guard-destructive-git)
TARGET=$(echo "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&;|]+).*/\1/p' | head -1)
[ -z "$TARGET" ] && TARGET="$PWD"
TARGET="${TARGET/#\~/$HOME}"
TARGET="${TARGET%\"}"; TARGET="${TARGET#\"}"
TARGET="${TARGET%\'}"; TARGET="${TARGET#\'}"

git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Only block when a lockfile has UNCOMMITTED modifications.
DIRTY_LOCK=$(git -C "$TARGET" status --porcelain -- 'pnpm-lock.yaml' 'package-lock.json' 'yarn.lock' 2>/dev/null)
[ -z "$DIRTY_LOCK" ] && exit 0

{
  echo "BLOCKED: bare '$BARE install' in a repo whose lockfile has uncommitted changes ($TARGET)."
  echo ""
  echo "Regenerating the lockfile now would silently clobber or compound these:"
  printf '%s\n' "$DIRTY_LOCK"
  echo ""
  echo "Do one of these instead:"
  echo "  1. Commit or stash the lockfile change first, then install."
  echo "  2. If the lockfile change is the intended result of an earlier install, no new install is needed — verify with 'git -C \"$TARGET\" diff <lockfile>'."
  echo "  3. If a full reinstall is truly intended, say so and let the USER run it."
} >&2
exit 2
