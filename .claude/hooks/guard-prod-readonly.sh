#!/bin/bash
#
# guard-prod-readonly.sh - PreToolUse(Bash | AWS MCP run_script) hook for Claude Code
#
# Enforces two hard rules from CLAUDE.md:
#
#   1. Prod is read-only. Any `aws ...` command that targets a prod profile
#      (name starting with fb-live-us-prod) is blocked unless the operation is
#      a read: describe-*, get-*, list-*, batch-get-item, query, scan,
#      filter-log-events, `logs start-query`, `logs tail`, `s3 ls|presign`,
#      `s3 cp|sync` from s3:// to a LOCAL destination, `s3api head-object`,
#      `sso login|logout`, `configure`. `terraform apply|destroy` (and anything
#      else that is not a read, including `init -migrate-state|-force-copy|
#      -reconfigure`) is blocked when AWS_PROFILE (inline, exported earlier in
#      the command, or in the hook's environment) is prod. Demo
#      (fb-demo-us-prod) is NOT prod. The profile comes from `--profile X`,
#      else an inline/exported AWS_PROFILE, else AWS_PROFILE in the hook's
#      environment.
#
#   2. Secret values never enter context. `aws secretsmanager get-secret-value`
#      and `batch-get-secret-value` are blocked on EVERY profile, and so is
#      GetSecretValue / BatchGetSecretValue / get_secret_value inside the AWS
#      MCP server's run_script code. (MCP code is not otherwise judged.) In a
#      Bash command the SDK spellings are blocked next to secretsmanager,
#      boto3 or aws-sdk, and so is SSM get-parameter(s) on
#      /aws/reference/secretsmanager (it returns the secret). A
#      service or operation given through a shell variable or command
#      substitution is unverifiable: it is blocked when the other half is
#      secretsmanager/get-secret-value or is also a variable.
#
# Two layers:
#
#   Structural (precise): commands are tokenised with shlex and split on
#   ; & | ( ) and newlines, so chains (&&, ;, |), env prefixes, wrappers (env,
#   command, sudo -u X, nice -n N, timeout DUR, xargs -I X, stdbuf, watch,
#   nohup, time, `mise exec --`, `uv run`), `eval` and `bash -c "..."` are all
#   inspected. $VAR, ${VAR} and ${VAR:-default} are expanded against inline
#   assignments in earlier segments and the hook's environment. A profile that
#   still contains `$` or a backtick after expansion (command substitution, an
#   unset variable) is "unknown": that segment is not counted as examined and
#   the backstop judges it. A variable service/operation on a prod or unknown
#   profile is blocked.
#
#   Raw-text backstop (conservative): runs whenever the structural layer did
#   not already block and its verdict is not trustworthy, including when it
#   could not parse the command (e.g. a heredoc body with an apostrophe) or
#   raised. The structural verdict is trusted, and the backstop skipped, only
#   when the pass parsed cleanly, examined every aws/awscli/terraform/tofu word
#   in the text, met no unresolved command word, and (unless prod is named, see
#   P1) every profile it resolved was concrete. Otherwise the backstop blocks
#   (a) a variable aws service/operation next to a secret half, and (b) when the
#   text names fb-live-us-prod, the hook env profile is prod, or a profile was
#   unknown: a mutating AWS CLI operation, an aws word with no service after it
#   (`$(which aws) ...`, args supplied by xargs), or a terraform subcommand.
#   For aws it judges ONLY the service/operation position after each `aws`
#   word (global options skipped), never resource names, ARNs or redirects.
#   When it is unsure it blocks; a false positive is resolved by the user
#   running the command themselves.
#
# Trust policy (the structural parser can mis-resolve the profile or never see
# the real argv, so it does not get the last word):
#
#   P1 prod named: when the text contains fb-live-us-prod (any case), profile
#      resolution is ignored. Every aws/awscli (also `python -m awscli`)
#      invocation the structural pass saw must be a read per the allow-list
#      (service and op literal and present, none supplied by xargs stdin or a
#      replace string), every terraform/tofu invocation must be a read
#      subcommand, and no command word may be unresolved after expansion
#      (`$(which aws)`, `$X`; `${AWS_BIN:-aws}` and `A=aws; $A` expand and are
#      treated as aws). aws under parallel / find -exec is not followed
#      structurally; the text backstop judges it. Reads stay allowed.
#   P2 secrets, order-independent and linear: the lowercased text has
#      get-secret-value (or batch-) AND (secretsmanager anywhere, OR an aws /
#      awscli word, OR an xargs/parallel/find -exec word, OR an unresolved
#      command word). Never skipped, on every profile. An xargs-wrapped aws whose
#      service or op is missing or a replace string is also blocked next to the
#      other secret half, for stdin that comes from a file.
#   P3 env-profile path (no prod literal): aws options are canonicalised by
#      unique prefix (argparse: `--prof X` is `--profile X`), and the env wrapper
#      is applied (`env -u NAME` / `--unset`, `-i` / `-` / `--ignore-environment`
#      change the environment the command sees, not the shell scope used to
#      expand arguments).
#
#   P4 non-aws binaries: when the text names fb-live-us-prod and holds an
#      SDK-style mutation call (`put_item(`, `PutItemCommand`, `.invoke(`), it is
#      blocked (a text rule; python/node code is not parsed). terragrunt is
#      treated as terraform. Other wrappers (sam, cdk, make, scripts) under a prod
#      AWS_PROFILE are NOT judged.
#
# Size cap: shlex tokenising is quadratic in word length, so a command over 200KB
# or with a single whitespace-separated word over 20KB skips the structural
# layer; P1/P2 text rules still apply.
#
# Residual limits: arguments that xargs reads from a file or stdin cannot be
# seen, so `xargs aws < args.txt` on a non-prod profile with no prod text and no
# secret term is allowed; a profile set by `source`/`export $(...)` is invisible.
#
# Fail-closed edges: the Python layer has an internal 7s budget (the hook
# timeout is 10s) and this wrapper blocks when python3 exits with anything
# other than 0 or 2 while the input mentions aws/terraform/tofu/fb-live-us.
#
# Exit 2 = block, stderr is fed back to Claude. Exit 0 = allow.
#

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

read -r -d '' PY <<'PYEOF'
import json
import os
import re
import shlex
import signal
import sys

