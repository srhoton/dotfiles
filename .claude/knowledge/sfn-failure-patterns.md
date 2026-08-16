# Step Function Migration Failure Patterns

Known, previously-diagnosed failure patterns for the migration state machines. `/sfn-triage` classifies every new failure against this list **before** hypothesizing anything novel. When a triage session confirms a genuinely new pattern, append an entry here in the same format.

Entry format: **Signature** (what the failure looks like in the execution history / logs), **Root cause** (the confirmed mechanism, with evidence type), **Fix** (canonical remedy or PR reference).

---

## 1. Descope FGA 429 masked as 500

- **Signature**: Task state fails with a generic HTTP 500 from the authorization/FGA call path. The surfaced status is 500, but the raw error payload / downstream Descope response body shows rate limiting.
- **Root cause**: Descope FGA returns 429 (rate limit) under migration write bursts; an intermediate layer rewraps it as 500, so the execution history lies about the status. Never trust the surfaced HTTP status — pull the raw payload.
- **Fix**: retry with backoff on 429 at the FGA client, and/or reduce concurrent FGA writes. (Diagnosed against live dev/prod data, Jul 2026.)

## 2. DynamoDB write throttling (systemic, NOT transient)

- **Signature**: Migration lambda fails or slows with `ProvisionedThroughputExceededException` / throttled-write metrics on the target table; failures cluster across many entities in the same window.
- **Root cause**: Systemic write throttling from migration concurrency exceeding table capacity — historically mislabeled "transient" until CloudWatch throttle metrics proved it was sustained. Always check `WriteThrottleEvents` over the failure window before calling anything transient.
- **Fix**: retry/concurrency limits in the migration writer (shipped); verify table capacity mode before large batch runs.

## 3. Negative fee rate

- **Signature**: Financial migration state fails (or produces wrong figures) on entities whose fee/supplies rate is negative in source data.
- **Root cause**: Source data contains negative fee rates the transform did not anticipate; validation gap, not a pipeline error.
- **Fix**: validation/normalization in the fee transform; quantify affected entities via Athena before re-running.

## 4. Missing `partType`

- **Signature**: Parts migration state fails on records lacking the `partType` field.
- **Root cause**: Source parts records legitimately missing `partType`; mapper assumed presence.
- **Fix**: defaulting/skip logic in the parts mapper (shipped).

## 5. Missing `entity.json` contact fallback

- **Signature**: Entity migration fails or emits incomplete contact data for entities whose `entity.json` lacks primary contact fields.
- **Root cause**: No fallback when the primary contact block is absent in `entity.json`.
- **Fix**: contact fallback chain in the entity transform (shipped, verified against live dev/prod data).
