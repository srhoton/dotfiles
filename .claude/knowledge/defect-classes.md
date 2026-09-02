# Defect Classes — Red-Team Checklist

Recurring defect classes that OUR OWN fix rounds have introduced, mined from session
history (Jun–Aug 2026 insights report). Reviewers: check every diff against each class
below. Fixers: re-read your diff against this list before declaring done.

Append new entries when a review round confirms a defect class not listed here
(same pattern as `sfn-failure-patterns.md`). Keep entries short: detection heuristic +
the historical example that earned the entry.

## fail-open-default
**Heuristic:** a routing/guard/filter branch whose `else`/default path ALLOWS. Trace every
new conditional to its default arm; a match-failure must deny, queue, or error — never pass through.
**History:** fail-open routing bug shipped in a round-1 fix; caught at review round 2.

## unconditioned-overwrite
**Heuristic:** any write (DDB `PutItem`/`UpdateItem`, file write, status field assignment)
without a condition expression or preceding read-compare. Ask: what does this clobber when
the record is newer/different than assumed?
**History:** repair fix round 1 introduced an unconditioned overwrite (CRITICAL).

## serializer-allowlist-drop
**Heuristic:** a new field added to a type/record that passes through any allow-list
serializer, mapper, or JSON schema. Grep for the serializer's field list; the new field
must be added there in the SAME diff or it is silently dropped.
**History:** DynamoDB marker silently dropped by an allow-list serializer (partType fix).

## stale-literal
**Heuristic:** counters, version strings, expected-count assertions, and copied literals
near the changed code. Diff-adjacent literals that encode "how many" or "which version"
must be re-derived, not trusted.
**History:** stale counter literal survived a fix and was caught a full review round later.

## vacuous-assertion
**Heuristic:** a new/changed test that cannot fail: asserts on its own stub, checks
non-null on something structurally non-null, or stubs invert the shipped config. Prove with
`~/.claude/bin/mutation-probe` — revert the fix, the test must fail.
**History:** vacuous fatal check + a contract-check script with two real HIGH bugs of its own.

## lockfile-pm-mismatch
**Heuristic:** any diff touching `pnpm-lock.yaml`/`package-lock.json`/`yarn.lock`. Verify the
repo's pinned package-manager version (`mise.toml`/`.tool-versions`/`packageManager` field) was
used and `overrides`/`resolutions` survived; validate with a frozen install (`--frozen-lockfile`).
**History:** 316-line lockfile churn from a mise-pinned pnpm mismatch; caught only by the PR reviewer.

## unverified-404-deletion
**Heuristic:** code that treats a 404/NotFound as proof of absence and proceeds to delete,
create, or skip. A 404 can be auth failure, wrong endpoint, eventual consistency, or wrong ID
format — require a positive existence check before destructive follow-ups.
**History:** repair fix round 1 shipped an unverified 404-triggered deletion (HIGH).

## warn-log-amplification
**Heuristic:** a log statement added inside a loop, retry, or per-record path. Estimate
emissions at production cardinality (records × retries); per-item warns on a million-record
migration are an ops incident, not observability.
**History:** partType fix round 1 introduced warn-log amplification; cost an extra review round.
