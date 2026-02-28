#!/usr/bin/env bun
/**
 * Stop hook: GitNexus reindex reminder
 *
 * At session end, checks if any git repo in the CWD has a stale GitNexus
 * index. Outputs additionalContext if stale, empty JSON otherwise.
 *
 * Fail-open everywhere — every catch outputs {}.
 */

import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";

const COMMIT_THRESHOLD = 5;

function main(): void {
  // Find git root from CWD
  let gitRoot: string;
  try {
    gitRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    console.log(JSON.stringify({}));
    return;
  }

  // Check .gitnexus/meta.json exists
  const metaPath = join(gitRoot, ".gitnexus", "meta.json");
  if (!existsSync(metaPath)) {
    console.log(JSON.stringify({}));
    return;
  }

  // Read meta.json → get lastCommit
  let lastCommit: string;
  try {
    const meta = JSON.parse(readFileSync(metaPath, "utf-8"));
    lastCommit = meta.lastCommit;
    if (!lastCommit) {
      console.log(JSON.stringify({}));
      return;
    }
  } catch {
    console.log(JSON.stringify({}));
    return;
  }

  // Compare with current HEAD
  let headCommit: string;
  try {
    headCommit = execSync("git rev-parse HEAD", {
      cwd: gitRoot,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    console.log(JSON.stringify({}));
    return;
  }

  if (lastCommit === headCommit) {
    console.log(JSON.stringify({}));
    return;
  }

  // Count commits behind
  let commitsBehind: number;
  try {
    const count = execSync(`git rev-list --count ${lastCommit}..HEAD`, {
      cwd: gitRoot,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    commitsBehind = parseInt(count, 10);
  } catch {
    console.log(JSON.stringify({}));
    return;
  }

  if (commitsBehind < COMMIT_THRESHOLD) {
    console.log(JSON.stringify({}));
    return;
  }

  const repoName = gitRoot.split("/").pop();
  console.log(
    JSON.stringify({
      additionalContext: `[GITNEXUS] ${repoName}: Index is ${commitsBehind} commits behind. Run \`npx gitnexus@latest analyze\` or /gitnexus-tools:reindex to refresh the knowledge graph.`,
    })
  );
}

try {
  main();
} catch {
  console.log(JSON.stringify({}));
}
