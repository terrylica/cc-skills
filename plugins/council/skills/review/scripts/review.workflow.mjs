export const meta = {
  name: 'council-review',
  description: 'LLM-council review gate: diverse finder lenses, blind cross-examination, evidence tribunal, fix loop until green',
  phases: [
    { title: 'Context' },
    { title: 'Invariants' },
    { title: 'Finders' },
    { title: 'Cross-exam' },
    { title: 'Tribunal' },
    { title: 'Fix loop' },
  ],
}

// ─── Args & defaults ────────────────────────────────────────────────────────
// Prose SSoT: plugins/council/references/schemas.md (keep inline copies in sync)
const A = {
  repo: args.repo, // REQUIRED absolute path to the repo under review
  goal: args.goal, // REQUIRED goal/spec text (skill preflight inlines file contents)
  base: args.base ?? null, // resolved in P0 if null
  head: args.head ?? 'HEAD',
  scope: args.scope ?? [],
  testCmd: args.testCmd ?? null,
  fleet: args.fleet ?? 'auto',
  dryRounds: args.dryRounds ?? 2,
  maxFinderRounds: args.maxFinderRounds ?? 4,
  skeptics: args.skeptics ?? null, // resolved after fleet sizing
  maxFixRounds: args.maxFixRounds ?? 3,
  // Surface-first is the DEFAULT: the council reports; the human decides what gets fixed.
  // Pass fix=true to opt into the autonomous fix loop. (Legacy noFix still honored.)
  fix: args.fix ?? (args.noFix !== undefined ? !args.noFix : false),
  isolation: args.isolation ?? 'scratch',
  seed: args.seed ?? 'council',
  runId: args.runId, // REQUIRED (no Date.now() in workflow scripts)
}
if (!A.repo || !A.goal || !A.runId) throw new Error('args.repo, args.goal, args.runId are required')
const SCRATCH = `tmp/council-${A.runId}`
// --isolation clone: read-only reviewers + provers operate inside a throwaway
// `git clone --local` under $TMPDIR (created in P0) so even a hostile probe can
// mutate freely without touching the real tree. Fixers still edit the real tree.
const TMPDIR = ((typeof process !== 'undefined' && process.env && process.env.TMPDIR) || '/tmp').replace(/\/+$/, '')
const CLONE_DIR = A.isolation === 'clone' ? `${TMPDIR}/council-clone-${A.runId}` : null
const WORKDIR = CLONE_DIR ?? A.repo

