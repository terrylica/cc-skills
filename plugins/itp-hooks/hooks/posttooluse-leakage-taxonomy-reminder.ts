#!/usr/bin/env bun
/**
 * PostToolUse hook: temporal-leakage adjudication taxonomy reminder.
 *
 * Fires on Write/Edit/MultiEdit of a TEXT file when the NEW content contains
 * language that ADJUDICATES temporal leakage — a leak-family term sitting next
 * to a verdict word ("the H1 join is non-causal, so the reported AUC is
 * manufactured"). It injects the five-category taxonomy so the verdict is
 * CLASSIFIED rather than collapsed into a single undifferentiated "leaky →
 * reject".
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this reminder exists — the failure mode it guards
 * ════════════════════════════════════════════════════════════════════════
 *
 * The observed agent failure is OVER-RULING-OUT: every temporal irregularity
 * gets flattened to "leakage", every "leakage" to "reject", and a valid result
 * is thrown away. That is not hypothetical — it happened twice in the xaubot
 * audit that produced this doctrine:
 *
 *   1. The L3 HMM regime feature was called leaky end-to-end. It is MIXED:
 *      `scaler.fit_transform` over all data is CAT-2 (train-time-only) and
 *      whole-sequence Viterbi is non-causal IN TRAINING, but at the final bar
 *      both HMM calls are causal, so the LIVE path does not leak. The over-call
 *      was retracted by measurement.
 *   2. CAT-2 was repeatedly lumped in with CAT-3. Isolated on identical folds,
 *      seeds and fills it is worth +0.0014 AUC (`clean_reg` arm, the regime /
 *      HMM fitted axis) and +0.0042 (`cat2_only` arm) — 0.6–1.9% of the effect
 *      — and walk-forward DOES remove it. Its own canonical exemplar, a
 *      `StandardScaler` frozen and replayed, diverges on 0.000000% of 3,000
 *      samples (max abs diff 0.0). CAT-3 is the opposite: 8-fold rolling WF
 *      leaves leaky WFE(Sharpe) at 0.991 with 8/8 folds positive, an embargo
 *      swept to 5,000 bars does not dent it, and `leaky_noreg` (zero fitted
 *      parameters contaminated) reproduces the full leaky OOS AUC of 0.737.
 *      CAT-3 is 100% of the lift; CAT-2 is 0.6%. Treating them as one category
 *      is a measurable category error, not a stylistic quibble.
 *
 * The counterweight matters just as much: L4's `consecutive_direction` looks
 * perfectly causal and is univariately worthless, yet `direction × (L − p)` —
 * direction times BARS REMAINING — scores AUC 0.7342 alone. A leak that LOOKS
 * causal is exactly why the decisive test has to be MECHANICAL (prefix
 * invariance / streaming replay), never intent and never plausibility.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why NON-BLOCKING, and why once per session
 * ════════════════════════════════════════════════════════════════════════
 *
 * A blocking guard here would reproduce the exact failure it is meant to
 * prevent: it would rule out the agent's own sentence on suspicion, with no
 * measurement, which is the over-ruling-out pattern wearing a hook costume. So
 * this returns `{ kind: "additional_context" }`, which the iter-93 orchestrator
 * folds into one `{ decision: "block", reason }` emission — a Claude-visible
 * system reminder that does NOT undo the edit and carries no deny/ask.
 *
 * Once per session because the payload is a static doctrine card. Its value is
 * "you are entering an adjudication, here is the taxonomy"; repeating it on
 * every paragraph of a long audit write-up would be pure token tax. The gate is
 * claimed ONLY after a match, so a session full of unrelated edits still has
 * its reminder available for the first real verdict.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Detection: precision AND the once-per-session gate are ONE axis
 * ════════════════════════════════════════════════════════════════════════
 *
 * An adversarial review of the first implementation found the interaction that
 * governs this design: because the card fires at most once, EVERY false
 * positive is ALSO a false negative — it silently spends the session's single
 * shot before the verdict that needed it was written. A `LeakyReLU` import at
 * 09:00 would disable the hook for the rest of the day. So precision is not the
 * usual "a chatty reminder is merely annoying" trade; it is the whole design.
 *
 * Three mechanisms carry it, all measured against a real corpus (the 12 xaubot
 * adjudication documents) and a real negative corpus (naturalistic non-temporal
 * leak text plus a random sample of on-disk repo files):
 *
 *  1. TWO LEAK TIERS. `look-ahead`, `lookahead`, `data-snooping`, `non-causal`,
 *     `acausal`, `contaminat*`, `leakage`, `CAT-[123]` and qualified compounds
 *     (`data leak`, `label leak`, `temporal leak`…) are DOMAIN-SPECIFIC: they
 *     essentially only occur in this discourse. Bare `leak` / `leaks` /
 *     `leaked` / `leaky` is GENERIC — the sense that dominates real code is a
 *     memory/fd/goroutine leak, not a temporal one.
 *
 *  2. TWO VERDICT TIERS. DECISIVE verdict words (`falsified`, `refuted`,
 *     `rejected`, `condemned`, `manufactured`, `spurious`, `no edge`,
 *     `not genuine`, `overstated`, `ruled out`…) are the register this corpus
 *     actually writes verdicts in; they were read OFF the corpus, not guessed.
 *     WEAK words (`fails`, `invalid`, `discard`, `dismiss`, `artifact`,
 *     `collapses`, `inflated`, `coin flip`) are ordinary English that happens
 *     to sit near leak-shaped words in ordinary code.
 *
 *     FIRING RULE: `DOMAIN ∧ (DECISIVE ∨ WEAK)` or `GENERIC ∧ DECISIVE`.
 *     A weak verdict word never fires on a bare `leak` — that single rule
 *     removes the memory-leak-test, fd-leak, CSS-`leak`-class and
 *     news-leak false positives outright.
 *
 *  3. SENSE-WINDOW EXCLUSION. A leak-term hit is discarded when its ±80-char
 *     neighbourhood names a NON-temporal sense: `memory`/`heap`/`goroutine`/
 *     `descriptor` (resource leaks), `relu`/`torch`/`nn.` (LeakyReLU),
 *     `one-token`/`parser`/`lexer` (parser lookahead), `filtfilt`/`zero-phase`
 *     (DSP acausal filters), `water`/`gasket`, `the press`/`memo`,
 *     `gitleaks`/`credential` (secret leakage), `mise`/`env var`. This is what
 *     `\bleak\w*` matching `leaky_relu` deserved instead of a word boundary
 *     argument, and it generalises: the sense, not the spelling, is the signal.
 *
 * Two vocabulary corrections earned by measurement, recorded so they are not
 * re-introduced:
 *
 *   - `leaky` is NOT a verdict word. In the first implementation it was, which
 *     silently collapsed the two-term conjunction into "mentions leak twice":
 *     15 of 15 sentence-level fires over 1,448 corpus sentences had
 *     verdictTerm ∈ {leak,LEAKY,Leaky}, and not one was an adjudication.
 *     "three named leaks fixed = 0.7328 against a leaky control of 0.7520" is a
 *     measurement report, and it fired.
 *   - `invalid\w*` is NOT the right shape: it matches `invalidation`, and
 *     "cache invalidation" was the single most common false positive in real
 *     source. The inflections are spelled out instead.
 *
 * Non-overlap of the two spans is still enforced. With `leaky` gone from the
 * verdict side no term matches both patterns any more, so it is now DEFENSIVE
 * hygiene rather than the load-bearing rule it was originally billed as; it
 * keeps a future vocabulary addition from silently re-creating the collapse.
 *
 * Detection runs on the NEW content only (Write `content`, Edit `new_string`,
 * each MultiEdit fragment independently), never on the whole file — the hook
 * responds to a verdict being WRITTEN, not to one that was already there.
 * MultiEdit fragments are scanned SEPARATELY so proximity cannot be manufactured
 * by two unrelated edits landing adjacent in a concatenation.
 *
 * Suppression is the mirror image and IS whole-file: `LEAK-TAXONOMY-OK` in the
 * edited fragment OR anywhere in the post-edit file silences it, because the
 * operator declaring "I know the taxonomy" is a whole-document statement. The
 * file read happens ONLY after a fragment match, so the common path stays
 * read-free. (In the first implementation `classify()` never passed the file
 * content, so the whole-file arm was dead code — and an ordinary Edit to the
 * doctrine spoke, whose own header names the marker, fired the hook on its own
 * doctrine. That is now a regression test.)
 *
 * Fail-open everywhere: any error, unreadable input, or binary payload → noop.
 *
 * Doctrine SSoT: ~/.claude/leakage-taxonomy-CLAUDE.md
 * Taxonomy provenance: independent GPT-5.6 methodological review,
 * video-forensics/corpus/xaubot/honest-bias-doctrine-gpt.md §4.1–4.5.
 * Measured figures: video-forensics/corpus/xaubot/RULING.md (which supersedes
 * VERDICT.json / DEEP-DIVE-VERDICT.json / RETRAIN-VERDICT.json).
 */

