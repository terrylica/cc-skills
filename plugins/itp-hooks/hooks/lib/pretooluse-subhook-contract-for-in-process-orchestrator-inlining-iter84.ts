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