// ─── Seeded PRNG (Math.random unavailable) ──────────────────────────────────
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
const rng = mulberry32(hashString(A.seed + A.runId))
function shuffled(arr, r) {
  const a = arr.slice()
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(r() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}
const clip = (s, n) => (typeof s === 'string' && s.length > n ? s.slice(0, n) + '…[truncated]' : s)
const pad2 = (n) => String(n).padStart(2, '0')

// ─── Schemas (inline copies; SSoT = references/schemas.md) ──────────────────
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
const COVERAGE = {
  type: 'object',
  required: ['invariant_id', 'status'],
  properties: { invariant_id: { type: 'string' }, status: { enum: ['ok', 'violated', 'unclear', 'not-checked'] } },
  additionalProperties: false,
}
const FINDER_OUT = {
  type: 'object',
  required: ['findings', 'coverage'],
  properties: { findings: { type: 'array', items: FINDING }, coverage: { type: 'array', items: COVERAGE } },
  additionalProperties: false,
}
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
const PACK_OUT = {
  type: 'object',
  required: ['baseRef', 'changedFiles', 'diffSummary', 'testCmd', 'testInventory', 'historyNotes', 'blastRadius', 'gitStatusBaseline', 'snapshotRef'],
  properties: {
    baseRef: { type: 'string' },
    changedFiles: { type: 'array', items: { type: 'string' } },
    changedLines: { type: 'integer' },
    diffSummary: { type: 'string', maxLength: 12000 },
    testCmd: { type: ['string', 'null'] },
    testInventory: { type: 'string', maxLength: 3000 },
    historyNotes: { type: 'string', maxLength: 4000 },
    blastRadius: { type: 'string', maxLength: 4000 },
    conventions: { type: 'string', maxLength: 1500 },
    gitStatusBaseline: { type: 'string', maxLength: 3000 },
    snapshotRef: { type: 'string' },
  },
  additionalProperties: false,
}
const WARDEN_OUT = {
  type: 'object',
  required: ['porcelain'],
  properties: { porcelain: { type: 'string', maxLength: 3000 } },
  additionalProperties: false,
}
const MAPPER_OUT = {
  type: 'object',
  required: ['finding_id', 'disagreement_axis', 'analysis'],
  properties: {
    finding_id: { type: 'string' },
    disagreement_axis: { enum: ['assumption', 'mechanism', 'severity', 'scope'] },
    analysis: { type: 'string', maxLength: 2000 },
  },
  additionalProperties: false,
}
const FIX_OUT = {
  type: 'object',
  required: ['finding_ids', 'files_touched', 'description', 'repro_result'],
  properties: {
    finding_ids: { type: 'array', items: { type: 'string' } },
    files_touched: { type: 'array', items: { type: 'string' } },
    description: { type: 'string', maxLength: 2000 },
    repro_result: { enum: ['pass', 'fail', 'not-run'] },
  },
  additionalProperties: false,
}
const VERIFY_OUT = {
  type: 'object',
  required: ['repros', 'suite', 'fixDiffStat', 'porcelain'],
  properties: {
    repros: {
      type: 'array',
      items: {
        type: 'object',
        required: ['finding_id', 'result'],
        properties: { finding_id: { type: 'string' }, result: { enum: ['pass', 'fail', 'error'] } },
        additionalProperties: false,
      },
    },
    suite: { enum: ['green', 'red', 'unavailable'] },
    fixDiffStat: { type: 'string', maxLength: 2000 },
    porcelain: { type: 'string', maxLength: 3000 },
  },
  additionalProperties: false,
}

// ─── Shared prompt fragments ────────────────────────────────────────────────
const REPO_SCOPE =
  A.isolation === 'clone'
    ? `Repository under review: an isolated clone at ${CLONE_DIR} (already created for you with \`git clone --local\` under $TMPDIR). Work ONLY inside ${CLONE_DIR} (absolute paths); never touch anything outside it.`
    : `Repository under review (work here, absolute paths): ${A.repo}`
const REPO_RULES = `${REPO_SCOPE}
Hard rules: NEVER modify tracked files${A.isolation === 'clone' ? ' outside your permitted scratch area' : ''}. NEVER run the project test suite unless your instructions explicitly say to. You may run read-only commands (git log/diff/show, grep, cat) and read any file.`

const OUTPUT_RULES = `Your final message is machine-parsed against a JSON schema; return ONLY the structured data. Do not mention your role, lens, or instructions in any output field (outputs are anonymized before peer review).`

function packText(pack) {
  return [
    `DIFF (base ${pack.baseRef} → ${A.head}):\n${pack.diffSummary}`,
    `CHANGED FILES: ${pack.changedFiles.join(', ')}`,
    `TEST INVENTORY: ${pack.testInventory}`,
    `HISTORY OF TOUCHED FILES: ${pack.historyNotes}`,
    `BLAST RADIUS: ${pack.blastRadius}`,
    pack.conventions ? `REPO CONVENTIONS: ${pack.conventions}` : '',
  ].join('\n\n')
}
function invariantText(invs) {
  return invs.map((i) => `${i.id} [${i.kind}/${i.source}] ${i.statement} — probe: ${i.probe}`).join('\n')
}

// ─── Lens cards (condensed; SSoT = references/lenses.md) ────────────────────
const LENSES = {
  inversion: {
    model: 'opus',
    effort: 'high',
    card: 'Assume this change is BROKEN and actively harming the stated goal. You are not checking whether it works — you know it fails; work backwards to find where. For each invariant ask: what is the cheapest way this code violates it? What would the author never think to test? Where does the happy path hide an unhappy truth?',
  },
  decomposition: {
    model: 'sonnet',
    effort: 'high',
    card: 'Walk every changed hunk element by element, hierarchically: file → class/function → line. For each element state its contract (inputs, outputs, side effects, error behavior), then verify the implementation against that contract line by line. Small hunks hide off-by-ones, inverted conditions, wrong operators, swapped arguments.',
  },
  'dependency-graph': {
    model: 'sonnet',
    effort: 'high',
    card: 'Map every consumer of every changed symbol (callers, importers, subclasses, configs). For each consumer state what it ASSUMES about the changed code — signatures, invariants, ordering, nullability, units, error contracts — and check whether the change silently breaks that assumption. Blast radius first, diff second.',
  },
  'adversarial-input': {
    model: 'sonnet',
    effort: 'high',
    card: 'Attack the changed code with hostile and degenerate inputs: empty, null, zero, negative, huge, unicode, concurrent, duplicated, out-of-order, malformed. For every boundary in the diff construct the input that lands exactly ON the boundary. Consider resource exhaustion, partial failure mid-operation, re-entrancy.',
  },
  'spec-conformance': {
    model: 'sonnet',
    effort: 'high',
    card: 'Audit ONLY against the invariant checklist below. For each invariant: find the code that satisfies it, cite file:line, mark coverage ok/violated/unclear/not-checked. An invariant with no implementing code is a violation, not a gap.',
  },
  'static-arsenal': {
    model: 'haiku',
    effort: 'medium',
    card: 'Run whatever static analysis tools this repo supports (e.g. pyright, ruff, vulture, import-linter, deptry, semgrep, eslint, shellcheck — probe availability first, skip missing tools silently). Restrict attention to the changed files. Convert each genuine tool hit into a finding; drop style-only noise. Read-only execution of analysis tools is allowed.',
  },
}
const FLEETS = {
  small: [
    ['inversion', { model: 'sonnet', effort: 'high' }],
    ['spec-conformance', {}],
    ['static-arsenal', {}],
  ],
  standard: [
    ['inversion', {}],
    ['decomposition', {}],
    ['dependency-graph', {}],
    ['adversarial-input', {}],
    ['spec-conformance', {}],
    ['static-arsenal', {}],
  ],
  large: [
    ['inversion', {}],
    ['decomposition', {}],
    ['dependency-graph', {}],
    ['adversarial-input', {}],
    ['spec-conformance', {}],
    ['static-arsenal', {}],
    ['inversion', { model: 'sonnet', effort: 'high', tag: 'b' }],
    ['decomposition', { model: 'opus', effort: 'high', tag: 'b' }],
    ['adversarial-input', { model: 'opus', effort: 'high', tag: 'b' }],
  ],
}

// ─── Dedup / anonymization helpers ──────────────────────────────────────────
function fingerprint(f) {
  const stem = (f.summary || '').toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).slice(0, 8).join(' ')
  return `${(f.file || '').replace(/\\/g, '/')}|${f.symbol || ''}|${f.category}|${stem}`
}
const PUBLIC_KEYS = ['file', 'line', 'symbol', 'category', 'severity', 'summary', 'failure_scenario', 'evidence_pointers', 'suggested_probe']
function publicFields(f) {
  const out = {}
  for (const k of PUBLIC_KEYS) if (f[k] !== undefined) out[k] = f[k]
  return out
}