import { readFileSync, statSync } from "node:fs";

import {
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  type PostToolUseInput,
  type PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName } from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
// Iter-124: a throwaway scratch copy must not consume the once-per-session
// gate, or the first REAL adjudication of the session goes unreminded.
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Constants
// ══════════════════════════════════════════════════════════════════════════

const HOOK_NAME = "leakage-taxonomy-reminder";

const LEAK_TAXONOMY_OK_MARKER = "LEAK-TAXONOMY-OK";

const LEAKAGE_TAXONOMY_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE = "leakage-taxonomy";

/**
 * Maximum character distance between the leak-family term and the verdict word
 * for the pair to count as ONE adjudication — and it is NOT one number, because
 * the two tiers do not deserve the same reach.
 *
 * Calibrated, not guessed. Over the 12-document xaubot corpus every genuine
 * adjudication pair lands at d ≤ 48 (`look-ahead|artifact` d=11,
 * `look-ahead|manufactured` d=16, `look-ahead|coin flip` d=20,
 * `look-ahead|invalidates` d=27, `Leak|worthless` d=48), while the surviving
 * false positives over a 1,198-file random sample of real repo files clustered
 * at d = 79…141 (`look-ahead|artifacts` d=127 in a build-artifacts ADR,
 * `leakage|FAILED` d=135 in an unrelated integration test). Distance is a
 * genuine discriminator here, so the weaker the evidence the tighter the reach.
 *
 *  - DOMAIN leak + DECISIVE verdict — 200 chars, two sentences of prose,
 *    wide enough for "…is non-causal at decision time. We therefore reject the
 *    reported AUC."
 *  - GENERIC leak (bare `leak*`) — 100 chars. It only ever pairs with a
 *    decisive verdict anyway; the shorter reach stops "…is not leaked" and
 *    "lxml rejects them" three lines apart from conjoining.
 *  - WEAK verdict (`fails`, `artifact`, `collapses`…) — 80 chars, tight
 *    coupling only. This is the single change that removes the build-artifact
 *    and integration-test false positives without losing one corpus verdict.
 */
