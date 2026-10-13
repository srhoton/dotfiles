"""pr_feedback: what is actionable on one PR, as pure functions over its GraphQL dict.

Shared by pr-fix-queue (which decides whether to launch a fix session) and
pr-context (which shows a session what it has to fix). Nothing here talks to
GitHub, reads state, or knows about cooldowns or launching. Standard library only.

The PR dict is the `pullRequest` node of the GraphQL queries those two tools
send. The fields used:
  reviewThreads.nodes[]   id isResolved isOutdated
                          firstComment.nodes[0] / lastComment.nodes[0]
                            (aliases of comments(first: 1) / comments(last: 1))
  comments.nodes[]        databaseId createdAt lastEditedAt isMinimized
                          author{login __typename}
                          reactionGroups{content viewerHasReacted}
                          reactions.nodes[]{content createdAt user{login}}
  latestOpinionatedReviews.nodes[]  id state
  reviewDecision

`me` is the viewer's login. Every function treats missing or null fields as empty.
"""

from __future__ import annotations

import re
from typing import Any


def _nodes(obj: Any, key: str) -> list[dict[str, Any]]:
    return ((obj or {}).get(key) or {}).get("nodes") or []


def thread_ends(
    thread: dict[str, Any],
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    """First and last comment of a review thread, or None for a missing end."""
    first = _nodes(thread, "firstComment")
    last = _nodes(thread, "lastComment")
    return (first[0] if first else None, last[0] if last else None)


def classify_threads(
    pr: dict[str, Any], me: str, include_bots: bool = False
) -> tuple[list[tuple[dict[str, Any], dict[str, Any], dict[str, Any]]], dict[str, int]]:
    """Split a PR's review threads into actionable ones and counts of the rest.

    A thread is actionable only if it is unresolved and not outdated, a human
    opened it (unless include_bots), and its last comment is not mine, i.e. it is
    still waiting on me. Returns ([(thread, first_comment, last_comment)], skipped)
    where skipped maps a reason to how many threads it excluded.
    """
    actionable: list[tuple[dict[str, Any], dict[str, Any], dict[str, Any]]] = []
    skipped: dict[str, int] = {}

    def skip(reason: str) -> None:
        skipped[reason] = skipped.get(reason, 0) + 1

    for t in (pr.get("reviewThreads") or {}).get("nodes") or []:
        if t.get("isResolved"):
            skip("resolved")
            continue
        if t.get("isOutdated"):
            skip("outdated")
            continue
        first, last = thread_ends(t)
        if first is None or last is None:
            skip("no comments")
            continue
        if not include_bots and (first.get("author") or {}).get("__typename") != "User":
            skip("bot-started")
            continue
        if (last.get("author") or {}).get("login") == me:
            skip("last comment is mine")
            continue
        actionable.append((t, first, last))
    return actionable, skipped


def rocketed(comment: dict[str, Any], me: str) -> bool:
    """True when I have a ROCKET on the comment that is not older than its last edit.

    reactionGroups gives exact presence; reactions(last: 20) gives the time.
    Timestamps are same-format ISO-8601 UTC, so they sort as text.
    """
    if not any(
        g.get("content") == "ROCKET" and g.get("viewerHasReacted")
        for g in comment.get("reactionGroups") or []
    ):
        return False
    mine = [
        r.get("createdAt") or ""
        for r in ((comment.get("reactions") or {}).get("nodes") or [])
        if r.get("content") == "ROCKET" and (r.get("user") or {}).get("login") == me
    ]
    if not mine:
        return (
            True  # mine is older than the newest 20 reactions; presence is still exact
        )
    return not comment.get("lastEditedAt") or max(mine) >= comment["lastEditedAt"]


def classify_comments(
    pr: dict[str, Any], me: str
) -> tuple[list[dict[str, Any]], int, dict[str, int]]:
    """Split a PR's conversation comments into unhandled ones and counts of the rest.

    Human-only, always: bot comments in the conversation are status chatter.
    A comment is handled by my ROCKET (see rocketed), nothing else. Returns
    (unhandled comments, my newest comment's databaseId or 0, skipped counts).
    """
    unhandled: list[dict[str, Any]] = []
    skipped: dict[str, int] = {}
    my_newest = 0
    for c in (pr.get("comments") or {}).get("nodes") or []:
        author = c.get("author") or {}
        if author.get("login") == me:
            my_newest = max(my_newest, c.get("databaseId") or 0)
            skipped["mine"] = skipped.get("mine", 0) + 1
            continue
        if author.get("__typename") != "User":
            skipped["bot"] = skipped.get("bot", 0) + 1
            continue
        if c.get("isMinimized"):
            skipped["minimized"] = skipped.get("minimized", 0) + 1
            continue
        if rocketed(c, me):
            skipped["handled (rocket)"] = skipped.get("handled (rocket)", 0) + 1
            continue
        unhandled.append(c)
    return unhandled, my_newest, skipped


def changes_requested_ids(pr: dict[str, Any]) -> list[str]:
    """Sorted ids of standing CHANGES_REQUESTED reviews, when reviewDecision agrees.

    latestReviews can omit a still-standing CHANGES_REQUESTED that reviewDecision
    reports; latestOpinionatedReviews keeps each reviewer's latest approval or
    change request.
    """
    ids = sorted(
        r["id"]
        for r in _nodes(pr, "latestOpinionatedReviews")
        if r.get("state") == "CHANGES_REQUESTED"
    )
    return ids if pr.get("reviewDecision") == "CHANGES_REQUESTED" else []


def already_replied_by(comment: dict[str, Any], pr: dict[str, Any], me: str) -> dict[str, Any] | None:
    """My conversation comment that already answers `comment`, or None.

    Counts only when my comment was created after the comment's last edit (its
    creation if never edited) AND its body contains `#issuecomment-<databaseId>` not followed by another digit
    (so `#issuecomment-12` is not satisfied by `#issuecomment-123`).
    Position in the conversation is never enough: a reply that predates the latest
    edit answered an older ask. Replies are always newer than the comment they
    answer, so they fall inside the newest-50 window whenever the comment does.
    """
    stamp = comment.get("lastEditedAt") or comment.get("createdAt") or ""
    anchor = re.compile(r"#issuecomment-%s(?!\d)" % re.escape(str(comment.get("databaseId"))))
    for c in (pr.get("comments") or {}).get("nodes") or []:
        if (c.get("author") or {}).get("login") != me:
            continue
        if (c.get("createdAt") or "") > stamp and anchor.search(c.get("body") or ""):
            return c
    return None