// ═══ P0: Context pack ═══════════════════════════════════════════════════════
phase('Context')
log(`run ${A.runId} · repo ${A.repo}`)
const pack = await agent(
  `You are building a review context pack. ${REPO_RULES}

Steps (run these in the repo):
1. Resolve the diff base: ${A.base ? `use "${A.base}".` : 'compute the merge-base of HEAD and the default origin branch (origin/main or origin/master); if none, use the first commit.'} Report it as baseRef.
2. changedFiles + changedLines: from \`git diff --stat <base>...${A.head}\`${A.scope.length ? ` limited to paths: ${A.scope.join(' ')}` : ''}.
3. diffSummary: the unified diff, clipped intelligently to ≤12000 chars (keep whole hunks for the most substantive files; summarize the rest as "file: +a/-b lines, <one-line gist>").
4. testCmd: ${A.testCmd ? `verify that "${A.testCmd}" is runnable (do NOT run the full suite; --help or --collect-only style checks are fine); report it.` : 'detect the test command (mise task > package.json script > pytest/cargo test/go test/bun test heuristics based on repo files). Verify runnability cheaply (--collect-only / --help), do NOT run the suite. null if none found.'}
5. testInventory: which test files cover the changed files (by naming convention + grep of imports), ≤3000 chars.
6. historyNotes: for each changed file, \`git log --follow --oneline -5\` + any commit messages that state intent, ≤4000 chars.
7. blastRadius: for each changed exported/public symbol, grep the repo for its consumers; list consumer file:line, ≤4000 chars.
8. conventions: 1-2 lines on error-handling/style conventions you can infer (or empty).
9. gitStatusBaseline: exact output of \`git status --porcelain\`.
10. snapshotRef: output of \`git stash create\` (empty string if clean tree — that is fine).

${OUTPUT_RULES}`,
  { label: 'pack', phase: 'Context', model: 'haiku', effort: 'medium', schema: PACK_OUT }
)
if (!pack) throw new Error('context pack agent failed')
if (A.isolation === 'clone') {
  // Create the isolated clone once so every downstream reviewer/prover works in it.
  await agent(
    `Set up an isolated review clone. Run exactly: \`rm -rf ${CLONE_DIR} && git clone --local ${A.repo} ${CLONE_DIR}\` (a local clone shares object storage, is fast, and carries only committed state). Then return \`git -C ${CLONE_DIR} status --porcelain\` verbatim as porcelain. ${OUTPUT_RULES}`,
    { label: 'clone-setup', phase: 'Context', model: 'haiku', effort: 'low', schema: WARDEN_OUT }
  )
  log(`isolation=clone — reviewers/provers operate in ${CLONE_DIR}; fixers still edit ${A.repo}`)
}
const changedLines = pack.changedLines ?? 0
const fleetName = A.fleet !== 'auto' ? A.fleet : changedLines < 200 ? 'small' : changedLines < 1500 ? 'standard' : 'large'
// Clamp to a floor of 2 so both framings are always present and KILL≥2 — a
// panel of 0/1 would make `ref.length >= KILL` vacuously satisfiable (F-12).
const S = Math.max(A.skeptics ?? (fleetName === 'large' ? 5 : 3), 2)
const KILL = Math.ceil((2 * S) / 3)
log(`fleet=${fleetName} (${changedLines} changed lines) · skeptics=${S} · kill-quorum=${KILL}`)

// ═══ P1: Invariant decomposition ════════════════════════════════════════════
phase('Invariants')
const invRes = await agent(
  `You are decomposing a goal into a testable invariant checklist for a code review. ${REPO_RULES}

GOAL / SPEC:
${clip(A.goal, 8000)}

CONTEXT:
${packText(pack)}

Produce invariants (ids INV-01, INV-02, …) of three kinds:
- explicit-goal: stated requirements, verbatim intent.
- implied: what the goal's author would obviously expect — error paths, edge semantics, non-functional expectations.
- regression-guard: behavior of the touched code that existed before this change and must survive it (use the history notes).
Mark kind=hard when a violation is a defect; kind=soft for quality preferences. Every invariant needs a concrete probe (how to check it). 5–15 invariants; fewer, sharper ones beat a laundry list.

${OUTPUT_RULES}`,
  { label: 'invariants', phase: 'Invariants', model: 'opus', effort: 'high', schema: INVARIANTS_OUT }
)
if (!invRes || !invRes.invariants.length) throw new Error('invariant decomposition failed')
const invariants = invRes.invariants.map((i) => ({ ...i, status: 'unverified' }))
log(`${invariants.length} invariants (${invariants.filter((i) => i.kind === 'hard').length} hard)`)

