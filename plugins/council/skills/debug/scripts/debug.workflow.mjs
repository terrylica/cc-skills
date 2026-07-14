export const meta = {
  name: 'council-debug',
  description: 'Hypothesis-elimination debugging: parallel falsifiable hypotheses, discriminating experiments, root cause proven by repro-then-fix-then-pass',
  phases: [{ title: 'Evidence' }, { title: 'Hypotheses' }, { title: 'Experiments' }, { title: 'Confirmation' }],
}

// ─── Args (SSoT: plugins/council/references/schemas.md) ─────────────────────
const A = {
  repo: args.repo,
  symptom: args.symptom,
  repro: args.repro ?? null,
  suspects: args.suspects ?? [],
  maxHypotheses: args.maxHypotheses ?? 6,
  maxRounds: args.maxRounds ?? 3,
  testCmd: args.testCmd ?? null,
  // Surface-first default: propose the fix but do NOT apply it. Pass fix=true to apply the
  // minimal confirming fix and independently verify (repro-then-fix-then-pass). Legacy noFix honored.
  fix: args.fix ?? (args.noFix !== undefined ? !args.noFix : false),
  seed: args.seed ?? 'council',
  runId: args.runId,
}
if (!A.repo || !A.symptom || !A.runId) throw new Error('args.repo, args.symptom, args.runId are required')
const SCRATCH = `tmp/council-${A.runId}`
const clip = (s, n) => (typeof s === 'string' && s.length > n ? s.slice(0, n) + '…[truncated]' : s)

// ─── Schemas (inline copies; SSoT = references/schemas.md) ──────────────────
const HYPOTHESIS = {
  type: 'object',
  required: ['id', 'statement', 'mechanism', 'falsifiable_prediction', 'discriminating_experiment', 'prior'],
  properties: {
    id: { type: 'string' },
    statement: { type: 'string' },
    mechanism: { type: 'string' },
    falsifiable_prediction: { type: 'string' },
    discriminating_experiment: {
      type: 'object',
      required: ['setup', 'command', 'expected_if_true', 'expected_if_false'],
      properties: {
        setup: { type: 'string' },
        command: { type: 'string' },
        expected_if_true: { type: 'string' },
        expected_if_false: { type: 'string' },
      },
      additionalProperties: false,
    },
    discriminates_against: { type: 'array', items: { type: 'string' } },
    prior: { type: 'number', minimum: 0, maximum: 1 },
  },
  additionalProperties: false,
}
const HYPOTHESES_OUT = {
  type: 'object',
  required: ['hypotheses'],
  properties: { hypotheses: { type: 'array', items: HYPOTHESIS } },
  additionalProperties: false,
}
const EXPERIMENT_OUT = {
  type: 'object',
  required: ['hypothesis_id', 'command', 'observed', 'verdict'],
  properties: {
    hypothesis_id: { type: 'string' },
    command: { type: 'string' },
    observed: { type: 'string', maxLength: 3000 },
    verdict: { enum: ['SUPPORTS', 'ELIMINATES', 'INCONCLUSIVE'] },
    artifact_path: { type: 'string' },
  },
  additionalProperties: false,
}
const EVIDENCE_PACK_OUT = {
  type: 'object',
  required: ['baselineFailure', 'stackTraces', 'suspectHistory', 'environment'],
  properties: {
    baselineFailure: { type: 'string', maxLength: 6000 },
    stackTraces: { type: 'string', maxLength: 4000 },
    suspectHistory: { type: 'string', maxLength: 4000 },
    environment: { type: 'string', maxLength: 1500 },
  },
  additionalProperties: false,
}
const FIX_OUT = {
  type: 'object',
  required: ['files_touched', 'description', 'repro_result', 'suite_result'],
  properties: {
    files_touched: { type: 'array', items: { type: 'string' } },
    description: { type: 'string', maxLength: 2000 },
    fix_summary_plain: { type: 'string', maxLength: 1000 }, // plain-language description of the fix
    repro_result: { enum: ['pass', 'fail', 'not-run'] },
    suite_result: { enum: ['green', 'red', 'unavailable', 'not-run'] },
  },
  additionalProperties: false,
}
const WARDEN_OUT = {
  type: 'object',
  required: ['porcelain'],
  properties: { porcelain: { type: 'string', maxLength: 3000 } },
  additionalProperties: false,
}

const REPO_RULES = `Target repository (work here, absolute paths): ${A.repo}
Rules: NEVER modify tracked files. New files ONLY under ${A.repo}/${SCRATCH}/. Read-only commands are fine.`
const OUTPUT_RULES = 'Your final message is machine-parsed against a JSON schema; return ONLY the structured data. Do not reference your role or instructions in any output field.'

