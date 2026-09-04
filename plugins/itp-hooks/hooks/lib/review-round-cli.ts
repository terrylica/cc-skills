#!/usr/bin/env bun
/**
 * Producer for the review-round gate.
 *
 *   bun review-round-cli.ts record --file 'path=verdict' [--file 'path=verdict' …]
 *   bun review-round-cli.ts status
 *
 * The gate never writes an artifact itself. That separation is the point: recording a pass is an
 * act the operator performs deliberately, at a moment when they have actually looked at the diff.
 * The SHAs and the diff hash are computed HERE rather than accepted as arguments, so an artifact
 * cannot claim a commit it was not written against.
 */

import {
  MIN_VERDICT_CHARS,
  sha256,
  validateArtifact,
  type ReviewRoundArtifact,
} from "./review-round-artifact.ts";
import { collectFacts, identifyRepo, writeArtifact } from "./review-round-state.ts";

function fail(message: string): never {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function parseFiles(argv: string[]): { path: string; verdict: string }[] {
  const files: { path: string; verdict: string }[] = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] !== "--file") continue;
    const spec = argv[i + 1];
    if (spec === undefined) fail("--file needs a 'path=verdict' argument");
    const eq = spec.indexOf("=");
    if (eq <= 0) fail(`--file expects 'path=verdict', got: ${spec}`);
    files.push({ path: spec.slice(0, eq).trim(), verdict: spec.slice(eq + 1).trim() });
  }
  return files;
}

function main(): void {
  const argv = process.argv.slice(2);
  const sub = argv[0];
  const cwd = process.cwd();

  const repo = identifyRepo(cwd);
  if (repo === null) fail("not inside a git repository with a named branch");

  const facts = collectFacts(cwd);
  if (facts === null) fail("could not resolve a base branch (tried origin/main, origin/master, main, master)");

  if (sub === "status") {
    process.stdout.write(
      [
        `repo    ${repo.slug}`,
        `branch  ${repo.branch}`,
        `head    ${facts.headSha.slice(0, 12)}`,
        `base    ${facts.baseSha.slice(0, 12)}`,
        `files   ${facts.changedPaths.length} changed since base`,
        ...facts.changedPaths.map((p) => `        ${p}`),
      ].join("\n") + "\n",
    );
    return;
  }

  if (sub !== "record") fail("usage: review-round-cli.ts record --file 'path=verdict' … | status");

  const files = parseFiles(argv);
  if (files.length === 0) {
    fail(
      [
        "record needs at least one --file 'path=verdict'.",
        "",
        "Changed files needing a verdict:",
        ...facts.changedPaths.map((p) => `  ${p}`),
      ].join("\n"),
    );
  }

  const artifact: ReviewRoundArtifact = {
    schema: 1,
    head_sha: facts.headSha,
    base_sha: facts.baseSha,
    diff_sha256: sha256(facts.diffText),
    recorded_at: new Date().toISOString(),
    files,
  };

  // Validate BEFORE writing. Writing an artifact the gate will reject teaches the operator that
  // the producer and the gate disagree, which is how a tool stops being trusted.
  const verdict = validateArtifact(artifact, facts);
  if (!verdict.ok) {
    fail(
      [
        "This record would not satisfy the gate:",
        ...verdict.failures.map((f) => `  - ${f}`),
        "",
        `Every changed file needs its own verdict of at least ${MIN_VERDICT_CHARS} characters,`,
        "and no two verdicts may be identical.",
      ].join("\n"),
    );
  }

  const path = writeArtifact(repo, artifact);
  process.stdout.write(
    `recorded ${files.length} verdict(s) at ${facts.headSha.slice(0, 12)}\n  ${path}\n`,
  );
}

main();