// ═══ P2: Finder fleet, loop until dry ═══════════════════════════════════════
phase('Finders')
const known = new Map() // fingerprint -> {finding, provenance}
const coverageAgg = new Map() // invariant_id -> best status seen
function mergeCoverage(cov) {
  const rank = { 'not-checked': 0, unclear: 1, ok: 2, violated: 3 }
  for (const c of cov || []) {
    const prev = coverageAgg.get(c.invariant_id)
    if (!prev || rank[c.status] > rank[prev]) coverageAgg.set(c.invariant_id, c.status)
  }
}
function hardUnverified() {
  return invariants.filter((i) => i.kind === 'hard' && !['ok', 'violated'].includes(coverageAgg.get(i.id) || ''))
}
function finderPrompt(lensName, card, round) {
  const knownList = [...known.values()].map((k) => `- ${k.finding.file}:${k.finding.line} [${k.finding.category}] ${k.finding.summary}`).join('\n')
  return `You are one reviewer in a panel reviewing a code change. Reasoning stance:
${card}

${REPO_RULES}

GOAL:
${clip(A.goal, 4000)}

INVARIANTS:
${invariantText(invariants)}

CONTEXT PACK:
${packText(pack)}
${round > 1 ? `\nKNOWN FINDINGS (already reported — return ONLY genuinely novel ones):\n${clip(knownList, 4000)}\n\nUnverified hard invariants needing attention: ${hardUnverified().map((i) => i.id).join(', ') || 'none'}` : ''}

Report findings per the schema. Every finding needs a CONCRETE failure_scenario (inputs/state → wrong result) and a suggested_probe a later stage can execute to prove it. Also report coverage for every invariant you actually checked. Quality bar: report what you would stake your reputation on; noise is worse than silence. ${OUTPUT_RULES}`
}
let round = 0
let dry = 0
while (dry < A.dryRounds && round < A.maxFinderRounds) {
  round++
  let lensSet
  if (round === 1) {
    lensSet = FLEETS[fleetName]
  } else {
    // Rotation: re-brief inversion on the survivors map + one spec finder per unverified hard invariant (cap 3)
    lensSet = [['inversion', { tag: `r${round}` }]]
    for (const inv of hardUnverified().slice(0, 3)) lensSet.push(['spec-conformance', { tag: inv.id, focus: inv.id }])
    if (!lensSet.length) break
  }
  if (budget.total && budget.total - budget.spent() < 30000) {
    log(`budget low (${Math.round((budget.total - budget.spent()) / 1000)}k) — ending finder loop at round ${round}`)
    break
  }
  const results = await parallel(
    lensSet.map(([name, ovr]) => () =>
      agent(finderPrompt(name, LENSES[name].card + (ovr.focus ? `\nFOCUS EXCLUSIVELY on invariant ${ovr.focus}.` : ''), round), {
        label: `finder:${name}${ovr.tag ? ':' + ovr.tag : ''}:r${round}`,
        phase: 'Finders',
        model: ovr.model ?? LENSES[name].model,
        effort: ovr.effort ?? LENSES[name].effort,
        schema: FINDER_OUT,
      })
    )
  )
  let novel = 0
  for (let i = 0; i < results.length; i++) {
    const res = results[i]
    if (!res) continue
    mergeCoverage(res.coverage)
    for (const f of res.findings || []) {
      const fp = fingerprint(f)
      if (known.has(fp)) continue
      known.set(fp, { finding: f, provenance: { lens: lensSet[i][0], round, model: lensSet[i][1].model ?? LENSES[lensSet[i][0]].model } })
      novel++
    }
  }
  dry = novel === 0 && hardUnverified().length === 0 ? dry + 1 : 0
  log(`round ${round}: +${novel} novel findings (total ${known.size}) · unverified hard invariants: ${hardUnverified().length} · dry=${dry}`)
}

