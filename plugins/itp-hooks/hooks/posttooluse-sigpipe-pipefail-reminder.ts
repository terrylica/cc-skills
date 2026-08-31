#!/usr/bin/env bun
/**
 * PostToolUse hook: SIGPIPE-under-pipefail reminder (soft nudge).
 *
 * Fires when a Write/Edit introduces a pipeline into an EARLY-EXITING READER
 * inside a shell script that enables `pipefail`. The reader closes the pipe, the
 * producer dies of SIGPIPE with status 141, and under `pipefail` the PIPELINE
 * takes the producer's status — so a pipeline whose reader succeeded reports
 * failure.
 *
 * WHY THIS IS WORTH A HOOK RATHER THAN A LINT RULE. The harm is usually not a
 * crash. Measured instance: a pre-push hook ran
 * `moon query tasks | grep -q '"check-all-gates"'` to decide whether a task
 * existed. grep FOUND it, exited, killed the producer, and the `if` condition
 * evaluated FALSE — so the hook reported that 40 gates had no runner while the
 * same command ran fine by hand. Nothing crashed and nothing logged; the boolean
 * simply inverted. It is also a RACE: if the producer finishes writing before
 * the reader exits there is no SIGPIPE at all, which is why this class passes in
 * testing and begins failing later as the data grows. That instance cost three
 * `git push --no-verify` bypasses in one day, each disabling 40 gates at once.
 *
 * WHY IT NUDGES AND NEVER BLOCKS. A whole-tree census of the source repository
 * found 60 sites across 26 of 119 pipefail scripts. Most are harmless — the
 * status is discarded, or the producer is small enough to always win the race.
 * A hook that denied on this shape would fire constantly on ordinary code, and
 * the documented consequence of an over-eager gate here is a bypass that
 * disables every OTHER gate with it. So this emits a reminder and gets out of
 * the way. Judgement stays with the author; the hook only ensures the question
 * was asked.
 *
 * Channel: PostToolUse `{decision:"block", reason}` — the Claude-visible channel
 * per ADR 2025-12-17. `block` does NOT undo the completed tool; it surfaces
 * `reason` as a system reminder. This hook NEVER blocks real work.
 *
 * NET-NEW ONLY. For Edit/MultiEdit, the site count in `new_string` must exceed
 * the count in `old_string`, so touching a line near a pre-existing site does
 * not fire. For Write, the whole content is scanned — a new file is entirely
 * net-new, and an overwrite of an existing file is a rewrite of its content.
 *
 * Escape hatch: `SIGPIPE-OK: <reason>` on any line of the pipeline, or the
 * file-wide `SHELL-SAFETY-OK` honoured by the sibling shell-safety detector.
 *
 * Detector + its fidelity evidence: lib/sigpipe-under-pipefail-detector-iter125.ts
 */

import { trackHookError } from "./pretooluse-helpers.ts";
import {
  detectSigpipeUnderPipefailSites,
  type SigpipeSite,
} from "./lib/sigpipe-under-pipefail-detector-iter125.ts";

interface HookInput {
  tool_name: string;
  tool_input?: {
    file_path?: string;
    content?: string;
    old_string?: string;
    new_string?: string;
    edits?: { old_string?: string; new_string?: string }[];
  };
}

/**
 * Sites introduced by this edit, or [] when the edit did not add any.
 *
 * The old/new comparison is by COUNT rather than by identity: an Edit that
 * rewrites a line containing a site should not fire, and an Edit that adds one
 * should. Comparing counts is what makes "moved a pre-existing pipeline" quiet.
 */
