/**
 * PostToolUse Subhook Contract — iter-93 in-process orchestrator inlining
 *
 * Defines the pure-function contract that every PostToolUse subhook MUST
 * satisfy to be registered in the iter-93 PostToolUse orchestrator
 * (`posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts`).
 *
 * Why a SEPARATE contract from iter-84's PreToolUseSubhookContract
 * (motivation distinct from the PreToolUse design):
 *
 *   The PreToolUse contract has FIRST-DENY-SHORT-CIRCUIT semantics: any
 *   subhook returning `deny`/`ask` causes the orchestrator to skip all
 *   remaining subhooks and emit a single `deny`/`ask` decision. That works
 *   because Claude Code's PreToolUse schema honors `permissionDecision`.
 *
 *   The PostToolUse schema CANNOT deny (per iter-66 forensic finding +
 *   Anthropic official docs). The only Claude-visible context-injection
 *   surface is `{decision: "block", reason}` JSON which Claude renders as a
 *   system reminder next-to-tool-result (synchronous timing required — see
 *   iter-92 audit). That means PostToolUse subhooks have a fundamentally
 *   different aggregation contract:
 *
 *     - Each subhook produces EITHER a no-op (no context to inject) OR an
 *       `additional_context` payload (a string to be folded into the
 *       aggregated reason)
 *     - The orchestrator runs ALL subhooks (no short-circuit) and merges
 *       every non-empty `additional_context` payload into one consolidated
 *       `{decision: "block", reason: aggregate}` emission
 *     - If every subhook returns `noop`, the orchestrator emits NOTHING
 *       (silent allow — same as legacy synchronous PostToolUse with clean
 *       result)
 *
 *   Iter-93 also preserves the iter-84 invariants that made PreToolUse
 *   inlining safe (pure function discipline, AbortSignal.timeout()
 *   cooperative cancellation, try/catch crash isolation, fail-open on
 *   error/timeout).
 *
 * Why the strict-dominance claim from iter-89 was WRONG (iter-92 correction):
 *
 *   Iter-89 claimed `async: true` was strict-dominant over orchestrator
 *   inlining for PostToolUse because the schema cannot deny. Iter-92 web
 *   research (claudefa.st March-2026 + Anthropic timing docs) revealed
 *   that async PostToolUse hooks cannot reliably inject context next-to-
 *   tool-result — the model advances before the hook finishes. The iter-92
 *   eligibility audit (`audit-posttooluse-asynctrue-eligibility-classifier-by-decision-block-vs-pure-side-effect-output-pattern-iter92-corrects-iter89-strict-dominance-claim.sh`)
 *   classified 15 of 17 marketplace PostToolUse hooks as
 *   `[C] CONTEXT-INJECTING / ASYNC-UNSAFE`, leaving orchestrator inlining
 *   (Path B) as the only viable consolidation strategy for the
 *   context-injecting cohort. This contract makes that strategy safe.
 */

/**
 * The PostToolUse hook input shape that subhooks receive verbatim from the
 * orchestrator. Mirrors the documented Anthropic PostToolUse JSON.
 *
 * Notable difference from PreToolUseInput: PostToolUse fires AFTER the tool
 * executes, so `tool_response` carries the tool's result (file written,
 * command stdout, etc.). Subhooks classify based on the
 * already-applied-to-disk state, not the proposed-edit-shape.
 */
export interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    command?: string;
    file_path?: string;
    content?: string;
    old_string?: string;
    new_string?: string;
    [key: string]: unknown;
  };
  /**
   * The tool's result payload. Shape depends on the tool — for Write/Edit it
   * typically includes `success` / `filePath`; for Bash it includes
   * `stdout`/`stderr`/`exit_code`. Subhooks that need this field cast it.
   */
  tool_response?: Record<string, unknown>;
  tool_use_id?: string;
  cwd?: string;
  session_id?: string;
  transcript_path?: string;
  hook_event_name?: string;
}