const DOMAIN_LEAK_WITH_DECISIVE_VERDICT_PROXIMITY_WINDOW_CHARACTERS = 200;
const GENERIC_LEAK_PROXIMITY_WINDOW_CHARACTERS = 100;
const WEAK_VERDICT_PROXIMITY_WINDOW_CHARACTERS = 80;

/**
 * Half-width of the neighbourhood inspected around a leak-term hit for
 * evidence that the word carries a NON-temporal sense. 80 chars each side is
 * about one line of code plus its comment — the distance at which `LeakyReLU`
 * still has `torch`/`nn.` in view and `acausal` still has `filtfilt` in view.
 */
const LEAK_TERM_SENSE_DISAMBIGUATION_WINDOW_HALF_WIDTH_CHARACTERS = 80;

/**
 * Whole-file suppression reads the post-edit file. Cap the read so a
 * multi-megabyte generated `.jsonl` cannot turn a reminder into a stall; past
 * the cap we simply do not suppress (the fragment-level marker check already
 * ran, and failing to suppress is the non-destructive direction).
 */
const MAXIMUM_POST_EDIT_FILE_BYTES_READ_FOR_WHOLE_FILE_MARKER_SUPPRESSION = 4 * 1024 * 1024;

/**
 * Text files whose prose can carry a verdict. Deliberately broad (findings
 * docs, notebooks, analysis scripts, config-as-documentation) but an ALLOWLIST,
 * so a `.parquet`, `.png` or `.mp4` written through Write never reaches the
 * scanner. The binary sniff below is the second line of defence for a binary
 * payload wearing a text extension.
 */
const TEXT_FILE_EXTENSIONS_ELIGIBLE_FOR_LEAKAGE_TAXONOMY_REMINDER: ReadonlySet<string> = new Set([
  ".md",
  ".markdown",
  ".mdx",
  ".txt",
  ".rst",
  ".org",
  ".tex",
  ".adoc",
  ".ipynb",
  ".py",
  ".pyi",
  ".r",
  ".jl",
  ".sql",
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".cjs",
  ".rs",
  ".go",
  ".json",
  ".jsonl",
  ".yaml",
  ".yml",
  ".toml",
  ".sh",
  ".bash",
]);

/**
 * DOMAIN-SPECIFIC leak vocabulary: terms that essentially only occur when
 * someone is talking about temporal/train-test leakage. `CAT-[123]` lives here
 * rather than on the verdict side because in this doctrine `CAT-2` NAMES a
 * leakage category — it is the subject of the adjudication, not the ruling.
 * `data[\s._-]?snoop\w*` is spelled out rather than using `.` so that
 * "database snooping" cannot masquerade as "data-snooping".
 */
const DOMAIN_SPECIFIC_TEMPORAL_LEAK_TERM_PATTERN =
  /\b(?:look-?ahead\w*|lookahead\w*|data[\s._-]?snoop\w*|non-?causal\w*|acausal\w*|contaminat\w*|leakage\w*|CAT-[123]|prefix[\s-]invarian\w*|(?:data|label|target|temporal|future|forward|train[\s-]?test|train[\s-]?time|feature|outcome)[\s._-]leak\w*)/gi;

