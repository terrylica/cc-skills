#!/usr/bin/env bun
/**
 * Tier 2: the standing status line for the review-round gate.
 *
 * WHY THIS EVENT AND NOT PreToolUse. PreToolUse stdout goes to the debug log and is NOT shown to
 * the model, and for the Bash matcher every context-injection channel is dropped. So a gate cannot
 * make itself visible at the moment of the command it gates. `UserPromptSubmit` is one of the few
 * events whose plain stdout IS added to context, and it fires once per turn rather than once per
 * Bash call -- so this costs nothing on the hundreds of commands it has no opinion about.
 *
 * FACTS ONLY, PHRASED AS STATEMENTS. Imperative text injected into context reads as an instruction
 * and gets surfaced to the user by the prompt-injection defences instead of acted on. Everything
 * below is a measurement or a state reading.
 *
 * Nothing here blocks, and nothing here calls the network.
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { validateArtifact } from "./lib/review-round-artifact.ts";
import {
  STATE_ROOT,
  collectFacts,
  identifyRepo,
  isBranchReviewable,
  readArtifact,
} from "./lib/review-round-state.ts";

function overrideCountToday(): number {
  const path = join(STATE_ROOT, "overrides.jsonl");
  if (!existsSync(path)) return 0;
  try {
    const today = new Date().toISOString().slice(0, 10);
    return readFileSync(path, "utf8")
      .split("\n")
      .filter((line) => line.includes(`"at":"${today}`)).length;
  } catch {
    return 0;
  }
}

function main(): void {
  // stdin is consumed but unused: this hook needs no input beyond cwd, and reading it keeps the
  // contract identical to sibling hooks.
  try {
    readFileSync(0, "utf8");
  } catch {
    // no stdin is fine
  }

  const cwd = process.cwd();
  const repo = identifyRepo(cwd);
  if (repo === null) return; // not a git repo — nothing to say, say nothing

  const facts = collectFacts(cwd);
  if (facts === null) return;

  const artifact = readArtifact(repo);
  const verdict = validateArtifact(artifact, facts);
  const churn = facts.changedPaths.length;

  const lines: string[] = [`[review-round-gate] ${repo.slug} · ${repo.branch}`];

  lines.push(
    verdict.ok
      ? `  Self-review record is current for HEAD ${facts.headSha.slice(0, 8)} (${churn} file(s)).`
      : `  No current self-review record for HEAD ${facts.headSha.slice(0, 8)}; ${churn} file(s) changed since base.`,
  );

  if (isBranchReviewable(repo)) {
    lines.push("  This branch has been marked ready for review, so pushes to it are metered.");
  }

  // The measured relationship, stated once so the size decision is made before the diff is large
  // rather than after a reviewer has paid for it.
  if (churn > 0) {
    lines.push(
      "  Measured on this reviewer: PRs <=400 changed lines cost 1.36 review rounds on average; " +
        "PRs >900 lines cost 7.43.",
    );
  }

  lines.push(
    "  `gh pr update-branch` is not required where the ruleset is loose, and costs a full CI run.",
  );

  const overrides = overrideCountToday();
  if (overrides > 0) {
    lines.push(`  Gate overrides recorded today: ${overrides}.`);
  }

  process.stdout.write(`${lines.join("\n")}\n`);
}

try {
  main();
} catch {
  // A status line must never interfere with a turn. Silence is the correct failure mode here,
  // unlike the gate itself, where a failure is logged because it means a check did not run.
}
