"""gh_prs: the read-only `gh api graphql` pieces shared by impl-plan-status and pr-status.

- gh_cmd() / run() / first_line()
                     the gh command (GH env var replaces it, for tests), a subprocess wrapper
                     that raises Failure when gh is missing, and the first non-blank line.
- graphql()          one `gh api graphql` call for a repository; returns the `repository`
                     object or raises Failure. `retries=N` repeats a call that failed with an
                     HTTP 5xx (gh's intermittent 502s) up to N more times; the default is no retry.
- fetch_prs()        {number: node} for several PRs of one repo from ONE call (aliases p<N>),
                     plus the numbers GitHub does not know. Any selection set can be asked for.
- fetch_pr_states()  the same for just {number: OPEN|MERGED|CLOSED}.
- PR_RE / split_ref  owner/repo#N references.

Only queries are ever sent; nothing here can mutate. Standard library only. Import with
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib"))
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import time
from typing import Any

PR_STATES = ("OPEN", "MERGED", "CLOSED")
PR_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)#([1-9][0-9]*)$")
PR_QUERY = (
    "query($owner:String!,$name:String!){repository(owner:$owner,name:$name){%s}}"
)

# gh prints "gh: HTTP 502: Bad Gateway" (or the HTML of the error page) on a 5xx.
TRANSIENT_RE = re.compile(
    r"HTTP 5\d\d|Bad Gateway|Service Unavailable|Gateway Time-?out", re.IGNORECASE
)
RETRY_DELAY = float(os.environ.get("GH_PRS_RETRY_DELAY", "1.0"))


class Failure(Exception):
    """gh failed or answered with something unexpected."""


def gh_cmd() -> list[str]:
    return shlex.split(os.environ.get("GH") or "gh")


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, errors="replace", check=False
        )
    except FileNotFoundError:
        raise Failure(f"'{cmd[0]}' is not installed or not on PATH") from None


def first_line(text: str) -> str:
    lines = text.strip().splitlines()
    return lines[0] if lines else ""


def graphql(
    query: str,
    owner: str,
    name: str,
    extra: dict[str, str] | None = None,
    retries: int = 0,
) -> dict[str, Any]:
    """One `gh api graphql` call; returns the `repository` object. gh exits non-zero when the
    response carries errors even if part of the data is there, so the body is parsed first.
    A call that fails with an HTTP 5xx is repeated up to `retries` more times."""
    cmd = [
        *gh_cmd(),
        "api",
        "graphql",
        "-f",
        f"query={query}",
        "-f",
        f"owner={owner}",
        "-f",
        f"name={name}",
    ]
    for k, v in (extra or {}).items():
        cmd += ["-f", f"{k}={v}"]
    attempt = 0
    while True:
        proc = run(cmd)
        try:
            doc = json.loads(proc.stdout)
        except ValueError:
            doc = None
        if not isinstance(doc, dict):
            if attempt < retries and TRANSIENT_RE.search(
                f"{proc.stderr}\n{proc.stdout}"
            ):
                attempt += 1
                time.sleep(RETRY_DELAY)
                continue
            raise Failure(
                f"gh api graphql failed for {owner}/{name}: "
                f"{first_line(proc.stderr or proc.stdout) or f'exit {proc.returncode}'}"
            )
        repo = (doc.get("data") or {}).get("repository")
        if not isinstance(repo, dict):
            errors = doc.get("errors") or []
            msg = (
                errors[0].get("message", "?")
                if errors and isinstance(errors[0], dict)
                else "no repository in the response"
            )
            if attempt < retries and TRANSIENT_RE.search(msg):
                attempt += 1
                time.sleep(RETRY_DELAY)
                continue
            raise Failure(f"gh api graphql failed for {owner}/{name}: {msg}")
        return repo


def fetch_prs(
    owner: str, name: str, numbers: list[int], fields: str, retries: int = 0
) -> tuple[dict[int, dict[str, Any]], set[int]]:
    """({number: node}, numbers GitHub does not know), from one call. `fields` is the selection
    set inside `pullRequest(number:N){...}`. Raises Failure."""
    body = " ".join(f"p{n}:pullRequest(number:{n}){{{fields}}}" for n in numbers)
    repo = graphql(PR_QUERY % body, owner, name, retries=retries)
    nodes: dict[int, dict[str, Any]] = {}
    missing: set[int] = set()
    for n in numbers:
        node = repo.get(f"p{n}", "absent")
        if node is None:
            missing.add(n)
        elif isinstance(node, dict):
            nodes[n] = node
        else:
            raise Failure(f"gh api graphql for {owner}/{name}#{n}: unexpected response")
    return nodes, missing


def fetch_pr_states(
    owner: str, name: str, numbers: list[int]
) -> tuple[dict[int, str], set[int]]:
    """({number: OPEN|MERGED|CLOSED}, numbers GitHub does not know), from one call. Raises Failure."""
    nodes, missing = fetch_prs(owner, name, numbers, "state")
    states: dict[int, str] = {}
    for n, node in nodes.items():
        if node.get("state") not in PR_STATES:
            raise Failure(f"gh api graphql for {owner}/{name}#{n}: unexpected response")
        states[n] = node["state"]
    return states, missing


def split_ref(ref: str) -> tuple[str, str, int]:
    m = PR_RE.match(ref)
    assert m is not None  # validated
    return m.group(1), m.group(2), int(m.group(3))