/**
 * GENERIC leak vocabulary: the bare noun/verb/adjective. In real source the
 * dominant sense is a resource leak, so a hit here is only ever half of an
 * adjudication when the OTHER half is a decisive verdict word.
 */
const GENERIC_LEAK_TERM_PATTERN = /\b(?:leak\w*)/gi;

/**
 * Full-match spellings that are never a leak in any sense — an identifier that
 * merely starts with the letters. Tested against the WHOLE matched text.
 */
const NEVER_A_LEAK_IDENTIFIER_FULL_MATCH_PATTERN = /^leaky_?relu$/i;

/**
 * Evidence, in the neighbourhood of a leak-term hit, that the word carries a
 * NON-temporal sense. Every entry below was added because it produced a
 * measured false positive, and each is deliberately narrow: `\bthe press\b`
 * rather than `press` (which is inside "compress"), `\bmise\b` rather than
 * `mise` (which is inside "premise"), `filtfilt`/`zero-phase` rather than
 * `signal.` (which is inside "…the calibrated synthetic signal.").
 */
const NON_TEMPORAL_LEAK_SENSE_NEIGHBOURHOOD_EVIDENCE_PATTERN = new RegExp(
  [
    // Resource leaks.
    String.raw`memory|heap|\brss\b|malloc|calloc|free\(|\bgc\b|goroutine|goleak|\bthreads?\b`,
    String.raw`|\bfds?\b|fd_|file[\s_-]?descriptor|descriptor|socket|connection pool|lsof|valgrind|sanitizer|leakcanary`,
    // LeakyReLU and friends.
    String.raw`|relu|torch|tensorflow|keras|\bnn\.|negative_slope|leaky[\s_-]?bucket|leaky abstraction`,
    // Parser / regex lookahead.
    String.raw`|parser|lexer|grammar|syntaxkind|one-token|two-token|k-token|peek\(|\bLL\(|\bLR\(|regexp?\b`,
    // Physical leaks.
    String.raw`|water|plumb|gasket|riser|faucet|\bpipes?\b`,
    // Disclosure leaks.
    String.raw`|\bthe press\b|journalist|newspaper|reporter|\bmemos?\b|whistleblow`,
    // Zero-phase / offline DSP filters ("acausal" in its signal-processing sense).
    String.raw`|filtfilt|zero-?phase|forward\+backward|savgol|butterworth`,
    // Secret leakage.
    String.raw`|gitleaks|trufflehog|\bsecrets?\b|credential|password|api[\s_-]?keys?|env(?:ironment)?[\s_-]?var|__MISE|\bmise\b|dotenv`,
  ].join(""),
  "i",
);

/**
 * DECISIVE verdict vocabulary — the register in which this corpus actually
 * writes adjudications. Read OFF the corpus, not guessed: `CLAIM FALSIFIED`
 * (SEED-AVERAGING-VERDICT `$.verdict`), `NO EDGE SURVIVES` (RETRAIN-VERDICT
 * `$.verdict`), `manufactured by look-ahead` (DEEP-DIVE-VERDICT
 * `$.THE_DECISIVE_FINDING.headline`), `condemned by a leak` (RETRAIN-VERDICT
 * `$.purpose`), `REFUTED as originally framed`, `overstated`, `ruled out`.
 *
 * A term here fires against EITHER leak tier.
 */
const DECISIVE_ADJUDICATION_VERDICT_TERM_PATTERN = new RegExp(
  [
    String.raw`\b(?:falsif\w*|refut\w*|reject\w*|disqualif\w*|condemn\w*|manufactur\w*`,
    String.raw`|spurious|illusor\w*|bogus|overstat\w*|unusable|untrustworthy|worthless`,
    String.raw`|rul(?:e|ed|es|ing)\s+out|thr(?:ow|own|ew)\s+away`,
    String.raw`|no\s+(?:real\s+|genuine\s+)?edge\b|not\s+(?:a\s+)?(?:real|genuine|valid)\b)`,
  ].join(""),
  "gi",
);

/**
 * WEAK verdict vocabulary — ordinary English that happens to sit near
 * leak-shaped words in ordinary code ("a leak here fails the budget"). Fires
 * ONLY alongside a DOMAIN-SPECIFIC leak term.
 *
 * Note the invalid family is an explicit alternation, NOT `invalid\w*`: the
 * open tail matched "cache invalidation", which was the single most common
 * false positive in real source.
 */
const WEAK_ADJUDICATION_VERDICT_TERM_PATTERN = new RegExp(
  [
    String.raw`\b(?:fail\w*|invalid|invalidly|invalidity|invalidate|invalidates|invalidated|invalidating`,
    String.raw`|discard\w*|dismiss\w*|fatal\w*|artifacts?|artefacts?|collaps\w*|inflat\w*|coin\s+flip)\b`,
  ].join(""),
  "gi",
);