/**
 * A PostToolUse subhook's classification verdict on the just-applied tool
 * call.
 *
 * - `noop` — subhook has no context to inject. Orchestrator silently skips
 *   this subhook's contribution to the aggregated reason. If EVERY subhook
 *   returns `noop`, the orchestrator emits NOTHING (legacy silent-allow
 *   semantics preserved).
 *
 * - `additional_context` — subhook wants Claude to see `message` as a
 *   system-reminder. Orchestrator collects all non-empty messages from the
 *   registry and emits ONE consolidated
 *   `{decision: "block", reason: aggregate}` JSON. The aggregate is
 *   delimiter-joined so Claude sees each subhook's contribution as a
 *   labeled section.
 *
 *   IMPORTANT: this does NOT block the tool from running — the tool has
 *   ALREADY run by the time PostToolUse fires. The `decision: "block"`
 *   keyword is the documented Anthropic-schema mechanism for PostToolUse
 *   context-injection — it surfaces the reason as a Claude-visible system
 *   reminder, NOT a rejection. (Per iter-66 forensic finding +
 *   docs/HOOKS.md PostToolUse section.)
 */
export type PostToolUseSubhookDecisionKind = "noop" | "additional_context";

export type PostToolUseSubhookDecision =
  | { kind: "noop" }
  | { kind: "additional_context"; message: string };

/**
 * Iter-96 helper: build a TIMEOUT-AWARE additional_context decision so Claude
 * sees that a subhook was ATTEMPTED-BUT-ABORTED (cooperative timeout fired
 * before the subprocess could complete), not silently-passed. Default behavior
 * in iter-93/94/95 was to fail-open with `noop` on timeout — that's a silent
 * false-negative: Claude assumes the type-check/lint passed. Per Anthropic's
 * 2026 operator-visibility best practice, `additionalContext` is the
 * documented surface for diagnostic information that Claude should see.
 *
 * The orchestrator wires this in
 * `executeSinglePostToolUseSubhookWithCooperativeAbortSignalTimeoutAndCrashIsolation`
 * — when the timeout fires, instead of returning `noop`, it returns this
 * subhook-self-describing additional_context with a tightly-scoped message.
 * The aggregator then folds the timeout-section in with any other contributing
 * sections (and applies the iter-95 conditional provenance prefix).
 *
 * Iter-96 invariant: the timeout message MUST be operator-actionable. It
 * MUST tell Claude what was attempted (subhook name + tool), why it didn't
 * complete (timed out — not crashed), and the suggested next step
 * (manually verify) — in ≤200 chars so the aggregate reason doesn't blow up.
 */
export function buildPostToolUseTimeoutAwareAdditionalContextDecisionForOperatorVisibility(
  subhookName: string,
  timeoutMs: number,
): PostToolUseSubhookDecision {
  return {
    kind: "additional_context",
    message: `[${subhookName}] timed out after ${timeoutMs}ms — check was attempted but aborted before completion. Manually verify by running the standalone hook (bun plugins/itp-hooks/hooks/posttooluse-${subhookName}.ts) if this file looks risky.`,
  };
}

/**
 * The pure classifier function that every PostToolUse subhook exports.
 *
 * Contract:
 *   - Receives the orchestrator-parsed PostToolUseInput verbatim
 *   - Returns a Promise<PostToolUseSubhookDecision>
 *   - MUST NOT touch stdin/stdout/process.exit (orchestrator owns I/O)
 *   - MUST resolve within the registry-declared timeoutMs (orchestrator
 *     enforces via AbortSignal.timeout() race; runaway classifiers
 *     fail-open to `noop`)
 *   - MUST internally catch errors and return a fail-open `noop` decision;
 *     classifiers that throw will be treated as `noop` by the orchestrator's
 *     outer try/catch but should not rely on it
 *   - MAY perform read-only filesystem operations (e.g., reading the
 *     just-written file from disk for static analysis) — PostToolUse fires
 *     after the tool's side effects are durable. Distinguishes from the
 *     PreToolUse contract which forbids file I/O on `allow` paths.
 *   - MUST NOT mutate filesystem state for any purpose unrelated to the
 *     hook's documented PostToolUse responsibility (e.g., writing gate
 *     files for inter-hook coordination is allowed; writing arbitrary
 *     output files is not).
 */
