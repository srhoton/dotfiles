"""fanout_result: read a review-fanout workflow output file.

Shared by fanout-report and risk-score. The review-fanout workflow
(~/.claude/workflows/review-fanout.js) returns
{actionable, informational, refuted, reviewersSkipped, reviewersGated, files}. Its output file is
normally a JSON object {summary, agentCount, logs, result}, but this also accepts a file
that IS the bare result object, a `result` carried as a JSON-encoded string, or a file where
that JSON object is embedded in surrounding text (the outermost object containing
"actionable" is used).

Standard library only.
"""

from __future__ import annotations

import json
from typing import Any


class InputError(Exception):
    pass


def unwrap(doc: Any) -> dict[str, Any] | None:
    """Return the result object from a wrapped or bare document, else None."""
    if not isinstance(doc, dict):
        return None
    if "actionable" in doc:
        return doc
    inner = doc.get("result")
    if isinstance(inner, str):
        try:
            inner = json.loads(inner)
        except ValueError:
            return None
    if isinstance(inner, dict) and "actionable" in inner:
        return inner
    return None


def extract_result(text: str) -> dict[str, Any]:
    try:
        found = unwrap(json.loads(text))
    except ValueError:
        found = None
    if found is not None:
        return found
    # Embedded in surrounding text: the earliest '{' that decodes to an object holding
    # "actionable" (directly or under "result") is the outermost such object.
    decoder = json.JSONDecoder()
    pos = text.find("{")
    while pos != -1:
        try:
            doc, _ = decoder.raw_decode(text, pos)
        except ValueError:
            doc = None
        found = unwrap(doc)
        if found is not None:
            return found
        pos = text.find("{", pos + 1)
    raise InputError('no JSON object containing "actionable" found')


def items(result: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = result.get(key) or []
    if not isinstance(value, list):
        raise InputError(f'"{key}" is not a list')
    return [i for i in value if isinstance(i, dict)]