PROD_PREFIX = "fb-live-us-prod"
TIME_BUDGET_SECONDS = 7
UNKNOWN_PROFILE = "$unresolved"
SECRET_OPS = {"get-secret-value", "batch-get-secret-value"}
MCP_TOOL_RE = re.compile(r"mcp__.*aws.*run_script", re.I)
MCP_SECRET_RE = re.compile(
    r"GetSecretValue|BatchGetSecretValue|get[_-]secret[_-]value", re.I
)
# SDK spellings (boto3, node, the CLI's own words): a GetSecretValue name next to
# one of these is a secret read. These substrings also cover secretsmanagerclient
# and @aws-sdk.
SECRET_SDK_WORDS = ("secretsmanager", "secrets-manager", "boto3", "aws-sdk")
# get-parameter(s|-by-path), get_parameter, GetParameterCommand (text is lowercased).
SSM_GET_RE = re.compile(r"get[_-]?parameter")
# Broad substring match used only on failure paths (timeout, crash).
MENTION_RE = re.compile(r"aws|terraform|terragrunt|tofu|fb-live-us", re.I)

# aws global options that consume a following value.
GLOBAL_VALUE_OPTS = {
    "--profile", "--region", "--endpoint-url", "--output", "--query",
    "--color", "--ca-bundle", "--cli-read-timeout", "--cli-connect-timeout",
    "--cli-binary-format", "--cli-auto-prompt",
}
# aws s3 options that consume a following value (so they are not mistaken
# for the source/destination arguments).
S3_VALUE_OPTS = GLOBAL_VALUE_OPTS | {
    "--exclude", "--include", "--acl", "--sse", "--sse-c", "--sse-c-key",
    "--sse-kms-key-id", "--sse-c-copy-source", "--sse-c-copy-source-key",
    "--storage-class", "--content-type", "--cache-control",
    "--content-disposition", "--content-encoding", "--content-language",
    "--expires", "--website-redirect", "--metadata", "--metadata-directive",
    "--grants", "--source-region", "--page-size", "--request-payer",
    "--follow-symlinks-opt", "--expected-size", "--checksum-algorithm",
    "--checksum-mode", "--delete-opt",
}
# aws global flags that take no value (raw-text backstop option skipping).
BS_BOOL_OPTS = {
    "--no-cli-pager", "--debug", "--no-verify-ssl", "--no-paginate",
    "--no-sign-request", "--no-cli-auto-prompt",
}
# Every aws global option. The CLI parses them with argparse, which accepts any
# unique prefix (`--prof X` is `--profile X`), so options are canonicalised
# against this list before they are interpreted.
GLOBAL_OPTS = GLOBAL_VALUE_OPTS | BS_BOOL_OPTS | {"--version"}
# Input-size caps: shlex builds a token one character at a time (quadratic), so
# an oversized command skips the structural layer and goes to the linear text
# rules.
MAX_CMD_CHARS = 200_000
MAX_WORD_CHARS = 20_000
READ_EXACT = {
    "batch-get-item", "query", "scan", "filter-log-events", "head-object",
    "help",
}
# Wrapper commands -> their options that consume a following value. The
# wrapped command is whatever follows the options (and, for timeout, the
# DURATION positional).
WRAPPERS = {
    "env": {"-u", "--unset", "-C", "--chdir"},
    "command": set(),
    "builtin": set(),
    "exec": {"-a"},
    "time": {"-f", "--format", "-o", "--output"},
    "nohup": set(),
    "sudo": {
        "-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt",
        "-C", "-D", "--chdir", "-r", "--role", "-t", "--type", "-U", "-T",
        "-R", "--chroot",
    },
    "nice": {"-n", "--adjustment"},
    "timeout": {"-k", "--kill-after", "-s", "--signal"},
    "xargs": {
        "-I", "-n", "-L", "-P", "-d", "-E", "-s", "-a", "-J", "--max-args",
        "--max-lines", "--max-procs", "--delimiter", "--arg-file",
        "--max-chars", "--eof",
    },
    "stdbuf": {"-i", "-o", "-e", "--input", "--output", "--error"},
    "watch": {"-n", "--interval"},
    "if": set(), "then": set(), "else": set(), "elif": set(), "do": set(),
    "while": set(), "until": set(), "!": set(), "{": set(),
}
UV_RUN_VALUE_OPTS = {
    "--with", "--python", "-p", "--project", "--directory", "--env-file",
    "--group", "--extra", "--package", "--with-requirements", "--index",
    "--with-editable", "--no-group", "--only-group", "--config-file",
    "--cache-dir", "--script", "-s", "-w",
}
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# A shell redirection token: `> f`, `>>f`, `< f`, `2> f` (group 1 is the target
# when attached to the operator).
REDIR_RE = re.compile(r"^\d*(?:>>|>|<<<|<<|<)(.*)$")
PROFILE_VARS = ("AWS_PROFILE", "AWS_DEFAULT_PROFILE")
# The ${VAR:-default} default is bounded so a run of unterminated `${a:-` stays
# linear.
VAR_RE = re.compile(r"\$\{(\w+)(?:(:?[-=+?])([^}]{0,512}))?\}|\$(\w+)")
# `:` is excluded from the lookbehind so `arn:aws:...` is not an aws command.
# `:-aws` (`${AWS_BIN:-aws}`) still counts: it is an aws command word.
CMD_WORD_RE = re.compile(
    r"(?:(?<![A-Za-z0-9_:-])|(?<=:-))(?:aws|awscli|terraform|terragrunt|tofu)(?![A-Za-z0-9_-])",
    re.I,
)
AWS_WORD_RE = re.compile(r"(?<![A-Za-z0-9_-])aws(?![A-Za-z0-9_-])", re.I)
BS_AWS_RE = re.compile(r"(?<![A-Za-z0-9_:-])aws(?![A-Za-z0-9_-])", re.I)
TF_WORD_RE = re.compile(
    r"(?<![A-Za-z0-9_-])(?:terraform|terragrunt|tofu)(?![A-Za-z0-9_-])"
)
# Linear, order-independent secret-read check, see secret_text_hit().
SECRET_AWS_RE = re.compile(r"\baws(?:cli)?\b")
# Wrappers that append arguments the hook cannot see.
SECRET_WRAP_RE = re.compile(
    r"(?<![\w-])(?:xargs|parallel)(?![\w-])"
    r"|(?<![\w-])-(?:exec|execdir|ok|okdir)(?![\w-])"
)
# `python -m awscli` is the aws CLI too.
PYTHON_RE = re.compile(r"^python[0-9.]*$")
MUTATING_OP_RE = re.compile(
    r"^(?:put|update|delete|create|start|stop|send|purge|batch-write|"
    r"transact-write|redrive|modify|terminate|reboot|restore|tag|untag|attach|"
    r"detach|associate|disassociate|enable|disable|register|deregister|reset|"
    r"set|add|remove|import|cancel|run|copy|execute)-|^invoke|^publish",
    re.I,
)
# Mutating-looking prefixes that are reads: `logs start-query`, `logs
# start-live-tail`.
BACKSTOP_READ_OPS = {"start-query", "start-live-tail"}
S3_MUTATING_OPS = {"rm", "mv", "mb", "rb"}
TF_READ_SUBS = {
    "plan", "show", "output", "validate", "fmt", "init", "providers",
    "version", "graph", "console",
}
TF_STATE_READ_SUBS = {"list", "show", "pull"}
# `terraform init` flags that copy or overwrite remote state.
TF_INIT_RISKY = {"migrate-state", "force-copy", "reconfigure"}
TF_INIT_RISKY_RE = re.compile(
    r"(?<![\w-])-{1,2}(?:migrate-state|force-copy|reconfigure)(?![\w-])"
)
SEP_RE = re.compile(r"[;&|\n]")
# Raw-text sign of an indirect profile (`--profile $(..)`, `AWS_PROFILE=$P`).
# Used when the structural layer could not parse the text; bounded, so linear.
PROFILE_SUBST_RE = re.compile(
    r"(?:--p(?:r(?:o(?:f(?:i(?:le?)?)?)?)?)?(?:\s+|=)|AWS_(?:DEFAULT_)?PROFILE=)"
    r"[\"']?[^\s\"';|&]{0,200}[$`]"
)
# SDK-style mutation calls (boto3 `put_item(`, node `PutItemCommand`, `.invoke(`):
# a text rule for non-aws binaries that name prod. Case-sensitive on purpose.
SDK_MUTATION_RE = re.compile(
    r"\b(?:put|update|delete|create|start|stop|send|purge|invoke|batch_write|"
    r"transact_write|redrive|terminate|modify|publish|copy|upload)_[a-z_]+\("
    r"|\.(?:invoke|publish)\("
    r"|\b(?:Put|Update|Delete|Create|Start|Stop|Send|Purge|Invoke|BatchWrite|"
    r"TransactWrite|Redrive|Terminate|Publish|Copy)[A-Za-z]*Command\b"
    r"|\.(?:put_item|delete_item|update_item|batch_writer)\b"
)
# Reads that look like mutations: boto3 `logs.start_query(` (Logs Insights).
SDK_READ_CALLS = ("start_query(", "start_live_tail(")
# Facts gathered by the structural pass.
#   seen       aws/terraform/tofu invocations the pass looked at
#   unknown    a profile that could not be resolved
#   indirect   a command word that is still unresolved after expansion
#   unjudged   aws whose arguments the pass cannot see (parallel, find -exec, a
#              command cut at `$(...)`): the text rules judge it
#   nonread    an invocation that is not provably a read (profile ignored)
STATS = {"seen": 0, "unknown": False, "indirect": False, "unjudged": False,
         "nonread": False}