// ══════════════════════════════════════════════════════════════════════════
//  Reminder message (static doctrine card — paid once per session, per fire)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Kept under 900 characters on purpose: it is injected into context on every
 * fire, and a doctrine card nobody finishes reading is a doctrine card that
 * does not change behaviour. Every line earns its place — the taxonomy, the one
 * measured correction agents get wrong most (CAT-2), the two epistemic rules
 * (UNKNOWN is not a finding; prefix invariance decides), the purge-vs-embargo
 * split, and the two pointers.
 *
 * BOTH lengths are pinned by test: JS `.length` (UTF-16 units) AND UTF-8
 * bytes, because the card contains `·` and `—` and the two numbers differ.
 * 896 chars / 907 bytes today, and both are deliberate.
 */
export const LEAKAGE_TAXONOMY_ADJUDICATION_STATIC_REMINDER_MESSAGE = [
  "[LEAK-TAXONOMY] Adjudicating temporal leakage — classify before you reject.",
  "CB causal-batch=ACCEPT · PT privileged TRAIN_ONLY=ACCEPT WITH DECLARATION · BP outcome-overlap=REJECT until exact records removed · EC eval-contamination=REJECT as OOS · DN decision-time-noncausal=REJECT for that decision time.",
  "CAT-2 (train-time-only, e.g. a scaler fitted on the training fold) is NOT a leak: measured +0.0014..+0.0042 AUC here, and walk-forward DOES remove it. Never lump it with CAT-3.",
  'UNKNOWN is not a leak finding — write "unverified", not "leaky".',
  "Decisive test = prefix invariance / prefix replay. Not intent, not plausibility, not how causal the feature looks.",
  "A mandatory availability exclusion (label matured by the training origin) is required; an OPTIONAL dependence gap beyond it is not — dependence_gap=0 is defensible.",
  "SSoT ~/.claude/leakage-taxonomy-CLAUDE.md · Override: LEAK-TAXONOMY-OK",
].join("\n");

// ══════════════════════════════════════════════════════════════════════════
//  Types
// ══════════════════════════════════════════════════════════════════════════

/** `PostToolUseInput.tool_input` with the MultiEdit `edits[]` array named. */
interface MultiEditCapableToolInput {
  file_path?: string;
  content?: string;
  old_string?: string;
  new_string?: string;
  edits?: Array<{ old_string?: string; new_string?: string }>;
}

/** A matched adjudication: which two terms conjoined, how far apart, at which tiers. */
export interface LeakageAdjudicationMatch {
  leakTerm: string;
  verdictTerm: string;
  characterDistance: number;
  /** `domain` = temporal-leakage jargon; `generic` = a bare `leak*`. */
  leakTermTier: "domain" | "generic";
  /** `decisive` = adjudication register; `weak` = ordinary English. */
  verdictTermTier: "decisive" | "weak";
}

// ══════════════════════════════════════════════════════════════════════════
//  Eligibility
// ══════════════════════════════════════════════════════════════════════════

function getFileExtensionIncludingLeadingDotLowercased(filePath: string): string {
  const lastDotIndex = filePath.lastIndexOf(".");
  if (lastDotIndex < 0) return "";
  return filePath.slice(lastDotIndex).toLowerCase();
}

/**
 * Code point of NUL, named so no source file here ever has to contain one.
 */
const NUL_CODE_POINT = 0;

/** How much of a payload's head is probed for the binary signal. */
const BINARY_SNIFF_PREFIX_LENGTH_CHARACTERS = 1024;

/**
 * A NUL byte is the standard "this is not text" signal (it is what `git` and
 * `grep` use). Cheap O(1)-ish prefix probe: a binary blob has one within its
 * first kilobyte essentially always, and prose never does.
 */
function looksLikeBinaryPayloadRatherThanText(text: string): boolean {
  const limit = Math.min(text.length, BINARY_SNIFF_PREFIX_LENGTH_CHARACTERS);
  for (let index = 0; index < limit; index++) {
    if (text.charCodeAt(index) === NUL_CODE_POINT) return true;
  }
  return false;
}

/**
 * Pure activation gate (exported for tests): a Write/Edit/MultiEdit of a
 * durable text file, never a throwaway copy in a temp scratch dir.
 */
export function isLeakageTaxonomyReminderEligibleTarget(
  toolName: string,
  filePath: string,
): boolean {
  if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(toolName)) return false;
  if (!filePath) return false;
  if (
    !TEXT_FILE_EXTENSIONS_ELIGIBLE_FOR_LEAKAGE_TAXONOMY_REMINDER.has(
      getFileExtensionIncludingLeadingDotLowercased(filePath),
    )
  ) {
    return false;
  }
  if (
    isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
      filePath,
    )
  ) {
    return false;
  }
  return true;
}

