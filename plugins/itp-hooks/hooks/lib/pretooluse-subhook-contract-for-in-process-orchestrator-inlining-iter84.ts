/**
 * PreToolUse Subhook Contract — iter-84 in-process orchestrator inlining
 *
 * Defines the pure-function contract that every subhook MUST satisfy to be
 * registered in `pretooluse-edit-time-orchestrator-combining-multiple-subhooks-into-single-bun-process-iter66-precedent.ts`.
 *
 * Why this contract exists (motivation distinct from iter-66):
 *
 *   The iter-66 stop-orchestrator subprocess-spawns each subhook. That works
 *   for Stop hooks where the savings come from collapsing N independent
 *   hook-table entries into a single Claude-Code-visible entry. But for
 *   PreToolUse Write|Edit, every subhook is itself a `bun <script>` invocation
 *   and bun cold-start is the floor (~44ms measured iter-80). Subprocess-
 *   spawning subhooks from within an orchestrator would still pay 1 bun
 *   cold-start per subhook → zero savings.
 *
 *   To actually realize the cold-start savings on PreToolUse, the orchestrator
 *   must INLINE subhook logic as imported async functions running inside the
 *   single bun process. This contract makes inlining safe by enforcing:
 *
 *     1. Pure function — no stdin read, no stdout write, no process.exit.
 *        The orchestrator owns I/O; subhooks return a decision object.
 *
 *     2. Bounded time — every classifier MUST resolve within `timeoutMs` or
 *        the orchestrator times it out via Promise.race and treats it as
 *        fail-open (allow). Prevents one hung subhook from blocking the rest.
 *
 *     3. No throw — every classifier MUST catch its own errors and convert
 *        them to a fail-open SubhookDecision. The orchestrator additionally
 *        wraps each call in try/catch as belt-and-suspenders, but classifiers
 *        that propagate errors will degrade the orchestrator's allow-rate.
 *
 *     4. Side-effect-free for `allow` — subhooks that produce no decision
 *        change MUST NOT mutate caches, write files, or call subprocesses
 *        during the orchestrator path. Side-effects belong in PostToolUse,
 *        not PreToolUse.
 */

import type { PreToolUseInput } from "../pretooluse-helpers.ts";

/**
 * A subhook's classification verdict on the proposed tool call.
 *
 * - `allow` — subhook has no objection. Orchestrator continues iterating
 *   the registry; if every subhook returns `allow`, the orchestrator emits
 *   a single `allow` decision to Claude Code.
 * - `deny`  — subhook objects. Orchestrator short-circuits the registry,
 *   emits a `deny` decision (with belt-and-suspenders stderr + exit 2
 *   per GitHub #37210 / iter-78), and never calls remaining subhooks.
 * - `ask`   — subhook wants the user to confirm. Same short-circuit as
 *   `deny` but emits `ask` to Claude Code.
 */
export type PreToolUseSubhookDecisionKind = "allow" | "deny" | "ask";

export interface PreToolUseSubhookDecision {
  kind: PreToolUseSubhookDecisionKind;
  /** Human-readable explanation (required for `deny`/`ask`, ignored for `allow`). */
  reason?: string;
}

/**
 * The pure classifier function that every subhook exports.
 *
 * Contract:
 *   - Receives the orchestrator-parsed PreToolUseInput verbatim
 *   - Returns a Promise<PreToolUseSubhookDecision>
 *   - MUST NOT touch stdin/stdout/process.exit (orchestrator owns I/O)
 *   - MUST resolve within the registry-declared timeoutMs (orchestrator
 *     enforces via Promise.race; runaway classifiers fail-open to `allow`)
 *   - MUST internally catch errors and return a fail-open `allow`
 *     decision; classifiers that throw will be treated as `allow` by the
 *     orchestrator's outer try/catch but should not rely on it
 */
export type PreToolUseSubhookClassifierFunction = (
  input: PreToolUseInput,
) => Promise<PreToolUseSubhookDecision>;

/**
 * A registry entry combining the classifier with metadata that the
 * orchestrator needs to enforce the contract.
 */
export interface PreToolUseSubhookRegistryEntry {
  /** Stable identifier used in stderr diagnostics and metrics. */
  name: string;
  /**
   * Per-subhook timeout in milliseconds. If the classifier doesn't resolve
   * within this window the orchestrator emits a stderr warning and treats
   * the result as fail-open `allow`.
   */
  timeoutMs: number;
  /** The actual classifier function. */
  classify: PreToolUseSubhookClassifierFunction;
  /**
   * Optional short prose explaining what this subhook checks for. Used
   * only in operator-visible orchestrator diagnostics.
   */
  description?: string;
}