export type PostToolUseSubhookClassifierFunction = (
  input: PostToolUseInput,
) => Promise<PostToolUseSubhookDecision>;

/**
 * A PostToolUse registry entry combining the classifier with metadata that
 * the orchestrator needs to enforce the contract.
 */
export interface PostToolUseSubhookRegistryEntry {
  /** Stable identifier used in stderr diagnostics and aggregation labels. */
  name: string;
  /**
   * Per-subhook timeout in milliseconds. If the classifier doesn't resolve
   * within this window the orchestrator emits a stderr warning and treats
   * the result as fail-open `noop`. PostToolUse subhooks are typically
   * SLOWER than PreToolUse ones (they may spawn subprocess type-checkers,
   * linters, etc.) so registry entries often use generous budgets
   * (4000-8000ms typical).
   */
  timeoutMs: number;
  /** The actual classifier function. */
  classify: PostToolUseSubhookClassifierFunction;
  /**
   * Optional short prose explaining what this subhook checks for. Used
   * only in operator-visible orchestrator diagnostics.
   */
  description?: string;
}

/**
 * Helper: a no-op decision (orchestrator emits nothing for these).
 */
export const POSTTOOLUSE_SUBHOOK_NOOP_DECISION: PostToolUseSubhookDecision = {
  kind: "noop",
};

/**
 * Helper: build an additional-context decision with a message that the
 * orchestrator will fold into the aggregated reason.
 */
export function buildPostToolUseAdditionalContextDecision(
  message: string,
): PostToolUseSubhookDecision {
  return { kind: "additional_context", message };
}

/**
 * The set of tool names a file-edit-context-injecting subhook MUST treat as
 * "this is a file-mutation tool whose effects I should classify". Iter-100
 * expansion: previously only `Write` + `Edit` were honored by inlined
 * classifiers' early-exit guards. The 2026 Anthropic best-practice (per
 * the `Write|Edit|MultiEdit` recommended matcher in the official hook docs
 * + community guides) is to ALSO honor `MultiEdit` — Claude uses MultiEdit
 * when applying multiple Edits to one file in a single tool call, and a
 * file-classifier missing MultiEdit silently skips entire classes of edits.
 *
 * Centralized here so future expansions (e.g., new file-mutation tools
 * introduced by Anthropic) only require updating ONE set, not N classifier
 * files — eliminates drift between the orchestrator's hooks.json matcher
 * string and each classifier's tool-name early-exit guard.
 */
export const FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS: ReadonlySet<string> =
  new Set(["Write", "Edit", "MultiEdit"]);

/**
 * Helper: returns true if the tool_name in a PostToolUse input is one of
 * the file-edit tools a context-injecting subhook should classify. Use this
 * in classifier early-exit guards instead of hand-rolling the equality
 * check so the allow-set stays canonical.
 */
export function isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(
  toolName: string | undefined,
): boolean {
  if (!toolName) return false;
  return FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS.has(toolName);
}

// ────────────────────────────────────────────────────────────────────────
//  Iter-104 / Iter-105 / Iter-106: Hook-output size cap helpers
// ────────────────────────────────────────────────────────────────────────
//
// Iter-104 originally hosted the canonical truncation helper here because
// the first adopter (posttooluse-vale-claude-md.ts) was a PostToolUse
// classifier. Iter-105 scaled the helper marketplace-wide to 8 cohort hooks
// including one PreToolUse classifier (pretooluse-vale-claude-md-guard.ts),
// creating an awkward cross-lib import pattern.
//
// Iter-106 RELOCATES the canonical home of these 3 exports to a dedicated
// cross-Pre/PostToolUse shared lib:
//
//   ./shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts
//
// The transitive re-exports below preserve the iter-104 PostToolUse-contract-
// lib API surface so existing audit tasks, regression tests, documentation,
// and any external consumers continue to work without modification. Direct
// imports from the new shared-lib location are preferred for new code.

export {
  MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER,
  HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_FOR_CLAUDE_VISIBLE_AWARENESS_OF_CONTEXT_LOSS,
  truncateHookOutputToStayBelowClaudeFileSpilloverThreshold,
} from "./shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";