// Taint guard (plugin CLAUDE.md invariant #5): experimenters (prover-analogs) are held to
// NEVER modify tracked files. A `git status --porcelain` warden between experiments catches
// drift so a stray tracked-file edit can't silently alter later experiments or the baseline.
const trackedLines = (s) => (s || '').split('\n').filter((l) => l.trim() && !l.startsWith('??')).sort().join('\n')
async function warden(label) {
  const w = await agent(
    `Run exactly one command in ${A.repo}: \`git status --porcelain\` and return its output verbatim (empty string if clean). ${OUTPUT_RULES}`,
    { label, phase: 'Experiments', model: 'haiku', effort: 'low', schema: WARDEN_OUT }
  )
  return w ? w.porcelain.trim() : null
}

// ═══ P0: Evidence collection ════════════════════════════════════════════════
phase('Evidence')
const pack = await agent(
  `You are collecting baseline evidence for a debugging council. ${REPO_RULES}

SYMPTOM: ${clip(A.symptom, 3000)}
${A.repro ? `REPRO COMMAND (run it ONCE, capture full output): ${A.repro}` : 'No repro command given — try to construct one cheaply from the symptom; if you succeed, run it once and note the command in baselineFailure.'}
${A.suspects.length ? `SUSPECT PATHS: ${A.suspects.join(', ')}` : ''}

Collect:
- baselineFailure: the repro's captured output (or best observed manifestation).
- stackTraces: any stack traces / error logs found (run the repro, check obvious log locations).
- suspectHistory: \`git log --oneline -8\` for suspect paths (or recently-changed files if none given) + any commit messages stating intent.
- environment: runtime versions and config facts that could matter (1-2 lines each).
${OUTPUT_RULES}`,
  { label: 'evidence', phase: 'Evidence', model: 'sonnet', effort: 'medium', schema: EVIDENCE_PACK_OUT }
)
if (!pack) throw new Error('evidence collection failed')

// Baseline tree state — experiments must leave tracked files untouched (taint guard, invariant #5).
let baselinePorcelain = await warden('warden:baseline')