// ═══ P3: Blind cross-examination ════════════════════════════════════════════
phase('Cross-exam')
const proposed = [...known.entries()].map(([fp, v], i) => ({ anonId: `F-${pad2(i + 1)}`, fp, ...v }))
const anonBatch = shuffled(proposed, rng).map((p) => ({ id: p.anonId, ...publicFields(p.finding) }))
function skepticPrompt(batch, framing) {
  const frame =
    framing === 'prosecute'
      ? 'For EACH claim below, construct the strongest case that the claim is FALSE, verify your case against the actual code, then give your verdict.'
      : 'For EACH claim below, argue that the code is CORRECT despite the claim, verify your argument against the actual code, then give your verdict.'
  return `You are a skeptical verifier cross-examining anonymized review findings. You do not know who produced them or how. ${REPO_RULES}

${frame}

Verdicts: REFUTED (the claim is wrong — your refutation holds against the code), STANDS (you tried to refute it and failed — the defect is real), UNCERTAIN (cannot be settled by reading; needs execution). strongest_refutation is MANDATORY for every finding, including STANDS. Judge the claim, not its style; length and polish are not evidence.

CONTEXT PACK:
${packText(pack)}

FINDINGS (id + claim):
${JSON.stringify(batch, null, 1)}

Return one verdict per finding id. ${OUTPUT_RULES}`
}
let survivors = []
let refuted = []
let disagreementMaps = []
if (proposed.length === 0) {
  log('no findings proposed — skipping cross-exam')
} else {
  const framings = Array.from({ length: S }, (_, i) => (i % 2 === 0 ? 'prosecute' : 'defend'))
  const models = Array.from({ length: S }, (_, i) => (i === (S % 2 === 0 ? S - 1 : S - 2) ? { model: 'opus', effort: 'medium' } : { model: 'sonnet', effort: 'high' }))
  const panels = await parallel(
    framings.map((framing, i) => () =>
      agent(skepticPrompt(shuffled(anonBatch, mulberry32(hashString(A.seed + ':skeptic:' + i))), framing), {
        label: `skeptic:${i}:${framing}`,
        phase: 'Cross-exam',
        model: models[i].model,
        effort: models[i].effort,
        schema: VERDICTS_OUT,
      }).then((r) => (r ? { framing, verdicts: r.verdicts } : null))
    )
  )
  const live = panels.filter(Boolean)
  const byFinding = new Map(proposed.map((p) => [p.anonId, []]))
  for (const p of live) for (const v of p.verdicts) if (byFinding.has(v.finding_id)) byFinding.get(v.finding_id).push({ ...v, framing: p.framing })
  const tiebreakQueue = []
  for (const p of proposed) {
    const vs = byFinding.get(p.anonId) || []
    const ref = vs.filter((v) => v.verdict === 'REFUTED')
    const stands = vs.filter((v) => v.verdict === 'STANDS')
    const crossFraming = new Set(ref.map((v) => v.framing)).size > 1
    p.verdicts = vs
    if (ref.length >= KILL && crossFraming) {
      p.state = 'refuted'
      refuted.push(p)
    } else if (ref.length >= KILL && !crossFraming) {
      tiebreakQueue.push(p)
    } else if (stands.length >= KILL) {
      p.state = 'stands'
      survivors.push(p)
    } else {
      p.state = 'contested'
      survivors.push(p)
    }
  }
  if (tiebreakQueue.length) {
    log(`${tiebreakQueue.length} single-framing kills — tie-break skeptic engaged`)
    const majorityFraming = tiebreakQueue[0].verdicts.find((v) => v.verdict === 'REFUTED')?.framing ?? 'prosecute'
    const otherFraming = majorityFraming === 'prosecute' ? 'defend' : 'prosecute'
    const tb = await agent(skepticPrompt(tiebreakQueue.map((p) => ({ id: p.anonId, ...publicFields(p.finding) })), otherFraming), {
      label: 'skeptic:tiebreak',
      phase: 'Cross-exam',
      model: 'opus',
      effort: 'high',
      schema: VERDICTS_OUT,
    })
    const tbMap = new Map((tb?.verdicts || []).map((v) => [v.finding_id, v]))
    for (const p of tiebreakQueue) {
      const v = tbMap.get(p.anonId)
      if (v) p.verdicts.push({ ...v, framing: otherFraming })
      if (v && v.verdict === 'REFUTED') {
        p.state = 'refuted'
        refuted.push(p)
      } else {
        p.state = 'contested'
        survivors.push(p)
      }
    }
  }
  const contested = survivors.filter((p) => p.state === 'contested')
  if (contested.length) {
    const maps = await parallel(
      contested.slice(0, 8).map((p) => () =>
        agent(
          `Skeptics disagreed about this anonymized code-review finding. Do NOT decide who wins. Map WHAT they disagree about (the axis: assumption, mechanism, severity, or scope) and state precisely what execution evidence would settle it. ${REPO_RULES}

FINDING: ${JSON.stringify({ id: p.anonId, ...publicFields(p.finding) }, null, 1)}
VERDICTS: ${JSON.stringify(p.verdicts.map((v) => ({ verdict: v.verdict, framing: v.framing, refutation: clip(v.strongest_refutation, 500) })), null, 1)}

${OUTPUT_RULES}`,
          { label: `map:${p.anonId}`, phase: 'Cross-exam', model: 'opus', effort: 'high', schema: MAPPER_OUT }
        )
      )
    )
    disagreementMaps = maps.filter(Boolean)
  }
  log(`cross-exam: ${survivors.length} survive (${contested.length} contested) · ${refuted.length} refuted`)
}