// ══════════════════════════════════════════════════════════════════════════
//  Two-tier two-term proximity detection
// ══════════════════════════════════════════════════════════════════════════

interface MatchedTermSpan {
  text: string;
  startIndex: number;
  endIndex: number;
}

/** All non-overlapping matches of a global regex, as spans. */
function collectMatchedTermSpans(text: string, globalPattern: RegExp): MatchedTermSpan[] {
  // A fresh RegExp per call: the module-level patterns carry /g, and sharing
  // lastIndex across calls would make detection depend on call order.
  const pattern = new RegExp(globalPattern.source, globalPattern.flags);
  const spans: MatchedTermSpan[] = [];
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null) {
    spans.push({ text: match[0], startIndex: match.index, endIndex: match.index + match[0].length });
    if (match.index === pattern.lastIndex) pattern.lastIndex++; // zero-width guard
    match = pattern.exec(text);
  }
  return spans;
}

/**
 * True when the neighbourhood of `span` names a non-temporal sense of the word
 * — a memory leak, a LeakyReLU, a parser lookahead, an acausal DSP filter, a
 * leaked memo, a leaked credential.
 *
 * Exported so the sense list can be exercised directly by tests: it is the
 * mechanism that keeps a `torch.nn.LeakyReLU` import from burning the
 * session's single reminder.
 */
export function hasNonTemporalLeakSenseEvidenceAroundSpan(
  text: string,
  startIndex: number,
  endIndex: number,
): boolean {
  const windowStart = Math.max(
    0,
    startIndex - LEAK_TERM_SENSE_DISAMBIGUATION_WINDOW_HALF_WIDTH_CHARACTERS,
  );
  const windowEnd = Math.min(
    text.length,
    endIndex + LEAK_TERM_SENSE_DISAMBIGUATION_WINDOW_HALF_WIDTH_CHARACTERS,
  );
  return NON_TEMPORAL_LEAK_SENSE_NEIGHBOURHOOD_EVIDENCE_PATTERN.test(
    text.slice(windowStart, windowEnd),
  );
}

interface TieredLeakTermSpan extends MatchedTermSpan {
  tier: "domain" | "generic";
}

/**
 * Leak-term spans, tiered and sense-filtered. A generic `leak*` span that is
 * merely the tail of a domain span (`leakage`, `data leak`) is dropped so the
 * same characters are never counted at the lower tier.
 */
function collectTieredLeakTermSpans(text: string): TieredLeakTermSpan[] {
  const domainSpans = collectMatchedTermSpans(text, DOMAIN_SPECIFIC_TEMPORAL_LEAK_TERM_PATTERN);
  const genericSpans = collectMatchedTermSpans(text, GENERIC_LEAK_TERM_PATTERN).filter(
    (generic) =>
      !domainSpans.some(
        (domain) => generic.startIndex < domain.endIndex && domain.startIndex < generic.endIndex,
      ),
  );

  const tiered: TieredLeakTermSpan[] = [
    ...domainSpans.map((s) => ({ ...s, tier: "domain" as const })),
    ...genericSpans.map((s) => ({ ...s, tier: "generic" as const })),
  ];

  return tiered.filter(
    (span) =>
      !NEVER_A_LEAK_IDENTIFIER_FULL_MATCH_PATTERN.test(span.text) &&
      !hasNonTemporalLeakSenseEvidenceAroundSpan(text, span.startIndex, span.endIndex),
  );
}

interface TieredVerdictTermSpan extends MatchedTermSpan {
  tier: "decisive" | "weak";
}

function collectTieredVerdictTermSpans(text: string): TieredVerdictTermSpan[] {
  const decisiveSpans = collectMatchedTermSpans(text, DECISIVE_ADJUDICATION_VERDICT_TERM_PATTERN);
  const weakSpans = collectMatchedTermSpans(text, WEAK_ADJUDICATION_VERDICT_TERM_PATTERN).filter(
    (weak) =>
      !decisiveSpans.some(
        (decisive) => weak.startIndex < decisive.endIndex && decisive.startIndex < weak.endIndex,
      ),
  );
  return [
    ...decisiveSpans.map((s) => ({ ...s, tier: "decisive" as const })),
    ...weakSpans.map((s) => ({ ...s, tier: "weak" as const })),
  ];
}

/**
 * How far apart the two terms may sit, given how strong each one is. Exported
 * so the calibration above is directly assertable rather than folded into an
 * end-to-end expectation.
 */