// ═══ P1/P2: Hypothesis → experiment rounds ═══════════════════════════════════
const GENERATOR_LENSES = [
  { name: 'state-corruption', model: 'sonnet', card: 'Focus on wrong values/state: bad data, stale cache, wrong variable, incorrect mutation, off-by-one, type coercion.' },
  { name: 'causal-chain', model: 'opus', card: 'Trace the full causal chain backwards from the symptom to first causes; hypothesize the deepest plausible root, not the nearest.' },
  { name: 'environment', model: 'sonnet', card: 'Focus on environment/config/dependency causes: versions, platform differences, ordering/timing, filesystem state, external services.' },
]
const hypotheses = new Map() // id -> {h, status, round, experiments: []}
const experiments = []
let rootCause = null
let round = 0
function mechFingerprint(h) {
  return (h.mechanism || '').toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).slice(0, 10).join(' ')
}
const seenMech = new Set()
while (!rootCause && round < A.maxRounds) {
  round++
  phase('Hypotheses')
  const eliminated = [...hypotheses.values()].filter((x) => x.status === 'eliminated')
  const genOut = await parallel(
    GENERATOR_LENSES.map((g) => () =>
      agent(
        `You are a debugging hypothesis generator. Lens: ${g.card} ${REPO_RULES}

SYMPTOM: ${clip(A.symptom, 3000)}
BASELINE FAILURE: ${clip(pack.baselineFailure, 4000)}
STACK TRACES: ${clip(pack.stackTraces, 2500)}
SUSPECT HISTORY: ${clip(pack.suspectHistory, 2500)}
ENVIRONMENT: ${pack.environment}
${eliminated.length ? `ALREADY ELIMINATED (do not re-propose these mechanisms):\n${eliminated.map((x) => `- ${x.h.id}: ${x.h.statement} — eliminated because: ${clip(x.experiments.map((e) => e.observed).join('; '), 300)}`).join('\n')}` : ''}

Propose 1-3 hypotheses (ids H-${round}A, H-${round}B, …). Each MUST include a falsifiable_prediction (an observable that must hold if true) and a discriminating_experiment with a concrete runnable command whose outcome differs between true and false. Vague hypotheses are rejected by schema. Read the code before hypothesizing. ${OUTPUT_RULES}`,
        { label: `gen:${g.name}:r${round}`, phase: 'Hypotheses', model: g.model, effort: 'high', schema: HYPOTHESES_OUT }
      )
    )
  )
  let fresh = []
  for (const out of genOut.filter(Boolean)) {
    for (const h of out.hypotheses) {
      const fp = mechFingerprint(h)
      if (seenMech.has(fp)) continue
      seenMech.add(fp)
      if (hypotheses.size + fresh.length >= A.maxHypotheses + (round - 1) * 3) break
      fresh.push(h)
    }
  }
  for (const h of fresh) hypotheses.set(h.id, { h, status: 'live', round, experiments: [] })
  const live = [...hypotheses.values()].filter((x) => x.status === 'live')
  log(`round ${round}: +${fresh.length} hypotheses (${live.length} live)`)
  if (!live.length) break

  phase('Experiments')
  // Greedy ordering: experiments that discriminate against the most live hypotheses first
  const ordered = live
    .slice()
    .sort((a, b) => (b.h.discriminates_against?.length || 0) - (a.h.discriminates_against?.length || 0) || b.h.prior - a.h.prior)
  for (const x of ordered) {
    if (x.status !== 'live') continue // may have been eliminated by an earlier experiment this round
    const exp = await agent(
      `You are a debugging experimenter. Execute EXACTLY this discriminating experiment and judge the outcome. ${REPO_RULES}
Save any outputs under ${A.repo}/${SCRATCH}/experiments/.

HYPOTHESIS ${x.h.id}: ${x.h.statement}
MECHANISM: ${x.h.mechanism}
PREDICTION: ${x.h.falsifiable_prediction}
EXPERIMENT:
- setup: ${x.h.discriminating_experiment.setup}
- command: ${x.h.discriminating_experiment.command}
- expected if TRUE: ${x.h.discriminating_experiment.expected_if_true}
- expected if FALSE: ${x.h.discriminating_experiment.expected_if_false}

Run the setup and command (adapt paths minimally if needed, report what you actually ran). Compare observation to expectations. Verdict SUPPORTS only when the observation matches expected_if_true; ELIMINATES when it matches expected_if_false; INCONCLUSIVE otherwise. ${OUTPUT_RULES}`,
      { label: `exp:${x.h.id}`, phase: 'Experiments', model: 'sonnet', effort: 'high', schema: EXPERIMENT_OUT }
    )
    if (!exp) {
      x.status = 'inconclusive'
      continue
    }
    // Taint check: if the experimenter drifted tracked files, its verdict is untrustworthy
    // (a tracked-file edit can alter this and later experiments) — downgrade to INCONCLUSIVE.
    const after = await warden(`warden:exp:${x.h.id}`)
    const tainted = after !== null && baselinePorcelain !== null && trackedLines(after) !== trackedLines(baselinePorcelain)
    if (tainted) {
      exp.verdict = 'INCONCLUSIVE'
      exp.observed = `TAINTED: tracked files drifted during this experiment — verdict voided. ${clip(exp.observed, 2500)}`
      baselinePorcelain = after // absorb drift so the next experiment isn't re-flagged for the same edit
      log(`${x.h.id}: TAINTED (tracked-file drift) — verdict voided`)
    }
    experiments.push(exp)
    x.experiments.push(exp)
    if (exp.verdict === 'ELIMINATES') {
      x.status = 'eliminated'
      // cascade: this experiment may also discriminate against others
      for (const otherId of x.h.discriminates_against || []) {
        const o = hypotheses.get(otherId)
        if (o && o.status === 'live') o.status = 'weakened'
      }
    } else if (exp.verdict === 'SUPPORTS') {
      x.status = 'supported'
    } else {
      x.status = 'inconclusive'
    }
    log(`${x.h.id}: ${exp.verdict}`)
    const supported = [...hypotheses.values()].filter((v) => v.status === 'supported')
    const stillLive = [...hypotheses.values()].filter((v) => ['live', 'weakened', 'inconclusive'].includes(v.status))
    if (supported.length === 1 && stillLive.length === 0) break
  }
  const supported = [...hypotheses.values()].filter((v) => v.status === 'supported')
  if (supported.length === 1) rootCause = supported[0]
  else if (supported.length > 1) {
    // multiple supported: pick highest prior for confirmation; others stay for the report
    rootCause = supported.sort((a, b) => b.h.prior - a.h.prior)[0]
    log(`${supported.length} hypotheses supported — confirming strongest (${rootCause.h.id}); others reported as unresolved`)
  } else {
    // revive weakened/inconclusive as live for next round's refinement
    for (const v of hypotheses.values()) if (['weakened', 'inconclusive'].includes(v.status)) v.status = 'live'
  }
}