export function detectNetNewSigpipeSites(input: HookInput): SigpipeSite[] {
  const filePath = input.tool_input?.file_path;
  if (!filePath) return [];

  const scan = (text: string | undefined): SigpipeSite[] =>
    text ? detectSigpipeUnderPipefailSites(filePath, text) : [];

  if (input.tool_name === "Write") {
    return scan(input.tool_input?.content);
  }

  if (input.tool_name === "Edit") {
    // A fragment has no shebang and usually no `set -o pipefail`, so it is
    // scanned WITH a synthetic preamble when the path already identifies the
    // file as a shell script. Without this every Edit fragment would be
    // invisible to a detector that is (correctly) gated on pipefail.
    const before = scanFragment(filePath, input.tool_input?.old_string);
    const after = scanFragment(filePath, input.tool_input?.new_string);
    return after.length > before.length ? after.slice(before.length) : [];
  }

  if (input.tool_name === "MultiEdit") {
    const out: SigpipeSite[] = [];
    for (const edit of input.tool_input?.edits ?? []) {
      const before = scanFragment(filePath, edit.old_string);
      const after = scanFragment(filePath, edit.new_string);
      if (after.length > before.length) out.push(...after.slice(before.length));
    }
    return out;
  }

  return [];
}

/**
 * `pipefail` is a property of the FILE, not of the fragment being edited, so an
 * Edit fragment is scanned under a synthetic preamble that supplies it. The
 * fragment's own `SIGPIPE-OK` markers still apply because they are read from
 * the scanned text.
 */
const SYNTHETIC_PIPEFAIL_PREAMBLE = "#!/usr/bin/env bash\nset -euo pipefail\n";

function scanFragment(filePath: string, fragment: string | undefined): SigpipeSite[] {
  if (!fragment) return [];
  if (!/\.(sh|bash|zsh)$/.test(filePath) && !filePath.includes("git-hooks/")) return [];
  return detectSigpipeUnderPipefailSites(filePath, SYNTHETIC_PIPEFAIL_PREAMBLE + fragment);
}

export function buildReminder(sites: SigpipeSite[]): string {
  const first = sites[0] as SigpipeSite;
  const more = sites.length > 1 ? ` (+${sites.length - 1} more in this edit)` : "";
  return [
    `[SIGPIPE-PIPEFAIL] A pipeline pipes into an early-exiting reader under \`pipefail\`${more}:`,
    `  ${first.producer} | ${first.reader}`,
    "",
    "The reader closes the pipe, the producer is killed by SIGPIPE and exits 141, and",
    "`pipefail` makes the PIPELINE take that status. Two silent harm modes:",
    "  (A) under `set -e` the script aborts mid-run with 141 and no error line;",
    "  (B) in an `if`/`while` condition the boolean INVERTS — the reader succeeded,",
    "      the pipeline reports failure. Measured: `moon query tasks | grep -q X`",
    "      found X and still evaluated FALSE.",
    "It is a RACE, so it passes in testing and starts failing as the data grows.",
    "",
    "Fixes, cheapest first:",
    "  1. Use a reader that DRAINS: `awk 'NR<=5'` instead of `head -5`; drop `-q`",
    "     from grep and test its output; `tail`, `sort`, `wc` are already safe.",
    "  2. Remove the pipe: capture once (`out=$(producer)`) then match on `$out`,",
    "     or use a `case` on the captured text — no reader, no race.",
    "  3. Scope the disable: `x=$( set +o pipefail; producer | head -1 )`.",
    "  4. If the status genuinely does not matter, say so: `SIGPIPE-OK: <reason>`.",
  ].join("\n");
}

async function main(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText) as HookInput;
  } catch {
    process.exit(0); // invalid JSON → fail-open
  }

  if (!["Write", "Edit", "MultiEdit"].includes(input.tool_name)) process.exit(0);

  const sites = detectNetNewSigpipeSites(input);
  if (sites.length > 0) {
    console.log(JSON.stringify({ decision: "block", reason: buildReminder(sites) }));
  }
  process.exit(0);
}

if (import.meta.main) {
  main().catch((err) => {
    trackHookError(
      "posttooluse-sigpipe-pipefail-reminder",
      err instanceof Error ? err.message : String(err),
    );
    process.exit(0);
  });
}