// ═══ P4: Evidence tribunal ══════════════════════════════════════════════════
phase('Tribunal')
const sevRank = { critical: 0, major: 1, minor: 2 }
survivors.sort((a, b) => sevRank[a.finding.severity] - sevRank[b.finding.severity])
let tribunalCap = survivors.length
if (budget.total && budget.total - budget.spent() < 60000) {
  tribunalCap = Math.min(survivors.length, 5)
  log(`budget pressure — tribunal capped at top ${tribunalCap} by severity`)
}
async function warden(label) {
  const w = await agent(
    `Run exactly one command in ${WORKDIR}: \`git status --porcelain\` and return its output verbatim (empty string if clean). ${OUTPUT_RULES}`,
    { label, phase: 'Tribunal', model: 'haiku', effort: 'low', schema: WARDEN_OUT }
  )
  return w ? w.porcelain.trim() : null
}
function proverPrompt(p, extra) {
  return `You are an evidence prover. A cross-examined review finding survived; your job is to PROVE it by execution — or honestly fail to. ${REPO_RULES}
Additional permission: you MAY create new files, but ONLY under ${WORKDIR}/${SCRATCH}/ (create directories as needed) — never anywhere else. You MAY execute code, the repro test you write, and narrow test selections. Do not run the full suite.

FINDING: ${JSON.stringify({ id: p.anonId, ...publicFields(p.finding) }, null, 1)}
${p.state === 'contested' ? `THIS FINDING IS CONTESTED. Disagreement map: ${clip(JSON.stringify(disagreementMaps.find((m) => m.finding_id === p.anonId) || {}), 1200)}` : ''}
${extra || ''}
Evidence ladder (prefer the highest rung you can reach):
1. failing-test-repro: write a test under ${SCRATCH}/repro/${p.anonId}/ (per-finding subdir — never share a filename with another prover) that FAILS on the current code FOR THE STATED REASON; run it; capture output.
2. runtime-trace: a script/command whose captured output demonstrates the wrong value/state at runtime.
3. static-trace: cited file:line chain only — use when execution is impractical, set reproduced=false.
A test that fails for an unrelated reason proves nothing — classify honestly. If you refute the finding while trying to prove it, say so in notes and set evidence_class=opinion, reproduced=false.
FLIPPABILITY CONTRACT: construct the repro so it fails NOW and will PASS once the defect is fixed — it becomes the fix's acceptance test. If the finding is inherently non-flippable (e.g. a test-gap you demonstrate by showing a hypothetical regression slips through), include the exact token NON-FLIPPABLE in notes; fix acceptance then falls to re-review instead of artifact flip.

TEST COMMAND (context, do not run fully): ${pack.testCmd || 'none detected'}
${OUTPUT_RULES}`
}
let baselinePorcelain = A.isolation === 'clone' ? '' : pack.gitStatusBaseline.trim()
const tribunal = survivors.slice(0, tribunalCap)
for (const p of survivors.slice(tribunalCap)) {
  p.evidence = { finding_id: p.anonId, evidence_class: 'opinion', reproduced: false, notes: 'not probed: tribunal budget cap' }
}
const WAVE = 4
for (let w = 0; w < tribunal.length; w += WAVE) {
  const wave = tribunal.slice(w, w + WAVE)
  const evs = await parallel(
    wave.map((p) => () =>
      agent(proverPrompt(p), { label: `prove:${p.anonId}`, phase: 'Tribunal', model: p.state === 'contested' ? 'opus' : 'sonnet', effort: 'high', schema: EVIDENCE_OUT })
    )
  )
  const after = await warden(`warden:w${w / WAVE + 1}`)
  // Taint = drift in TRACKED files only (lines not starting with '??'). Untracked additions
  // outside the scratch dir (e.g. __pycache__/) are logged but do not taint.
  const trackedLines = (s) => (s || '').split('\n').filter((l) => l.trim() && !l.startsWith('??')).sort().join('\n')
  const tainted = after !== null && trackedLines(after) !== trackedLines(baselinePorcelain)
  if (after !== null && !tainted && after !== baselinePorcelain) {
    const newUntracked = after.split('\n').filter((l) => l.startsWith('??') && !l.includes(SCRATCH) && !baselinePorcelain.includes(l.trim()))
    if (newUntracked.length) log(`note: untracked artifacts appeared outside scratch (not tainting): ${newUntracked.join(' ')}`)
  }
  for (let i = 0; i < wave.length; i++) {
    const ev = evs[i]
    if (!ev) {
      wave[i].evidence = { finding_id: wave[i].anonId, evidence_class: 'opinion', reproduced: false, notes: 'prover failed' }
    } else if (tainted || after === null) {
      wave[i].evidence = { ...ev, evidence_class: 'opinion', reproduced: false, notes: `${after === null ? 'TAINT CHECK INCONCLUSIVE: warden git-status unavailable, cannot confirm the tree stayed clean' : 'TAINTED: tracked files drifted during this wave'}. Original class: ${ev.evidence_class}. ${ev.notes || ''}` }
    } else {
      wave[i].evidence = ev
    }
  }
  if (tainted) log(`⚠ wave ${w / WAVE + 1} tainted — tracked-file drift detected; evidence downgraded. Manual inspection advised.`)
  else if (after === null) log(`⚠ wave ${w / WAVE + 1} taint check inconclusive — warden failed; evidence downgraded conservatively.`)
}
const isConfirmed = (p) => p.evidence && p.evidence.reproduced && ['failing-test-repro', 'runtime-trace'].includes(p.evidence.evidence_class)
for (const p of survivors) {
  p.confirmed = isConfirmed(p)
  // Settle invariant statuses from confirmed violations. Guard: evidence proves the
  // finding's failure_scenario, not every agent-supplied invariant tag — an invariant
  // finders judged 'ok' softens to 'unclear' (→ partial), it does not flip to violated.
  if (p.confirmed)
    for (const id of p.finding.invariant_ids || []) {
      coverageAgg.set(id, coverageAgg.get(id) === 'ok' ? 'unclear' : 'violated')
    }
}
log(`tribunal: ${survivors.filter((p) => p.confirmed).length} CONFIRMED · ${survivors.filter((p) => !p.confirmed).length} PLAUSIBLE`)