RAW_CMD = {"cmd": None}


def expand(val, env, depth=0, missing=None):
    """Expand $VAR, ${VAR}, ${VAR:-default}, ${VAR-default} against env.

    Names that are referenced without a default and are not in env are
    appended to `missing` (when given): the hook cannot know their value.
    """
    if depth > 4 or "$" not in val:
        return val

    def repl(m):
        name = m.group(1) or m.group(4)
        op, default = m.group(2), m.group(3) or ""
        cur = env.get(name, "")
        if op in (":-", ":="):
            return cur if cur else expand(default, env, depth + 1, missing)
        if op in ("-", "="):
            return cur if name in env else expand(default, env, depth + 1, missing)
        if missing is not None and name not in env:
            missing.append(name)
        return cur

    return VAR_RE.sub(repl, val)


def unresolved(val):
    """True when val still holds a substitution the hook cannot evaluate."""
    return "$" in val or "`" in val


def expand_assign(val, env):
    """Expand an assignment value; an unknowable value becomes UNKNOWN_PROFILE."""
    missing = []
    out = expand(val, env, 0, missing)
    if missing and not unresolved(out):
        return UNKNOWN_PROFILE
    return out


def classify(tok, env):
    """Expand a service/op token. Returns (value, is_variable)."""
    missing = []
    val = expand(tok, env, 0, missing)
    return val, bool(missing) or unresolved(val)


def is_prod(profile):
    return bool(profile) and profile.startswith(PROD_PREFIX)