/**
 * Helper: an allow decision (orchestrator emits one of these per
 * non-objecting subhook).
 */
export const ALLOW_DECISION: PreToolUseSubhookDecision = { kind: "allow" };

/**
 * Helper: build a deny decision with reason text.
 */
export function denyDecision(reason: string): PreToolUseSubhookDecision {
  return { kind: "deny", reason };
}

/**
 * Helper: build an ask decision with reason text.
 */
export function askDecision(reason: string): PreToolUseSubhookDecision {
  return { kind: "ask", reason };
}

// ────────────────────────────────────────────────────────────────────────
//  Iter-102: canonical file-edit tool-name allow-set for PreToolUse
//  blocking subhooks (mirrors iter-100's PostToolUse-side helper hoist)
// ────────────────────────────────────────────────────────────────────────
//
// Pre-iter-102 each of the 8 inlined PreToolUse classifiers (file-size-
// guard, vale-claude-md-guard, version-guard, hoisted-deps-guard, mise-
// hygiene-guard, pyi-stub-guard, native-binary-guard, gpu-optimization-
// guard) had its own hardcoded `tool_name !== "Write" && tool_name !==
// "Edit"` guard. After iter-101 broadened the orchestrator matcher to
// `Write|Edit|MultiEdit`, the orchestrator now routes MultiEdit payloads
// to every classifier — but the classifiers self-skip because their
// hardcoded guards exclude MultiEdit. Net behavior: silent no-op on
// MultiEdit (the iter-101 documented residual gap).
//
// Iter-102 closes this residual gap with the same canonical-helper
// pattern iter-100 established for PostToolUse:
//
//   1. ONE constant `FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_
//      BLOCKING_SUBHOOKS` defines the file-edit tool allow-set
//   2. ONE helper `isFileEditToolNameHonoredByPreToolUseBlockingSubhook`
//      provides the predicate
//   3. All 8 classifiers replace their hardcoded guard with one call to
//      the helper — future Anthropic tool-name additions (e.g.,
//      NotebookEdit which the iter-102 web research surfaced — see
//      HOOKS.md iter-102 section + iter-103 follow-up scope) update ONE
//      constant, not 8 classifier files
//
// Naming: encodes the actual semantic (file-edit tool names honored by
// PreToolUse blocking subhooks) per the self-explanatory scaffolding
// directive. Mirrors the PostToolUse-side
// FILE_EDIT_TOOL_NAMES_HONORED_BY_POSTTOOLUSE_CONTEXT_INJECTING_SUBHOOKS
// constant name, with the "blocking" qualifier distinguishing the
// PreToolUse intent (deny/ask) from the PostToolUse intent (additional
// context injection).
//
// MultiEdit acceptance rationale: file-edit-content guards (size,
// terminology, init-monolith, version-pin, GPU, hoisting, hygiene,
// launchd-native-binary) all operate on file_path + content, both of
// which are present in MultiEdit payloads (tool_input.file_path +
// tool_input.edits[].new_string concatenated). Classifiers that need
// per-edit content adaptation (currently NONE in the 8 inlined cohort —
// they're all file-path-based or full-file-content-based) would need
// downstream payload-shape handling, separate from the tool-name guard.
//
// NotebookEdit NON-acceptance rationale: NotebookEdit has a different
// payload shape (tool_input.notebook_path, cell_id, edit_mode, source)
// and operates on .ipynb files. Adding NotebookEdit support requires
// per-classifier per-payload-shape adaptation (not just tool-name
// expansion). Punted to iter-103+ scope per HOOKS.md.

export const FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS:
  ReadonlySet<string> = new Set(["Write", "Edit", "MultiEdit"]);

/**
 * Iter-102 canonical guard predicate for PreToolUse blocking subhooks.
 *
 * Returns true iff the given tool_name is in the file-edit tool allow-set
 * honored by the 8 inlined PreToolUse classifiers. Replaces the pre-iter-
 * 102 hardcoded `tool_name !== "Write" && tool_name !== "Edit"` pattern
 * scattered across all 8 classifier files.
 *
 * Closes the iter-101 documented residual gap (MultiEdit silent-skip at
 * the classifier level after the matcher was broadened at the hooks.json
 * level).
 */
export function isFileEditToolNameHonoredByPreToolUseBlockingSubhook(
  toolName: string | undefined,
): boolean {
  if (!toolName) return false;
  return FILE_EDIT_TOOL_NAMES_HONORED_BY_PRETOOLUSE_BLOCKING_SUBHOOKS.has(toolName);
}
