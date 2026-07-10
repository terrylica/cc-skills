export const meta = {
  name: 'council-goal-audit',
  description: 'Goal→invariant conformance audit: dual letter/spirit decomposition, per-invariant auditors, refute-first skeptic pass, optional evidence probes',
  phases: [{ title: 'Decompose' }, { title: 'Audit' }, { title: 'Cross-exam' }, { title: 'Probes' }],
}

// ─── Args (SSoT: plugins/council/references/schemas.md) ─────────────────────
const A = {
  repo: args.repo,
  goal: args.goal,
  scope: args.scope ?? [],
  depth: args.depth ?? 'standard',
  base: args.base ?? null,
  seed: args.seed ?? 'council',
  runId: args.runId,
}
if (!A.repo || !A.goal || !A.runId) throw new Error('args.repo, args.goal, args.runId are required')
const SCRATCH = `tmp/council-${A.runId}`
const clip = (s, n) => (typeof s === 'string' && s.length > n ? s.slice(0, n) + '…[truncated]' : s)
const pad2 = (n) => String(n).padStart(2, '0')
function hashString(s) {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}
function mulberry32(seed) {
  let a = seed >>> 0
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
function shuffled(arr, r) {
  const a = arr.slice()
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(r() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

// ─── Schemas (inline copies; SSoT = references/schemas.md) ──────────────────
const INVARIANT = {
  type: 'object',
  required: ['id', 'statement', 'kind', 'source', 'probe'],
  properties: {
    id: { type: 'string' },
    statement: { type: 'string' },
    kind: { enum: ['hard', 'soft'] },
    source: { enum: ['explicit-goal', 'implied', 'regression-guard'] },
    probe: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
  },
  additionalProperties: false,
}
const INVARIANTS_OUT = {
  type: 'object',
  required: ['invariants'],
  properties: { invariants: { type: 'array', items: INVARIANT } },
  additionalProperties: false,
}
const FINDING = {
  type: 'object',
  required: ['file', 'line', 'category', 'severity', 'summary', 'failure_scenario', 'invariant_ids', 'suggested_probe', 'confidence'],
  properties: {
    file: { type: 'string' },
    line: { type: 'integer' },
    symbol: { type: 'string' },
    category: { enum: ['correctness', 'spec-violation', 'regression', 'security', 'data-integrity', 'concurrency', 'performance', 'test-gap', 'boundary-contract'] },
    severity: { enum: ['critical', 'major', 'minor'] },
    summary: { type: 'string', maxLength: 200 },
    failure_scenario: { type: 'string' },
    invariant_ids: { type: 'array', items: { type: 'string' } },
    evidence_pointers: { type: 'array', items: { type: 'string' } },
    suggested_probe: { type: 'string' },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
  },
  additionalProperties: false,
}
const AUDIT_OUT = {
  type: 'object',
  required: ['statuses', 'findings', 'nuances'],
  properties: {
    statuses: {
      type: 'array',
      items: {
        type: 'object',
        required: ['invariant_id', 'status', 'evidence'],
        properties: {
          invariant_id: { type: 'string' },
          status: { enum: ['satisfied', 'violated', 'partial', 'unverified'] },
          evidence: { type: 'string', maxLength: 1200 },
        },
        additionalProperties: false,
      },
    },
    findings: { type: 'array', items: FINDING },
    nuances: { type: 'array', items: { type: 'string', maxLength: 500 } },
  },
  additionalProperties: false,
}
const VERDICT = {
  type: 'object',
  required: ['finding_id', 'verdict', 'strongest_refutation', 'confidence'],
  properties: {
    finding_id: { type: 'string' },
    verdict: { enum: ['REFUTED', 'STANDS', 'UNCERTAIN'] },
    strongest_refutation: { type: 'string' },
    refutation_evidence: { type: 'array', items: { type: 'string' } },
    residual_risk: { type: 'string' },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
  },
  additionalProperties: false,
}
const VERDICTS_OUT = {
  type: 'object',
  required: ['verdicts'],
  properties: { verdicts: { type: 'array', items: VERDICT } },
  additionalProperties: false,
}
const EVIDENCE_OUT = {
  type: 'object',
  required: ['finding_id', 'evidence_class', 'reproduced'],
  properties: {
    finding_id: { type: 'string' },
    evidence_class: { enum: ['failing-test-repro', 'runtime-trace', 'static-trace', 'opinion'] },
    artifact_path: { type: 'string' },
    command: { type: 'string' },
    output_excerpt: { type: 'string', maxLength: 2000 },
    reproduced: { type: 'boolean' },
    notes: { type: 'string' },
  },
  additionalProperties: false,
}
const MERGE_OUT = INVARIANTS_OUT

const REPO_RULES = `Repository under audit (work here, absolute paths): ${A.repo}
Rules: NEVER modify tracked files. New files ONLY under ${A.repo}/${SCRATCH}/. Read-only commands are fine.`
const OUTPUT_RULES = 'Your final message is machine-parsed against a JSON schema; return ONLY the structured data. Do not reference your role in output fields.'
const scopeNote = A.scope.length ? `Audit scope is limited to: ${A.scope.join(', ')}` : 'Audit the whole implementation relevant to the goal.'
const baseNote = A.base ? `Audit the state at ref ${A.base}.` : 'Audit the current working tree.'

// ═══ P1: Dual decomposition ═════════════════════════════════════════════════
phase('Decompose')
const [letter, spirit] = await parallel([
  () =>
    agent(
      `Decompose this goal into a LETTER-OF-SPEC invariant checklist: the stated requirements, read literally and completely — every "must", every named behavior, every constraint. ids L-01, L-02… kind=hard unless the text marks it optional. Each needs a concrete probe. ${REPO_RULES}\n${scopeNote}\n\nGOAL:\n${clip(A.goal, 8000)}\n\n${OUTPUT_RULES}`,
      { label: 'decompose:letter', phase: 'Decompose', model: 'opus', effort: 'high', schema: INVARIANTS_OUT }
    ),
  () =>
    agent(
      `Decompose this goal into a SPIRIT-OF-SPEC invariant checklist: what the goal's author would OBVIOUSLY expect but did not write — error paths, edge semantics, non-functional expectations, consistency with the surrounding system, "what would disappoint the author". ids S-01, S-02… kind=hard only when a violation would betray the goal's intent; else soft. Each needs a concrete probe. Read the actual repo to ground the implied expectations. ${REPO_RULES}\n${scopeNote}\n\nGOAL:\n${clip(A.goal, 8000)}\n\n${OUTPUT_RULES}`,
      { label: 'decompose:spirit', phase: 'Decompose', model: 'opus', effort: 'high', schema: INVARIANTS_OUT }
    ),
])
if (!letter && !spirit) throw new Error('both decomposers failed')
const merged = await agent(
  `Merge these two invariant lists: union, dedup (same requirement expressed twice → keep the sharper statement, prefer the LETTER id), keep ids stable, re-check hard/soft tags for consistency. Keep every genuinely distinct invariant — do not compress away nuance. ${OUTPUT_RULES}

LETTER:
${JSON.stringify(letter?.invariants || [], null, 1)}

SPIRIT:
${JSON.stringify(spirit?.invariants || [], null, 1)}`,
  { label: 'decompose:merge', phase: 'Decompose', model: 'sonnet', effort: 'high', schema: MERGE_OUT }
)
const invariants = (merged?.invariants?.length ? merged.invariants : [...(letter?.invariants || []), ...(spirit?.invariants || [])]).map((i) => ({ ...i }))
if (!invariants.length) throw new Error('decomposition produced no invariants')
log(`${invariants.length} invariants (${invariants.filter((i) => i.kind === 'hard').length} hard)`)

// ═══ P2: Audit fan-out (clustered by file locality) ═════════════════════════
phase('Audit')
const CLUSTERS = Math.min(4, Math.max(1, Math.ceil(invariants.length / 4)))
const byFile = new Map(); for (const inv of invariants) { const k = (inv.files && inv.files[0]) || inv.id; (byFile.get(k) || byFile.set(k, []).get(k)).push(inv) }
const clusters = Array.from({ length: CLUSTERS }, () => []); [...byFile.values()].forEach((grp, i) => clusters[i % CLUSTERS].push(...grp)) // file locality: each file's invariants stay in one cluster; whole file-groups round-robin across ≤4 auditors
const auditOuts = await parallel(
  clusters.map((cl, i) => () =>
    agent(
      `You are a conformance auditor. For EACH invariant below: find the code that satisfies it (cite file:line in evidence), judge status satisfied/violated/partial/unverified, and for violations/partials emit a FINDING (anchored file+line, concrete failure_scenario, suggested_probe). Also record NUANCES: observations the goal's author would want to know that are not violations (subtle semantics, quality gaps, surprising-but-correct behavior). Depth: ${A.depth === 'deep' ? 'DEEP — read every relevant file fully; trace call chains; check tests' : 'standard — read the implementing code and its direct callers'}. ${REPO_RULES}\n${baseNote}\n${scopeNote}

GOAL (context):
${clip(A.goal, 3000)}

INVARIANTS:
${cl.map((v) => `${v.id} [${v.kind}] ${v.statement} — probe: ${v.probe}`).join('\n')}

${OUTPUT_RULES}`,
      {
        label: `audit:c${i + 1}`,
        phase: 'Audit',
        model: A.depth === 'deep' && cl.some((v) => v.kind === 'hard') ? 'opus' : 'sonnet',
        effort: 'high',
        schema: AUDIT_OUT,
      }
    )
  )
)
const statuses = new Map()
const findings = []
const nuances = []
for (const out of auditOuts.filter(Boolean)) {
  for (const s of out.statuses) statuses.set(s.invariant_id, s)
  findings.push(...out.findings)
  nuances.push(...out.nuances)
}
const anon = shuffled(findings, mulberry32(hashString(A.seed + A.runId))).map((f, i) => {
  const { confidence, invariant_ids, ...pub } = f
  return { id: `F-${pad2(i + 1)}`, ...pub, _full: f }
})
log(`audit: ${findings.length} findings · ${nuances.length} nuances`)

// ═══ P3: Skeptic pass on violations ═════════════════════════════════════════
phase('Cross-exam')
let kept = []
let refuted = []
if (anon.length) {
  const batches = anon.map(({ _full, ...pub }) => pub)
  const panels = await parallel(
    ['prosecute', 'defend'].map((framing, i) => () =>
      agent(
        `You are a skeptical verifier cross-examining anonymized audit findings. ${framing === 'prosecute' ? 'For EACH claim, construct the strongest case that it is FALSE, verify against the code, then verdict.' : 'For EACH claim, argue the code is CORRECT despite it, verify against the code, then verdict.'} strongest_refutation is MANDATORY even for STANDS. ${REPO_RULES}

FINDINGS:
${JSON.stringify(shuffled(batches, mulberry32(hashString(A.seed + ':ga:' + i))), null, 1)}

${OUTPUT_RULES}`,
        { label: `skeptic:${framing}`, phase: 'Cross-exam', model: 'sonnet', effort: 'high', schema: VERDICTS_OUT }
      ).then((r) => (r ? { framing, verdicts: r.verdicts } : null))
    )
  )
  const live = panels.filter(Boolean)
  for (const a of anon) {
    const vs = live.flatMap((p) => p.verdicts.filter((v) => v.finding_id === a.id).map((v) => ({ ...v, framing: p.framing })))
    const entry = { anonId: a.id, finding: a._full, verdicts: vs }
    if (vs.length === 2 && vs.every((v) => v.verdict === 'REFUTED')) {
      refuted.push(entry)
      // a refuted violation resets its invariant status to satisfied-unless-other-evidence
      for (const invId of a._full.invariant_ids || []) {
        const s = statuses.get(invId)
        if (s && s.status !== 'satisfied') statuses.set(invId, { ...s, status: 'partial', evidence: s.evidence + ' [violation claim refuted on cross-exam]' })
      }
    } else {
      entry.contested = vs.length === 2 && vs.some((v) => v.verdict === 'REFUTED')
      kept.push(entry)
    }
  }
}
log(`cross-exam: ${kept.length} kept · ${refuted.length} refuted`)

// ═══ P4: Evidence probes for hard violations ════════════════════════════════
phase('Probes')
const hardKept = kept
  .filter((k) => (k.finding.invariant_ids || []).some((id) => invariants.find((v) => v.id === id)?.kind === 'hard')).toSorted((a, b) => ({ critical: 0, major: 1, minor: 2 }[a.finding.severity] - { critical: 0, major: 1, minor: 2 }[b.finding.severity]))
  .slice(0, 5) // severity-first (critical→minor) so the top-5 cap never drops a critical hard violation ahead of a minor one
for (const k of hardKept) {
  const ev = await agent(
    `You are an evidence prover for a goal-conformance audit. PROVE this violation by execution or honestly fail. New files ONLY under ${A.repo}/${SCRATCH}/repro/. Prefer a failing test demonstrating the violated requirement; else a runtime trace; else static-trace with reproduced=false. A test failing for an unrelated reason proves nothing. ${REPO_RULES}

FINDING: ${JSON.stringify({ id: k.anonId, ...k.finding }, null, 1)}
${k.contested ? 'THIS FINDING IS CONTESTED (skeptics split) — your execution evidence settles it.' : ''}
${OUTPUT_RULES}`,
    { label: `probe:${k.anonId}`, phase: 'Probes', model: k.contested ? 'opus' : 'sonnet', effort: 'high', schema: EVIDENCE_OUT }
  )
  k.evidence = ev || { finding_id: k.anonId, evidence_class: 'opinion', reproduced: false, notes: 'prover failed' }
  k.confirmed = !!ev && ev.reproduced && ['failing-test-repro', 'runtime-trace'].includes(ev.evidence_class)
  // Guard: evidence proves the finding's scenario, not every tagged invariant — an
  // invariant the auditor judged 'satisfied' softens to 'partial', never flips to violated.
  if (k.confirmed) for (const invId of k.finding.invariant_ids || []) {
    const s = statuses.get(invId) || { invariant_id: invId, status: 'unverified', evidence: '' }
    const next = s.status === 'satisfied' ? 'partial' : 'violated'
    statuses.set(invId, { ...s, status: next, evidence: (s.evidence || '') + ` [linked finding CONFIRMED by ${ev.evidence_class}]` })
  }
}
log(`probes: ${hardKept.filter((k) => k.confirmed).length}/${hardKept.length} confirmed`)

// ═══ Record ═════════════════════════════════════════════════════════════════
return {
  runId: A.runId,
  goal: clip(A.goal, 500),
  depth: A.depth,
  invariants: invariants.map((v) => ({ ...v, status: statuses.get(v.id)?.status || 'unverified', evidence: statuses.get(v.id)?.evidence || '' })),
  findings: kept.map((k) => ({
    id: k.anonId,
    finding: k.finding,
    verdicts: k.verdicts.map((v) => ({ verdict: v.verdict, framing: v.framing, strongest_refutation: clip(v.strongest_refutation, 600) })),
    evidence: k.evidence || null,
    state: k.confirmed ? 'CONFIRMED' : 'PLAUSIBLE',
  })),
  refuted: refuted.map((k) => ({ id: k.anonId, finding: k.finding, verdicts: k.verdicts })),
  nuances,
  status: 'REPORT_ONLY',
  budgetSpent: budget.spent(),
  scratchDir: SCRATCH,
}