def tokenize(cmd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    segments, cur = [], []
    for tok in lex:
        if tok and set(tok) <= set(";&|()\n"):
            if cur:
                segments.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        segments.append(cur)
    return segments


def resolve_profile_value(val, env, proc):
    """Expand a --profile value against the shell env; empty falls back to the
    environment the aws process will actually see (proc)."""
    missing = []
    out = expand(val, env, 0, missing)
    if missing and not unresolved(out):
        return UNKNOWN_PROFILE
    return out or env_profile(proc)


def env_profile(env):
    return env.get("AWS_PROFILE") or env.get("AWS_DEFAULT_PROFILE")


def canon_opt(name):
    """Canonicalise an abbreviated aws global option (argparse unique prefix).

    `--prof` -> `--profile`. Ambiguous or unknown names come back unchanged.
    """
    if name in GLOBAL_OPTS or len(name) < 3 or not name.startswith("--"):
        return name
    hits = [g for g in GLOBAL_OPTS if g.startswith(name)]
    return hits[0] if len(hits) == 1 else name


def aws_parts(args):
    """Return (service, op, op_index, profile_flag) for the args after `aws`."""
    profile = None
    service = op = None
    op_index = -1
    i = 0
    while i < len(args):
        a = args[i]
        r = redirect_len(a)
        if r:
            i += r
            continue
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            name = canon_opt(name)
            if name == "--profile":
                if eq:
                    profile = val
                elif i + 1 < len(args):
                    profile = args[i + 1]
                    i += 1
            elif not eq and name in GLOBAL_VALUE_OPTS:
                i += 1
        elif service is None:
            service = a
        elif op is None:
            op = a
            op_index = i
        i += 1
    return service, op, op_index, profile


def redirect_len(a):
    """Tokens a shell redirection occupies: 0 when a is not one, else 1 or 2."""
    m = REDIR_RE.match(a)
    if not m:
        return 0
    return 1 if m.group(1) else 2


def s3_positionals(args):
    pos = []
    i = 0
    while i < len(args):
        a = args[i]
        r = redirect_len(a)
        if r:
            i += r
            continue
        if a.startswith("--"):
            if "=" not in a and canon_opt(a) in S3_VALUE_OPTS:
                i += 1
        elif a == "-" or not a.startswith("-"):
            pos.append(a)
        i += 1
    return pos


def note_verdict(unknown):
    """Record that an invocation was looked at (and whether its profile is unknown)."""
    STATS["seen"] += 1
    if unknown:
        STATS["unknown"] = True


def has_repl(tok, repl):
    """True when tok holds an xargs replace string (default `{}`)."""
    return any(r and r in tok for r in repl)


def aws_read_ok(service, op, args, op_index, env=None, repl=frozenset()):
    """True when `aws service op` is on the read allow-list (any profile).

    env expands the s3 cp/sync positionals; repl holds the xargs replace strings.
    """
    if service in ("configure", "help"):
        return True
    if service == "sso" and op in ("login", "logout"):
        return True
    if re.match(r"^(describe|get|list)-", op) or op in READ_EXACT:
        return True
    if service == "logs" and op in ("start-query", "tail"):
        return True
    if service == "s3" and op in ("ls", "presign"):
        return True
    if service == "s3" and op in ("cp", "sync"):
        pos = s3_positionals(args[op_index + 1:])
        if len(pos) != 2:
            return False
        src, _ = classify(pos[0], env or {})
        dest, dvar = classify(pos[1], env or {})
        # A read only when the destination is a literal local path (or `-`): a
        # variable, substitution or xargs replace string could be an s3 URL.
        return (
            src.lower().startswith("s3://")
            and not dvar
            and not has_repl(pos[1], repl)
            and not dest.lower().startswith("s3://")
            and "arn:aws:s3" not in dest
        )
    return False


def check_aws(args, env, proc, xa=(False, frozenset())):
    """Judge one `aws` invocation.

    env is the shell scope (used to expand words); proc is the environment the
    aws process will see (AWS_PROFILE etc., after any `env -u`/`-i`). xa is
    (under xargs, xargs replace strings): xargs appends or substitutes
    arguments the hook cannot see.
    """
    wrapped, repl = xa
    service_raw, op_raw, op_index, flag_profile = aws_parts(args)
    profile = (
        resolve_profile_value(flag_profile, env, proc)
        if flag_profile
        else env_profile(proc)
    )
    prod = is_prod(profile)
    unknown = bool(profile) and unresolved(profile) and not prod
    if service_raw is None and not wrapped:
        note_verdict(unknown or prod)
        if any(unresolved(a) for a in args):
            # `aws --profile $(x) svc op`: the tokeniser split the command at the
            # substitution, so the real service/op are not visible here. The
            # text rules judge it (a prod profile counts as unknown so they run).
            STATS["unjudged"] = True
            return None
        STATS["nonread"] = True
        if prod and "--version" not in args:
            return (
                "BLOCKED: prod is read-only (profile '%s'): 'aws' with no service or\n"
                "operation cannot be verified as a read. Spell the command out, or\n"
                "hand it to the user." % profile
            )
        return None
    if service_raw is None:
        service, svar = "", False
    else:
        service, svar = classify(service_raw, env)
    if op_raw is None:
        # An op cut off after a variable service (`aws $(x) get-...` splits at
        # the parenthesis) is just as unverifiable as a variable op.
        op, ovar = "", svar
    else:
        op, ovar = classify(op_raw, env)
    s_secret = service == "secretsmanager"
    o_secret = op in SECRET_OPS
    # Under xargs a missing or replace-string half comes from stdin: unknown,
    # which only matters next to a secret half (a plain `xargs aws` is not one).
    s_unk = svar or (wrapped and (service_raw is None or has_repl(service_raw, repl)))
    o_unk = ovar or (wrapped and (op_raw is None or has_repl(op_raw, repl)))
    if (
        (svar and (ovar or o_secret))
        or (ovar and s_secret)
        or (s_unk and o_secret)
        or (o_unk and s_secret)
        or (not svar and not ovar and s_secret and o_secret)
    ):
        return (
            "BLOCKED: 'aws %s %s' is never allowed (any profile).\n"
            "Secret values must not enter context. Use the aws-secrets-manager\n"
            "skill's runtime-resolution pattern instead:\n"
            "    {{resolve:secretsmanager:<secret-id>:SecretString:<json-key>}}\n"
            "(a variable service/operation next to a secret half is treated as a\n"
            "secret read because the hook cannot see its value)."
            % (service_raw, op_raw or "")
        )
    if svar or ovar:
        STATS["nonread"] = True
        if prod or unknown:
            return (
                "BLOCKED: 'aws %s %s' on %s profile: the service or operation comes\n"
                "from a shell variable or substitution, so the hook cannot tell whether\n"
                "it is a read. Spell the command out literally, or hand it to the user."
                % (service_raw, op_raw or "", "a prod" if prod else "an unverifiable")
            )
        note_verdict(False)
        return None
    read = aws_read_ok(service, op, args, op_index, env, repl)
    if not read:
        STATS["nonread"] = True
    if unknown:
        # Profile unknowable: no structural verdict; the backstop judges the op.
        note_verdict(True)
        return None
    note_verdict(False)
    if not prod or read:
        return None
    return (
        "BLOCKED: prod is read-only (profile '%s'): 'aws %s %s' can modify data.\n"
        "Per CLAUDE.md, never modify prod. Write up the exact change (command,\n"
        "target, and why) and hand it to the user to run; do not run it yourself.\n"
        "Allowed on prod: describe-*, get-*, list-*, query, scan, batch-get-item,\n"
        "filter-log-events, logs start-query/tail, s3 ls|presign, s3 cp|sync\n"
        "s3:// -> local."
        % (profile, service, op)
    )


def terraform_sub(args):
    """Return (subcommand, state_subcommand) from the args after `terraform`."""
    rest = [a for a in args if not a.startswith("-")]
    sub = rest[0] if rest else None
    state_sub = None
    if sub == "state":
        for a in args[args.index("state") + 1:]:
            if not a.startswith("-"):
                state_sub = a
                break
    return sub, state_sub


def init_is_risky(args):
    return any(
        a.lstrip("-").partition("=")[0] in TF_INIT_RISKY
        for a in args
        if a.startswith("-")
    )


def tf_read_ok(sub, state_sub, args):
    """True for a terraform/tofu subcommand that does not modify anything."""
    if sub == "init" and init_is_risky(args):
        return False
    return sub is None or sub in TF_READ_SUBS or (
        sub == "state" and state_sub in TF_STATE_READ_SUBS
    )


def check_terraform(args, proc):
    profile = env_profile(proc)
    prod = is_prod(profile)
    sub, state_sub = terraform_sub(args)
    if not tf_read_ok(sub, state_sub, args):
        STATS["nonread"] = True
    if bool(profile) and unresolved(profile) and not prod:
        note_verdict(True)
        return None
    note_verdict(False)
    if not prod:
        return None
    if sub == "init" and init_is_risky(args):
        return (
            "BLOCKED: 'terraform init' with -migrate-state, -force-copy or\n"
            "-reconfigure under a prod AWS profile ('%s') can copy or overwrite\n"
            "remote state. Hand the command to the user." % profile
        )
    if sub is None or sub in TF_READ_SUBS:
        return None
    if sub == "state" and state_sub in TF_STATE_READ_SUBS:
        return None
    shown = "state %s" % state_sub if sub == "state" and state_sub else sub
    return (
        "BLOCKED: 'terraform %s' with a prod AWS profile ('%s').\n"
        "Prod is read-only for Claude. Allowed under prod: plan, show, output,\n"
        "validate, fmt, init, providers, version, graph, console, state\n"
        "list|show|pull. Show the change with 'terraform plan', then hand the\n"
        "mutating command to the user." % (shown, profile)
    )


def skip_wrapper(seg, i, name):
    """Return the index just past a wrapper command's own options/positionals."""
    value_opts = WRAPPERS[name]
    i += 1
    while i < len(seg) and seg[i].startswith("-") and seg[i] != "-":
        flag = seg[i]
        i += 1
        if flag == "--":
            break
        if flag in value_opts and i < len(seg):
            i += 1
    if name == "timeout" and i < len(seg):
        i += 1  # DURATION
    return i


def skip_mise_exec(seg, i):
    """`mise exec|x [tools] -- cmd`: return the index of cmd."""
    j = i + 2
    if "--" in seg[j:]:
        return seg.index("--", j) + 1
    while j < len(seg) and (seg[j].startswith("-") or "@" in seg[j]):
        j += 1
    return j


def skip_uv_run(seg, i):
    """`uv run [opts] [--] cmd`: return the index of cmd."""
    j = i + 2
    while j < len(seg) and seg[j].startswith("-") and seg[j] != "-":
        flag = seg[j]
        j += 1
        if flag == "--":
            break
        if flag in UV_RUN_VALUE_OPTS and j < len(seg):
            j += 1
    return j


def xargs_repl(opts):
    """Replace strings named by the options of an xargs wrapper (`{}` always)."""
    repl = {"{}"}
    n = len(opts)
    for k, o in enumerate(opts):
        if o in ("-I", "-J") and k + 1 < n:
            repl.add(opts[k + 1])
        elif o.startswith(("-I", "-J")) and len(o) > 2:
            repl.add(o[2:])
        elif o.startswith("--replace="):
            repl.add(o.partition("=")[2])
        elif o.startswith("-i") and len(o) > 2 and not o.startswith("--"):
            repl.add(o[2:])
    return repl


# GNU env long options with a prefix-match target (getopt_long accepts any
# unique prefix).
ENV_LONG_OPTS = ("--ignore-environment", "--unset", "--chdir")


def env_wrapper(seg, i):
    """Parse the options of `env` at seg[i].

    Returns (index just past them, ops). ops are ("clear", None) for -i / - /
    --ignore-environment and ("unset", NAME) for -u / --unset.
    """
    ops = []
    i += 1
    while i < len(seg) and seg[i].startswith("-"):
        flag = seg[i]
        i += 1
        if flag == "-":
            ops.append(("clear", None))
        elif flag == "--":
            break
        elif flag.startswith("--"):
            name, eq, val = flag.partition("=")
            hits = [o for o in ENV_LONG_OPTS if o.startswith(name)] if len(name) > 2 else []
            full = hits[0] if len(hits) == 1 else name
            if full == "--ignore-environment":
                ops.append(("clear", None))
            elif full == "--unset":
                if eq:
                    ops.append(("unset", val))
                elif i < len(seg):
                    ops.append(("unset", seg[i]))
                    i += 1
            elif full == "--chdir" and not eq and i < len(seg):
                i += 1
        else:
            j = 1
            while j < len(flag):
                c = flag[j]
                if c == "i":
                    ops.append(("clear", None))
                    j += 1
                elif c in "uC":
                    rest = flag[j + 1:]
                    if not rest and i < len(seg):
                        rest = seg[i]
                        i += 1
                    if c == "u" and rest:
                        ops.append(("unset", rest))
                    break
                else:
                    j += 1
    return i, ops


def find_command(seg, env):
    """Strip assignments and wrappers.

    Returns (index, seg_env, proc_env, xa). seg_env is the shell scope (inline
    assignments included) used to expand words. proc_env is what the command
    will actually see: seg_env minus whatever `env -u` / `env -i` removed.
    xa is (under xargs, xargs replace strings).
    """
    seg_env = dict(env)
    proc = seg_env
    wrapped, repl = False, frozenset()
    i = 0
    while i < len(seg):
        t = seg[i]
        base = os.path.basename(t)
        if ASSIGN_RE.match(t):
            k, _, v = t.partition("=")
            val = expand_assign(v, seg_env)
            seg_env[k] = val
            if proc is not seg_env:
                proc[k] = val
            i += 1
        elif base == "env" and " " not in t:
            i, ops = env_wrapper(seg, i)
            for op, name in ops:
                if proc is seg_env:
                    proc = dict(seg_env)
                if op == "clear":
                    proc.clear()
                else:
                    proc.pop(name, None)
        elif base in WRAPPERS and " " not in t:
            start = i
            i = skip_wrapper(seg, i, base)
            if base == "xargs":
                wrapped = True
                repl = frozenset(repl | xargs_repl(seg[start + 1:i]))
        elif base == "mise" and i + 1 < len(seg) and seg[i + 1] in ("exec", "x"):
            i = skip_mise_exec(seg, i)
        elif base == "uv" and i + 1 < len(seg) and seg[i + 1] == "run":
            i = skip_uv_run(seg, i)
        else:
            break
    return i, seg_env, proc, (wrapped, repl)


def is_shell_c_flag(a):
    """True for -c and combined short flags containing c (-lc, -ec, ...)."""
    body = a[1:]
    return (
        a.startswith("-")
        and not a.startswith("--")
        and body.isascii()
        and body.isalpha()
        and "c" in body
    )


def python_awscli_args(args):
    """Args after `-m awscli` in a python command line, else None."""
    for j, a in enumerate(args):
        if a == "-m" and j + 1 < len(args) and args[j + 1] == "awscli":
            return args[j + 2:]
        if a == "-mawscli":
            return args[j + 1:]
    return None


def analyze(cmd, env, depth=0, xa=(False, frozenset())):
    if depth > 4:
        return None
    env = dict(env)
    for seg in tokenize(cmd):
        i, seg_env, proc, (w, r) = find_command(seg, env)
        if i >= len(seg):
            # Pure assignment segment (VAR=x) persists for later segments.
            env = seg_env
            continue
        xa_seg = (xa[0] or w, frozenset(xa[1] | r))
        if " " in seg[i]:
            resolved, cvar = seg[i], False
        else:
            resolved, cvar = classify(seg[i], seg_env)
        if cvar:
            # An unresolved command word (`$(which aws)`, `$X`) could be anything,
            # aws included: no structural verdict can be trusted.
            STATS["indirect"] = True
        name = os.path.basename(resolved)
        args = seg[i + 1:]
        if name in ("export", "declare", "typeset"):
            for a in args:
                if ASSIGN_RE.match(a):
                    k, _, v = a.partition("=")
                    env[k] = expand_assign(v, env)
            continue
        if name == "unset":
            for a in args:
                env.pop(a, None)
                if a in PROFILE_VARS:
                    env[a] = ""
            continue
        msg = None
        py_args = python_awscli_args(args) if PYTHON_RE.match(name) else None
        if " " in seg[i]:
            # e.g. `watch 'aws ...'`, `env -S 'aws ...'`: the "command" is a
            # whole command line.
            msg = analyze(" ".join(seg[i:]), proc, depth + 1, xa_seg)
        elif " " in resolved.strip():
            # A variable holding a whole command (`C="aws x y"; $C`).
            msg = analyze(" ".join([resolved] + args), proc, depth + 1, xa_seg)
        elif name in ("aws", "awscli"):
            msg = check_aws(args, seg_env, proc, xa_seg)
        elif py_args is not None:
            msg = check_aws(py_args, seg_env, proc, xa_seg)
        elif name in ("terraform", "terragrunt", "tofu"):
            msg = check_terraform(args, proc)
        elif name == "eval":
            msg = analyze(" ".join(args), proc, depth + 1, xa_seg)
        elif name in ("bash", "sh", "zsh"):
            for j, a in enumerate(args):
                if is_shell_c_flag(a) and j + 1 < len(args):
                    msg = analyze(args[j + 1], proc, depth + 1, xa_seg)
                    break
        elif name in ("parallel", "find") and any(AWS_WORD_RE.search(a) for a in args):
            STATS["unjudged"] = True
        if msg:
            return msg
    return None


# ---- raw-text backstop -----------------------------------------------------

BS_MAX_WORDS = 24
BS_WINDOW = 1000


def bs_close_paren(text, i, n):
    """text[i] is '(': return the index just past its matching ')'."""
    depth = 0
    while i < n:
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def bs_words(text, start):
    """Words of the shell command beginning at text[start:] (bounded scan).

    Quotes, $(...), ${...} and backtick groups stay inside their word. The scan
    stops at ; & | newline or a bare parenthesis. Redirection operators and
    their targets are dropped.
    """
    n = min(len(text), start + BS_WINDOW)
    words = []
    cur = []
    drop = False  # the next word is a redirection target
    seen = 0  # words scanned, including dropped redirection targets

    def flush():
        nonlocal drop, seen
        if cur:
            word = "".join(cur)
            del cur[:]
            seen += 1
            if drop:
                drop = False
            else:
                words.append(word)

    i = start
    while i < n and seen < BS_MAX_WORDS:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c in " \t\r":
            flush()
            i += 1
            continue
        if c in ";|\n()":
            break
        if c in "<>" or (c == "&" and nxt == ">"):
            if cur and "".join(cur).isdigit():
                del cur[:]  # a file-descriptor prefix such as the 2 in 2>&1
            else:
                flush()
            while i < n and text[i] in "&<>|":
                i += 1
            drop = True
            continue
        if c == "&":
            break
        if c == "$" and nxt == "(":
            j = bs_close_paren(text, i + 1, n)
        elif c == "$" and nxt == "{":
            j = text.find("}", i, n)
            j = n if j < 0 else j + 1
        elif c in "`'":
            j = text.find(c, i + 1, n)
            j = n if j < 0 else j + 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
        elif c == "\\":
            j = min(i + 2, n)
        else:
            j = i + 1
        cur.append(text[i:j])
        i = j
    flush()
    return words


def bs_is_option(w):
    return w.startswith("-") and w != "-"


def bs_parse(words):
    """Return (service, op, rest) from the words after an `aws` token.

    Global options are skipped. Before the service an unknown `--x` followed by
    a non-`--` word is treated as an `--x value` pair; after it only known
    value options consume a word. rest[0] is op; for s3 it also holds every
    positional that follows.
    """
    pos = []
    i = 0
    n = len(words)
    while i < n and len(pos) < 2:
        w = words[i]
        if bs_is_option(w):
            if "=" in w or canon_opt(w) in BS_BOOL_OPTS:
                i += 1
            elif not pos and i + 1 < n and not words[i + 1].startswith("--"):
                i += 2
            elif pos and canon_opt(w) in S3_VALUE_OPTS:
                i += 2
            else:
                i += 1
        else:
            pos.append(w.strip("'\""))
            i += 1
    if not pos:
        return None, None, []
    rest = pos[1:]
    if pos[0].lower() == "s3" and len(pos) == 2:
        while i < n:
            w = words[i]
            if bs_is_option(w):
                i += 2 if ("=" not in w and canon_opt(w) in S3_VALUE_OPTS) else 1
            else:
                rest.append(w.strip("'\""))
                i += 1
    return pos[0], (pos[1] if len(pos) > 1 else None), rest


def aws_invocations(text):
    """Yield (service, op, rest) for every `aws` word in text."""
    for m in BS_AWS_RE.finditer(text):
        yield bs_parse(bs_words(text, m.end()))


def ssm_secret_ref(low):
    """SSM get-parameter(s) on the Secrets Manager reference path returns the secret."""
    return "/aws/reference/secretsmanager" in low and bool(SSM_GET_RE.search(low))


def secret_text_hit(text, indirect):
    """Order-independent secret-read check on the raw text. Linear.

    `get-secret-value` (also batch-) anywhere, together with `secretsmanager`,
    an aws/awscli word, an xargs/parallel/find -exec wrapper or an unresolved
    command word (indirect). The order of the words does not matter: wrappers
    take the service/operation from stdin, which comes before `aws`.
    """
    low = text.lower()
    if ssm_secret_ref(low):
        return True
    if MCP_SECRET_RE.search(text) and any(w in low for w in SECRET_SDK_WORDS):
        return True
    if "get-secret-value" not in low:
        return False
    if "secretsmanager" in low:
        return True
    return bool(SECRET_AWS_RE.search(low) or SECRET_WRAP_RE.search(low) or indirect)


def var_word(w):
    """A word the hook cannot evaluate: `$x`, a substitution or an xargs `{}`."""
    return unresolved(w) or "{}" in w


def backstop_secret_vars(text):
    """Variable service/op next to a secret half (text order does not matter)."""
    for service, op, _ in aws_invocations(text):
        if service is None:
            continue
        svar = var_word(service)
        ovar = var_word(op) if op is not None else svar
        sl, ol = service.lower(), (op or "").lower()
        if (
            (svar and (ovar or ol in SECRET_OPS))
            or (ovar and sl == "secretsmanager")
            or (not svar and not ovar and sl == "secretsmanager" and ol in SECRET_OPS)
        ):
            return "aws %s %s" % (service, op or "")
    return None


def backstop_aws_one(service, op, rest):
    sl, ol = service.lower(), (op or "").lower()
    if var_word(service) or (op is not None and var_word(op)):
        return "aws %s %s (service/operation is a variable)" % (service, op or "")
    if MUTATING_OP_RE.match(sl) or sl in S3_MUTATING_OPS:
        # A real service name never looks like an operation, so this is an
        # option value mistaken for the service (`--flag s3 rm ...`).
        return "aws %s" % service
    if MUTATING_OP_RE.match(ol) and not (sl == "logs" and ol in BACKSTOP_READ_OPS):
        return "aws %s %s" % (service, op)
    if sl == "s3":
        if ol in S3_MUTATING_OPS:
            return "aws s3 %s" % ol
        if ol in ("cp", "sync"):
            for t in rest[2:]:
                if t.lower().startswith("s3://") or "arn:aws:s3" in t or var_word(t):
                    return "aws s3 %s with an s3 or non-literal destination" % ol
    return None


def backstop_aws(text, in_prod_ctx):
    """Judge the service/operation position after each `aws` word."""
    if not in_prod_ctx:
        return None
    for service, op, rest in aws_invocations(text):
        if service is None:
            # `$(which aws) ...`, `xargs aws --profile P` (service from stdin):
            # nothing to judge, so it cannot be called a read.
            return "aws (no service or operation after the aws word)"
        hit = backstop_aws_one(service, op, rest)
        if hit:
            return hit
    return None


def backstop_terraform(text, in_prod_ctx):
    if not in_prod_ctx:
        return None
    for m in re.finditer(
        r"(?<![A-Za-z0-9_-])(?:terraform|terragrunt|tofu)(?![A-Za-z0-9_-])"
        r"((?:\s+-\S+)*)\s+([A-Za-z][\w-]*)(?:\s+(?:-\S+\s+)*([A-Za-z][\w-]*))?",
        text,
    ):
        sub, nxt = m.group(2), m.group(3)
        if sub == "init":
            window = text[m.end(2): m.end(2) + 1000]
            cut = SEP_RE.search(window)
            if cut:
                window = window[:cut.start()]
            if TF_INIT_RISKY_RE.search(window):
                return "terraform init (state-copying flag)"
            continue
        if sub in TF_READ_SUBS:
            continue
        if sub == "state" and nxt in TF_STATE_READ_SUBS:
            continue
        return "terraform %s%s" % (sub, " " + nxt if sub == "state" and nxt else "")
    return None


def backstop(cmd, env, trusted, indirect):
    """Raw-text safety net. Returns a block message or None."""
    if secret_text_hit(cmd, indirect):
        return (
            "BLOCKED (raw-text backstop): this command reads a Secrets Manager\n"
            "secret value (get-secret-value next to secretsmanager, an aws word, an\n"
            "xargs/parallel/find -exec wrapper or an indirect command word). Never\n"
            "allowed on any profile. Use the aws-secrets-manager skill's\n"
            "runtime-resolution pattern. If this is a false positive, ask the user\n"
            "to run it."
        )
    if trusted:
        return None
    hit = backstop_secret_vars(cmd)
    if hit:
        return (
            "BLOCKED (raw-text backstop): '%s' names a Secrets Manager read through\n"
            "a shell variable or substitution and the command could not be fully\n"
            "verified structurally. Never allowed on any profile. Spell it out\n"
            "literally or ask the user to run it." % hit
        )
    literal = PROD_PREFIX in cmd.lower()
    env_prod = is_prod(env_profile(env))
    unknown = STATS["unknown"] or bool(PROFILE_SUBST_RE.search(cmd))
    ctx_aws = literal or unknown or (env_prod and bool(AWS_WORD_RE.search(cmd)))
    ctx_tf = literal or unknown or (env_prod and bool(TF_WORD_RE.search(cmd)))
    hit = backstop_aws(cmd, ctx_aws) or backstop_terraform(cmd, ctx_tf)
    if hit:
        return (
            "BLOCKED (raw-text backstop): '%s' looks like a prod mutation and the\n"
            "command could not be fully verified structurally (unparseable text,\n"
            "unrecognised wrapper, unknown/indirect profile, or the text names %s).\n"
            "Prod is read-only per CLAUDE.md. Hand the exact command to the user\n"
            "to run. If this is a false positive (e.g. the text is only quoted or\n"
            "echoed), ask the user to run it themselves." % (hit, PROD_PREFIX)
        )
    return None


def main():
    raw = sys.stdin.read()
    # Until the command is extracted, the whole input is the text a failure
    # path judges.
    RAW_CMD["cmd"] = raw
    d = json.loads(raw)
    tool = d.get("tool_name") or ""
    ti = d.get("tool_input") or d.get("input") or {}
    if MCP_TOOL_RE.search(tool):
        code = ti.get("code")
        if not isinstance(code, str):
            code = json.dumps(ti)
        RAW_CMD["cmd"] = code
        if MCP_SECRET_RE.search(code) or ssm_secret_ref(code.lower()):
            sys.stderr.write(
                "BLOCKED: AWS run_script code references GetSecretValue /\n"
                "BatchGetSecretValue (or SSM get-parameter on\n"
                "/aws/reference/secretsmanager). Secret values must never enter context.\n"
                "Use the aws-secrets-manager skill's runtime-resolution pattern:\n"
                "    {{resolve:secretsmanager:<secret-id>:SecretString:<json-key>}}\n"
            )
            return 2
        return 0
    cmd = ti.get("command", "")
    if not isinstance(cmd, str) or not cmd:
        return 0
    RAW_CMD["cmd"] = cmd
    env = dict(os.environ)
    msg = None
    parsed = False
    for k, v in (("seen", 0), ("unknown", False), ("indirect", False),
                 ("unjudged", False), ("nonread", False)):
        STATS[k] = v
    if len(cmd) > MAX_CMD_CHARS or any(len(w) > MAX_WORD_CHARS for w in cmd.split()):
        # shlex is quadratic in token length: skip the structural layer. The
        # linear text rules (secrets, prod literal) still judge the command.
        pass
    else:
        try:
            msg = analyze(cmd, env)
            parsed = True
        except Exception:
            # Unparseable (ValueError: unbalanced quotes, heredoc apostrophe) or
            # an unexpected error: fall through to the backstop, never straight
            # to allow.
            parsed = False
    literal = PROD_PREFIX in cmd.lower()
    # P1: when the text names prod, the profile the parser resolved is not
    # trusted (abbreviated flags, env wrappers, indirect binaries and wrappers
    # can all hide the real one). Every invocation it saw must be a read, and no
    # command word may be unresolved.
    if not msg and literal and (STATS["nonread"] or STATS["indirect"]):
        msg = (
            "BLOCKED: prod is read-only: the command names %s and is not\n"
            "provably a read (an aws/terraform/tofu operation that is not on the\n"
            "read allow-list, a missing service/operation, or an indirect command\n"
            "word such as $(which aws)). The resolved profile is not trusted when\n"
            "prod is named. Hand the exact command to the user to run. Allowed:\n"
            "describe-*, get-*, list-*, query, scan, batch-get-item,\n"
            "filter-log-events, logs start-query/tail, s3 ls|presign, s3 cp|sync\n"
            "s3:// -> local, terraform plan/show/output/..." % PROD_PREFIX
        )
    # P4: a non-aws binary (python, node, ...) that names prod and holds an
    # SDK-style mutation call. Text rule only; the code is not parsed.
    call = next(
        (m.group(0) for m in SDK_MUTATION_RE.finditer(cmd)
         if m.group(0) not in SDK_READ_CALLS),
        None,
    ) if literal and not msg else None
    if call:
        msg = (
            "BLOCKED: prod is read-only: the command names %s and contains an\n"
            "SDK-style mutation call ('%s'). Prod writes are never run by Claude.\n"
            "Hand the exact script/command to the user to run. SDK reads\n"
            "(get_item, query, scan, describe_*, list_*) stay allowed."
            % (PROD_PREFIX, call)
        )
    # The structural verdict is trusted only when the pass parsed cleanly,
    # looked at every aws/terraform/tofu word in the text (counting indirect
    # command words as unresolved), and, unless prod is named (then the profile
    # is ignored, see P1), met no profile it could not resolve.
    trusted = (
        parsed
        and (literal or not STATS["unknown"])
        and not STATS["indirect"]
        and not STATS["unjudged"]
        and STATS["seen"] >= len(CMD_WORD_RE.findall(cmd))
    )
    if not msg:
        # Without a clean parse the command word is unknown: any `$` may be one.
        indirect = STATS["indirect"] or (not parsed and ("$" in cmd or "`" in cmd))
        msg = backstop(cmd, env, trusted, indirect)
    if msg:
        sys.stderr.write(msg + "\n")
        return 2
    return 0


def fail_closed(cmd, reason="an internal error"):
    """Unexpected failure: block loudly when the text is relevant."""
    if isinstance(cmd, str) and MENTION_RE.search(cmd):
        sys.stderr.write(
            "BLOCKED: guard-prod-readonly hit %s while checking\n"
            "a command that mentions aws/terraform/%s. Failing closed; ask the\n"
            "user to run it, or retry with a simpler command.\n" % (reason, PROD_PREFIX)
        )
        return 2
    return 0


def on_alarm(signum, frame):
    rc = fail_closed(RAW_CMD["cmd"], "its %ds time budget" % TIME_BUDGET_SECONDS)
    if rc == 0:
        sys.stderr.write(
            "guard-prod-readonly: %ds time budget exceeded; allowing a command that\n"
            "does not mention aws/terraform/%s.\n" % (TIME_BUDGET_SECONDS, PROD_PREFIX)
        )
    sys.exit(rc)


signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(TIME_BUDGET_SECONDS)
try:
    sys.exit(main())
except SystemExit:
    raise
except Exception:
    sys.exit(fail_closed(RAW_CMD["cmd"]))
PYEOF

printf '%s' "$INPUT" | python3 -c "$PY"
rc=$?
[ "$rc" -eq 2 ] && exit 2
if [ "$rc" -ne 0 ] && printf '%s' "$INPUT" | grep -Eqi 'aws|terraform|terragrunt|tofu|fb-live-us'; then
  echo "BLOCKED: guard-prod-readonly could not run to completion (python3 exit $rc)" >&2
  echo "while checking input that mentions aws/terraform/fb-live-us. Failing closed;" >&2
  echo "ask the user to run the command, or retry." >&2
  exit 2
fi
exit 0