export function resolveProximityWindowForTierPair(
  leakTermTier: "domain" | "generic",
  verdictTermTier: "decisive" | "weak",
): number {
  if (verdictTermTier === "weak") return WEAK_VERDICT_PROXIMITY_WINDOW_CHARACTERS;
  if (leakTermTier === "generic") return GENERIC_LEAK_PROXIMITY_WINDOW_CHARACTERS;
  return DOMAIN_LEAK_WITH_DECISIVE_VERDICT_PROXIMITY_WINDOW_CHARACTERS;
}

/**
 * The closest leak-term / verdict-term pair that satisfies the FIRING RULE —
 * `DOMAIN ∧ (DECISIVE ∨ WEAK)` or `GENERIC ∧ DECISIVE` — occupies DISTINCT
 * spans, and sits within the proximity window. `null` when nothing qualifies.
 *
 * The non-overlap test is `a.endIndex <= b.startIndex || b.endIndex <= a.startIndex`.
 * With `leaky` removed from the verdict vocabulary no term matches both sides
 * any more, so this is now defensive rather than load-bearing — it exists so a
 * future vocabulary addition cannot silently re-create "mentions leak twice".
 */
export function findNearestNonOverlappingTermPair(text: string): LeakageAdjudicationMatch | null {
  if (!text) return null;
  const leakSpans = collectTieredLeakTermSpans(text);
  if (leakSpans.length === 0) return null;
  const verdictSpans = collectTieredVerdictTermSpans(text);
  if (verdictSpans.length === 0) return null;

  let best: LeakageAdjudicationMatch | null = null;
  for (const leak of leakSpans) {
    for (const verdict of verdictSpans) {
      if (leak.tier === "generic" && verdict.tier === "weak") continue; // firing rule
      const disjoint = leak.endIndex <= verdict.startIndex || verdict.endIndex <= leak.startIndex;
      if (!disjoint) continue;
      const characterDistance = Math.abs(leak.startIndex - verdict.startIndex);
      if (characterDistance > resolveProximityWindowForTierPair(leak.tier, verdict.tier)) continue;
      if (best === null || characterDistance < best.characterDistance) {
        best = {
          leakTerm: leak.text,
          verdictTerm: verdict.text,
          characterDistance,
          leakTermTier: leak.tier,
          verdictTermTier: verdict.tier,
        };
      }
    }
  }
  return best;
}

// ══════════════════════════════════════════════════════════════════════════
//  Escape-hatch suppression (fragment, then whole post-edit file)
// ══════════════════════════════════════════════════════════════════════════

/** `LEAK-TAXONOMY-OK` anywhere in the blob (iter-107 canonical helper). */
function hasLeakTaxonomyEscapeHatchMarker(text: string): boolean {
  return hasFileWideEscapeHatchMarkerInContent(text, {
    markerNameTokenIncludingSuffix: LEAK_TAXONOMY_OK_MARKER,
  });
}

/**
 * FILE_WIDE suppression, for real this time: read the file as it stands AFTER
 * the edit and look for the marker anywhere in it.
 *
 * Called only once a fragment has already matched, so the common path never
 * touches the filesystem. Fail-open on any error (missing file, permissions,
 * oversize, non-UTF-8): not suppressing is the direction that preserves the
 * reminder, and the fragment check has already run.
 *
 * Exported for tests: the regression this closes is an ordinary Edit to
 * `~/.claude/leakage-taxonomy-CLAUDE.md`, whose own header names the marker,
 * firing the hook on its own doctrine.
 */
export function isLeakTaxonomySuppressedByWholeFilePostEditMarker(filePath: string): boolean {
  try {
    if (statSync(filePath).size > MAXIMUM_POST_EDIT_FILE_BYTES_READ_FOR_WHOLE_FILE_MARKER_SUPPRESSION) {
      return false;
    }
    return hasLeakTaxonomyEscapeHatchMarker(readFileSync(filePath, "utf8"));
  } catch {
    return false;
  }
}

/**
 * The verdict this tool call WROTE (exported for tests), or `null`.
 *
 * Scans the NEW content only — Write `content`, Edit `new_string`, and each
 * MultiEdit fragment independently. Fragments are never concatenated: doing so
 * would let a "leak" at the tail of edit 1 conjoin with a "fails" at the head
 * of edit 2, an adjacency that exists nowhere in the file.
 *
 * Whole-file suppression is NOT done here — it is a separate, explicitly
 * ordered step in `classify()` (see
 * `isLeakTaxonomySuppressedByWholeFilePostEditMarker`). This function has one
 * job and no filesystem access.
 */