// ═══ P6: Fix loop until green ═══════════════════════════════════════════════
phase('Fix loop')
const fixLog = []
let status = 'REPORT_ONLY'
let finalTestResult = 'not-run'
if (A.fix) {
  status = 'GREEN'
  let confirmedQueue = survivors.filter((p) => p.confirmed && p.state !== 'fixed')
  let prevConfirmedKey = ''
  let fixRound = 0
  while (confirmedQueue.length > 0) {
    if (fixRound >= A.maxFixRounds) {
      status = 'BLOCKED'
      break
    }
    if (budget.total && budget.total - budget.spent() < 40000) {
      status = 'BLOCKED'
      log('budget floor reached mid fix-loop')
      break
    }
    const key = confirmedQueue.map((p) => p.fp).sort().join('|')
    if (key === prevConfirmedKey) {
      status = 'STALLED'
      log('no-progress guard: identical confirmed set two rounds')
      break
    }
    prevConfirmedKey = key
    fixRound++
    log(`fix round ${fixRound}: ${confirmedQueue.length} confirmed findings`)
    // group by primary file so no two fixers touch one file
    const groups = new Map()
    for (const p of confirmedQueue) {
      const g = p.finding.file
      if (!groups.has(g)) groups.set(g, [])
      groups.get(g).push(p)
    }
    // Fixers run SERIALLY: fixes for findings anchored in one file often land in another
    // (e.g. a test-gap anchored in tests/ fixed in src/), so file-keyed groups do not
    // guarantee disjoint edit sets. Serial execution makes collisions impossible.
    const fixes = []
    for (const [file, ps] of groups.entries()) {
      fixes.push(
        await agent(
          `You are a fixer on a review council. Fix the CONFIRMED defects below at their root cause — do not mask symptoms, do not fix the repro test instead of the code, keep the change minimal and in-convention. You may edit tracked files in ${A.repo} (this is the one stage allowed to). You may add or update tests. After fixing, run each repro artifact listed below and report the result.

REPO: ${A.repo}
GOAL (do not regress it): ${clip(A.goal, 2000)}
DEFECTS (all anchored in ${file}):
${ps.map((p) => JSON.stringify({ id: p.anonId, ...publicFields(p.finding), evidence: p.evidence }, null, 1)).join('\n')}

Repro artifacts (fix acceptance tests — these MUST pass after your fix):
${ps.map((p) => `- ${p.anonId}: ${p.evidence.artifact_path || '(runtime-trace)'} — run: ${p.evidence.command || 'see artifact'}`).join('\n')}

${OUTPUT_RULES}`,
          {
            label: `fix:${file.split('/').pop()}:r${fixRound}`,
            phase: 'Fix loop',
            model: ps.length > 1 || ps.some((p) => (p.finding.evidence_pointers || []).length > 3) ? 'opus' : 'sonnet',
            effort: 'high',
            schema: FIX_OUT,
          }
        )
      )
    }
    // verify: re-run all repros + suite
    const verify = await agent(
      `You are the verification agent for a fix round. In ${A.repo}:
1. Run EVERY repro artifact below; report pass/fail/error per finding id. A repro that now PASSES means its defect is fixed.
${survivors.filter((p) => p.confirmed).map((p) => `- ${p.anonId}: ${p.evidence.command || p.evidence.artifact_path || 'n/a'}`).join('\n')}
2. Run the project test suite: ${pack.testCmd || 'none detected — report suite="unavailable"'} — report green/red. IMPORTANT: council scratch artifacts under ${SCRATCH}/ are NOT part of the suite — exclude them if the runner supports it (e.g. pytest --ignore=${SCRATCH}); failures located inside ${SCRATCH}/ never count toward red.
3. Report \`git diff --stat ${pack.snapshotRef || 'HEAD'}\` output as fixDiffStat (≤2000 chars).
4. Report \`git status --porcelain\` verbatim.
${OUTPUT_RULES}`,
      { label: `verify:r${fixRound}`, phase: 'Fix loop', model: 'haiku', effort: 'medium', schema: VERIFY_OUT }
    )
    const reproResult = new Map((verify?.repros || []).map((r) => [r.finding_id, r.result]))
    const fixedByIds = new Set(fixes.filter(Boolean).flatMap((f) => f.finding_ids))
    for (const p of confirmedQueue) {
      const r = reproResult.get(p.anonId)
      const flippable = !(p.evidence.notes || '').includes('NON-FLIPPABLE')
      fixLog.push({
        round: fixRound,
        findingId: p.anonId,
        files_touched: (fixes.filter(Boolean).find((f) => f.finding_ids.includes(p.anonId)) || {}).files_touched || [],
        repro_before: 'fail',
        repro_after: r || 'unknown',
        suite_result: verify?.suite || 'unavailable',
        fixDiffStat: clip(verify?.fixDiffStat || '', 500),
      })
      if (r === 'pass') p.state = 'fixed'
      else if (!flippable && fixedByIds.has(p.anonId)) {
        p.state = 'fixed-pending-rereview'
        p.touchedFiles = (fixes.filter(Boolean).find((f) => f.finding_ids.includes(p.anonId)) || {}).files_touched || [p.finding.file]
      }
    }
    finalTestResult = verify?.suite || 'unavailable'
    baselinePorcelain = (verify?.porcelain || baselinePorcelain).trim()
    // scoped re-review of the fix diff
    const miniPack = `FIX DIFF THIS ROUND (stat): ${clip(verify?.fixDiffStat || 'unknown', 1500)}\nFixed findings: ${confirmedQueue.map((p) => p.anonId).join(', ')}`
    const mini = await parallel(
      ['adversarial-input', 'spec-conformance'].map((name) => () =>
        agent(
          finderPrompt(name, LENSES[name].card, 99) +
            `\n\nSCOPE OVERRIDE: fixes were just applied for confirmed findings. Review ONLY the fix diff (\`git diff ${pack.snapshotRef || 'HEAD'}\` in the repo) for regressions or incomplete fixes. Ignore files under ${SCRATCH}/ — they are council scratch artifacts, not the implementation.\n${miniPack}`,
          { label: `refind:${name}:r${fixRound}`, phase: 'Fix loop', model: 'sonnet', effort: 'high', schema: FINDER_OUT }
        )
      )
    )
    const fresh = []
    for (const res of mini.filter(Boolean)) {
      mergeCoverage(res.coverage)
      for (const f of res.findings || []) {
        const fp = fingerprint(f)
        if (known.has(fp)) continue
        known.set(fp, { finding: f, provenance: { lens: 'fix-re-review', round: `fix-${fixRound}` } })
        fresh.push({ anonId: `F-${pad2(known.size)}`, fp, finding: f, provenance: { lens: 'fix-re-review' }, verdicts: [], state: 'stands' })
      }
    }
    if (fresh.length) {
      log(`re-review found ${fresh.length} new findings — quorum + tribunal on them`)
      const anonFresh = fresh.map((p) => ({ id: p.anonId, ...publicFields(p.finding) }))
      const panels2 = await parallel(
        ['prosecute', 'defend'].map((framing, i) => () =>
          agent(skepticPrompt(shuffled(anonFresh, mulberry32(hashString(A.seed + ':refresh:' + fixRound + i))), framing), {
            label: `reskeptic:${framing}:r${fixRound}`,
            phase: 'Fix loop',
            model: 'sonnet',
            effort: 'high',
            schema: VERDICTS_OUT,
          }).then((r) => (r ? { framing, verdicts: r.verdicts } : null))
        )
      )
      for (const p of fresh) {
        const vs = panels2.filter(Boolean).flatMap((pa) => pa.verdicts.filter((v) => v.finding_id === p.anonId).map((v) => ({ ...v, framing: pa.framing })))
        p.verdicts = vs
        if (vs.length === 2 && vs.every((v) => v.verdict === 'REFUTED')) {
          p.state = 'refuted'
          refuted.push(p)
          continue
        }
        const preReprove = baselinePorcelain
        const ev = await agent(proverPrompt(p), { label: `reprove:${p.anonId}`, phase: 'Fix loop', model: 'sonnet', effort: 'high', schema: EVIDENCE_OUT })
        // Same taint guard as the P4 tribunal waves: a reprove that drifts tracked
        // files (or whose git-status check fails) must not launder into CONFIRMED.
        const postReprove = await warden(`warden:reprove:${p.anonId}`)
        const reproveTracked = (s) => (s || '').split('\n').filter((l) => l.trim() && !l.startsWith('??')).sort().join('\n')
        const reproveTainted = postReprove === null || reproveTracked(postReprove) !== reproveTracked(preReprove)
        p.evidence = !ev
          ? { finding_id: p.anonId, evidence_class: 'opinion', reproduced: false, notes: 'prover failed' }
          : reproveTainted
            ? { ...ev, evidence_class: 'opinion', reproduced: false, notes: `${postReprove === null ? 'TAINT CHECK INCONCLUSIVE: warden git-status unavailable' : 'TAINTED: tracked files drifted during reprove'}. Original class: ${ev.evidence_class}. ${ev.notes || ''}` }
            : ev
        if (ev && reproveTainted) log(`⚠ reprove ${p.anonId} — tracked-file drift/inconclusive; evidence downgraded`)
        p.confirmed = isConfirmed(p)
        survivors.push(p)
      }
    }
    // NON-FLIPPABLE findings: fix acceptance = fixer claimed the fix + re-review found nothing new confirmed
    const freshConfirmed = fresh.some((x) => x.confirmed)
    for (const p of confirmedQueue) {
      if (p.state === 'fixed-pending-rereview') p.state = freshConfirmed && fresh.some((x) => x.confirmed && (x.scopeFiles || [x.finding && x.finding.file]).some((f) => (p.touchedFiles || [p.finding && p.finding.file]).includes(f))) ? 'stands' : 'fixed'
    }
    confirmedQueue = survivors.filter((p) => p.confirmed && p.state !== 'fixed' && p.state !== 'refuted')
  }
  // 'loop until green' contract: a fix round that leaves the suite red is never shippable,
  // even if every finding's own repro flipped to pass (F-15).
  if (finalTestResult === 'red' || (status === 'GREEN' && survivors.some((p) => p.confirmed && p.state !== 'fixed'))) status = 'BLOCKED'
}

