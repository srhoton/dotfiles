export const meta = {
  name: 'review-fanout',
  description: 'Five specialist reviewers in parallel, dedup, then adversarial verification of CRITICAL/HIGH findings',
  phases: [
    { title: 'Review', detail: 'five specialist reviewers over the changed files' },
    { title: 'Verify', detail: 'one skeptic per CRITICAL/HIGH finding tries to refute it' },
  ],
}

// args: { repoRoot: string, files: string[], intent: string, scopeNote?: string }
// Invoked by ~/.claude/commands/review.md and reviewit.md (Step 2).
const { repoRoot, files, intent } = args
const scopeNote = args.scopeNote ||
  'SCOPE BOUNDS: (1) the repo root and the changed-file list above are your ENTIRE scope; ' +
  '(2) do not explore sibling repos or spawn further agents; ' +
  '(3) if evidence outside that scope seems needed, report the gap as a LOW finding instead of expanding scope.'

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'file', 'line', 'description'],
        properties: {
          severity: { type: 'string', enum: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'] },
          file: { type: 'string', description: 'path relative to the repo root' },
          line: { type: 'integer' },
          description: { type: 'string', description: "what's wrong and how to fix it" },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean', description: 'true if the finding is wrong or not a real CRITICAL/HIGH issue' },
    reason: { type: 'string', description: 'evidence from the code (file:line) supporting the verdict' },
  },
}

const header =
  `Repo root: ${repoRoot}\n` +
  `Changed files (your ENTIRE review scope):\n${files.map(f => `- ${f}`).join('\n')}\n\n` +
  `${scopeNote}\n\n`

const checklistNote =
  'Additionally check the diff against EVERY defect class in ~/.claude/knowledge/defect-classes.md ' +
  '(read that file first) — these are historically recurring fix-round defects.\n\n'

const REVIEWERS = [
  {
    key: 'functional',
    agentType: 'functional-reviewer',
    prompt: header +
      `The user's stated requirements / intent:\n${intent}\n\n` + checklistNote +
      'Review ONLY the changed files listed above for functional correctness against the stated intent.',
  },
  {
    key: 'quality',
    agentType: 'code-quality-reviewer',
    prompt: header + 'Review ONLY the changed files listed above for code quality issues.',
  },
  {
    key: 'adr',
    agentType: 'adr-compliance-reviewer',
    prompt: header +
      'Analyze ONLY the changed files listed above for compliance with Fullbay\'s accepted ADRs. ' +
      'Load ADRs dynamically from ~/git/architecture-decisions (this KB read is in scope). ' +
      'In each description, name which ADR is violated and how to fix it.',
  },
  {
    key: 'performance',
    agentType: 'performance-reviewer',
    prompt: header +
      'Review ONLY the changed files listed above for performance bottlenecks, inefficient algorithms, and optimization opportunities.',
  },
  {
    key: 'data-side-effects',
    agentType: 'data-side-effects-reviewer',
    prompt: header + checklistNote +
      'Review ONLY the changed files listed above for blast radius on already-persisted data: ' +
      'hash/sourceHash/checksum/idempotency-key/dedup-key/ID-derivation changes that would re-key or re-flag ' +
      'already-migrated records; unguarded status or flag overwrites; schema or version bumps whose companion ' +
      'artifacts (JSON schema files, fixtures, contracts) were not updated in the same change; and re-run/backfill ' +
      'safety. If the change touches no persistence, identity, status, or schema surface, return zero findings.',
  },
]

phase('Review')
// Barrier is intentional: dedup below needs the full finding set from all five reviewers.
const reviews = await parallel(REVIEWERS.map(r => () =>
  agent(r.prompt, { label: `review:${r.key}`, phase: 'Review', agentType: r.agentType, schema: FINDINGS_SCHEMA })
    .then(res => res && res.findings.map(f => ({ ...f, source: r.key })))
))
const skipped = REVIEWERS.filter((r, i) => !reviews[i]).map(r => r.key)
if (skipped.length) log(`reviewers returned nothing (skipped or errored): ${skipped.join(', ')}`)

// Dedup by file:line, merging sources; keep the highest severity and longest description.
const RANK = { CRITICAL: 0, HIGH: 1, MEDIUM: 2, LOW: 3 }
const byKey = new Map()
for (const f of reviews.filter(Boolean).flat()) {
  const k = `${f.file}:${f.line}`
  const prev = byKey.get(k)
  if (!prev) { byKey.set(k, { ...f, source: [f.source] }); continue }
  prev.source.push(f.source)
  if (RANK[f.severity] < RANK[prev.severity]) prev.severity = f.severity
  if (f.description.length > prev.description.length) prev.description = f.description
}
const deduped = [...byKey.values()].map(f => ({ ...f, source: [...new Set(f.source)].join('+') }))

const candidateActionable = deduped
  .filter(f => f.severity === 'CRITICAL' || f.severity === 'HIGH')
  .sort((a, b) => RANK[a.severity] - RANK[b.severity])
const informational = deduped.filter(f => f.severity === 'MEDIUM' || f.severity === 'LOW')

const VERIFY_CAP = 10
const toVerify = candidateActionable.slice(0, VERIFY_CAP)
const unverified = candidateActionable.slice(VERIFY_CAP)
if (unverified.length) log(`verify cap: ${unverified.length} CRITICAL/HIGH finding(s) beyond ${VERIFY_CAP} pass through UNVERIFIED`)

phase('Verify')
const verified = await parallel(toVerify.map(f => () =>
  agent(
    `Repo root: ${repoRoot}\n` +
    `A code reviewer (${f.source}) reported this ${f.severity} finding:\n` +
    `  ${f.file}:${f.line} — ${f.description}\n\n` +
    'Your job is to REFUTE it. Read the actual code (and its callers/config as needed within this repo only) ' +
    'and determine whether this is a real, reachable ' + f.severity + '-level defect. ' +
    'Reviewers over-report: a finding that is unreachable, already guarded elsewhere, based on a misread of the ' +
    'code, or real-but-minor should be refuted (real-but-minor: say so in the reason). ' +
    'Cite file:line evidence either way. If you cannot decide from the code, refuted=false.',
    { label: `verify:${f.file}:${f.line}`, phase: 'Verify', schema: VERDICT_SCHEMA }
  ).then(v => ({ finding: f, verdict: v }))
))

const actionable = []
const refuted = []
for (let i = 0; i < toVerify.length; i++) {
  const f = toVerify[i]
  const verdict = verified[i] && verified[i].verdict
  if (verdict && verdict.refuted) {
    refuted.push({ ...f, refutation: verdict.reason })
  } else if (verdict) {
    actionable.push({ ...f, verified: true, verification: verdict.reason })
  } else {
    // skeptic skipped or errored — keep the finding, flagged unverified
    actionable.push({ ...f, verified: false })
  }
}
for (const f of unverified) actionable.push({ ...f, verified: false })

log(`${actionable.length} actionable, ${refuted.length} refuted, ${informational.length} informational`)
return { actionable, informational, refuted, reviewersSkipped: skipped }