// ═══ P3: Confirmation — repro-then-fix-then-pass (only with --fix) ════════════
phase('Confirmation')
let fixSummary = null
let proposedFix = null
let confirmation = 'UNRESOLVED'
if (rootCause && A.fix) {
  // Explicit --fix: apply the minimal confirming fix, then INDEPENDENTLY verify (a separate
  // agent re-runs the repro + suite) rather than trusting the fixer's self-report.
  const fix = await agent(
    `You are the fixer confirming a debugging root cause by repro-then-fix-then-pass. You MAY edit tracked files in ${A.repo} (this is the one stage allowed to). Fix the root cause below at its source — minimal, in-convention, no symptom masking. Then re-run the repro (${A.repro || 'reconstruct from the baseline failure'}) and the suite (${A.testCmd || 'none provided → report suite_result="unavailable"'}). Also give a plain-language fix_summary_plain a non-engineer could follow.

ROOT CAUSE ${rootCause.h.id}: ${rootCause.h.statement}
MECHANISM: ${rootCause.h.mechanism}
SUPPORTING EXPERIMENT: ${clip(JSON.stringify(rootCause.experiments.at(-1) || {}), 1500)}
BASELINE FAILURE: ${clip(pack.baselineFailure, 2500)}
${OUTPUT_RULES}`,
    { label: 'fix', phase: 'Confirmation', model: 'sonnet', effort: 'high', schema: FIX_OUT }
  )
  fixSummary = fix
  const verify = await agent(
    `You are an INDEPENDENT verifier (you did NOT write the fix). In ${A.repo}, re-run and report honestly:
1. The repro: ${A.repro || '(reconstruct from the baseline failure)'} — repro_result pass/fail/not-run ('pass' = the failure is gone).
2. The suite: ${A.testCmd || 'none provided → suite_result="unavailable"'} — suite_result green/red/unavailable.
Report files_touched=[] and a one-line description of what you observed. ${OUTPUT_RULES}`,
    { label: 'verify', phase: 'Confirmation', model: 'haiku', effort: 'medium', schema: FIX_OUT }
  )
  const reproPass = (verify?.repro_result ?? fix?.repro_result) === 'pass'
  // A red OR not-run suite fails the gate; only a green or (legitimately) unavailable suite passes.
  const suiteOk = ['green', 'unavailable'].includes(verify?.suite_result ?? fix?.suite_result ?? 'not-run')
  if (fix && reproPass && suiteOk) {
    confirmation = 'ROOT-CAUSED'
  } else {
    confirmation = 'FIX-FAILED'
    rootCause.status = 'demoted'
    log('independent verify did not confirm repro flip + non-red suite — hypothesis demoted; report as unresolved')
  }
} else if (rootCause) {
  // Surface-first default: propose the fix WITHOUT applying it. The operator directs the fix.
  proposedFix = await agent(
    `You are proposing (NOT applying) the root-cause fix for a confirmed debugging hypothesis. Do NOT modify any tracked file — read the code and describe the minimal, in-convention fix at its source. ${REPO_RULES}

ROOT CAUSE ${rootCause.h.id}: ${rootCause.h.statement}
MECHANISM: ${rootCause.h.mechanism}
SUPPORTING EXPERIMENT: ${clip(JSON.stringify(rootCause.experiments.at(-1) || {}), 1500)}
BASELINE FAILURE: ${clip(pack.baselineFailure, 2500)}

Report: files_touched = the file(s) the fix WOULD change; description = the technical fix (what to change and why it removes the root cause); fix_summary_plain = 1-2 sentences a non-engineer could follow; repro_result="not-run"; suite_result="not-run". ${OUTPUT_RULES}`,
    { label: 'propose-fix', phase: 'Confirmation', model: 'sonnet', effort: 'high', schema: FIX_OUT }
  )
  confirmation = 'ROOT-CAUSED-UNFIXED'
}

log(`done: ${confirmation} · ${[...hypotheses.values()].filter((x) => x.status === 'eliminated').length} eliminated`)
return {
  runId: A.runId,
  symptom: clip(A.symptom, 500),
  evidencePack: pack,
  hypotheses: [...hypotheses.values()].map((x) => ({ ...x.h, status: x.status, round: x.round })),
  experiments,
  rootCause: rootCause ? { ...rootCause.h, status: rootCause.status } : null,
  fixSummary,
  proposedFix,
  status: confirmation,
  rounds: round,
  budgetSpent: budget.spent(),
  scratchDir: SCRATCH,
}