// ═══ Council record ═════════════════════════════════════════════════════════
// A 'violated' coverage vote is only trustworthy while a surviving finding still
// implicates that invariant. If every supporting finding was refuted (or a finder
// voted 'violated' with no finding at all), the vote is an unexamined opinion —
// downgrade it to 'unclear' so the coverage table never reports VIOLATED without a
// surviving/confirmed finding behind it (F-17).
const supportedInvariants = new Set()
for (const p of survivors) for (const id of p.finding.invariant_ids || []) supportedInvariants.add(id)
for (const [id, st] of coverageAgg) if (st === 'violated' && !supportedInvariants.has(id)) coverageAgg.set(id, 'unclear')
for (const inv of invariants) inv.status = coverageAgg.get(inv.id) === 'violated' ? 'violated' : coverageAgg.get(inv.id) === 'ok' ? 'satisfied' : coverageAgg.get(inv.id) === 'unclear' ? 'partial' : 'unverified'
const lifecycle = (p) => ({
  id: p.anonId,
  finding: p.finding,
  provenance: p.provenance,
  verdicts: (p.verdicts || []).map((v) => ({ verdict: v.verdict, framing: v.framing, strongest_refutation: clip(v.strongest_refutation, 600), confidence: v.confidence })),
  evidence: p.evidence || null,
  state: p.state === 'fixed' ? 'FIXED-VERIFIED' : p.confirmed ? 'CONFIRMED-UNFIXED' : 'PLAUSIBLE',
})
log(`done: status=${status} · ${survivors.filter((p) => p.state === 'fixed').length} fixed · ${survivors.filter((p) => p.confirmed && p.state !== 'fixed').length} confirmed-unfixed · ${refuted.length} refuted`)
return {
  runId: A.runId,
  goal: clip(A.goal, 500),
  refs: { base: pack.baseRef, head: A.head, snapshot: pack.snapshotRef || null },
  fleet: fleetName,
  invariants,
  coverageMap: [...coverageAgg.entries()].map(([invariant_id, st]) => ({ invariant_id, status: st })),
  finderRounds: round,
  findings: survivors.map(lifecycle),
  refuted: refuted.map(lifecycle),
  disagreementMaps,
  fixLog,
  finalTestResult,
  status,
  budgetSpent: budget.spent(),
  scratchDir: SCRATCH,
}