export function detectTemporalLeakageAdjudicationVerdictLanguage(
  input: PostToolUseInput,
): LeakageAdjudicationMatch | null {
  const toolInput = (input.tool_input || {}) as MultiEditCapableToolInput;

  const newContentFragments: string[] =
    input.tool_name === "Write"
      ? [toolInput.content || ""]
      : input.tool_name === "MultiEdit"
        ? (toolInput.edits || []).map((e) => e.new_string || "")
        : [toolInput.new_string || ""];

  for (const fragment of newContentFragments) {
    if (!fragment) continue;
    if (looksLikeBinaryPayloadRatherThanText(fragment)) continue;
    if (hasLeakTaxonomyEscapeHatchMarker(fragment)) continue;
    const match = findNearestNonOverlappingTermPair(fragment);
    if (match !== null) return match;
  }
  return null;
}

// ══════════════════════════════════════════════════════════════════════════
//  Session-id sanitisation for the gate-file path
// ══════════════════════════════════════════════════════════════════════════

/**
 * The shared gate helper interpolates its `sessionId` straight into
 * `/tmp/.claude-<name>-reminder/<sessionId>.reminded`. A session id of
 * `../../tmp/pwned` therefore creates a file OUTSIDE the gate directory —
 * demonstrated, not theorised. Reduce to a single path component and an
 * alphanumeric-ish charset before it ever reaches the join.
 *
 * Exported for tests. Empty/degenerate input collapses to a constant rather
 * than to `""` (which would produce a dotfile named `.reminded` shared by every
 * such session — still safe, but silently global).
 */
export function sanitizeSessionIdentifierForGateFilePathComponent(rawSessionId: string): string {
  const lastSeparator = Math.max(rawSessionId.lastIndexOf("/"), rawSessionId.lastIndexOf("\\"));
  const basename = lastSeparator >= 0 ? rawSessionId.slice(lastSeparator + 1) : rawSessionId;
  const sanitized = basename.replace(/[^A-Za-z0-9._-]/g, "-").replace(/^\.+/, "");
  return sanitized.length > 0 ? sanitized.slice(0, 128) : "unknown-session";
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Classify a PostToolUse Write|Edit|MultiEdit for temporal-leakage-adjudication
 * language and, ONCE PER SESSION, inject the taxonomy card.
 *
 *   - Returns `additional_context` on the first eligible adjudication of the
 *     session (gate claimed atomically via the shared O_EXCL helper).
 *   - The gate is claimed only AFTER a match AND after whole-file suppression
 *     has been ruled out, so neither an unrelated edit nor a marker-bearing
 *     doctrine file can burn it.
 *   - Never denies, never asks, never blocks: a guard that rules out on
 *     suspicion would be the very error this doctrine exists to stop.
 *
 * Fail-open: one linear scan of the edited fragment, at most one file read
 * (only on a match), and a sub-millisecond gate-claim, so it resolves far
 * inside its registry timeout and any throw collapses to `noop`.
 */
export async function classifyTemporalLeakageAdjudicationVerdictLanguageOncePerSessionForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = (input.tool_input?.file_path as string) || "";
    if (!isLeakageTaxonomyReminderEligibleTarget(input.tool_name, filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const match = detectTemporalLeakageAdjudicationVerdictLanguage(input);
    if (match === null) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (isLeakTaxonomySuppressedByWholeFilePostEditMarker(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const rawSessionId = input.session_id || process.env.CLAUDE_SESSION_ID || String(process.ppid);
    if (
      !tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(
        LEAKAGE_TAXONOMY_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE,
        sanitizeSessionIdentifierForGateFilePathComponent(rawSessionId),
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    return buildPostToolUseAdditionalContextDecision(
      LEAKAGE_TAXONOMY_ADJUDICATION_STATIC_REMINDER_MESSAGE,
    );
  } catch (err: unknown) {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

/**
 * Symmetric-naming alias matching the sibling subhooks (ty, tsc, oxlint, biome,
 * vale, ssot-principles, memory-efficiency, markdown-hard-wrap). The precise
 * algorithm-encoding name above captures the two-tier-two-term-proximity +
 * once-per-session nature; this alias is what the orchestrator imports.
 */
export const classifyLeakageTaxonomyForPostToolUseOrchestrator =
  classifyTemporalLeakageAdjudicationVerdictLanguageOncePerSessionForPostToolUseOrchestrator;

// ── Standalone CLI (kept runnable like every sibling subhook) ────────────────

async function main(): Promise<never> {
  try {
    const stdin = await Bun.stdin.text();
    if (stdin.trim()) {
      const input = JSON.parse(stdin) as PostToolUseInput;
      const decision = await classifyLeakageTaxonomyForPostToolUseOrchestrator(input);
      if (decision.kind === "additional_context") {
        console.log(JSON.stringify({ decision: "block", reason: decision.message }));
      }
    }
  } catch (err: unknown) {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  }
  return process.exit(0);
}

if (import.meta.main) {
  void main();
}
