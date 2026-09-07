#!/usr/bin/env bun
/**
 * Tests for the pre-commit staged-content credential guard.
 *
 * Every positive fixture below is SYNTHETIC. The token shapes are real — that
 * is what is being tested — but the values are invented for this file and were
 * never issued by any provider. This test file is published to a public
 * marketplace, so a real value here would commit the exact error the guard
 * exists to prevent, in the repository that owns the guard.
 *
 * The false-positive floor carries equal weight. This guard runs on EVERY
 * commit, over every staged blob, in a repo full of lockfile hashes, git SHAs
 * and documented placeholders. One bad block and the operator reaches for
 * `--no-verify` permanently — which loses the credential gate for good. A
 * blocking guard is only as valuable as its silence on ordinary work.
 *
 * The integration block at the end drives a REAL git index in a throwaway
 * repository under the OS temp directory, because the two decisions most likely
 * to be wrong are the ones no pure unit test can reach: that the guard reads
 * the staged blob rather than the working tree, and that it enumerates the
 * staged set correctly.
 *
 * SECRET-SCAN-OK: synthetic never-issued credential fixtures for this guard's own suite
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  buildStagedCredentialBlock,
  classifyEscapeHatch,
  isProbablyBinary,
  parseArguments,
  scanStagedBlobContent,
  scanStagedChanges,
} from "./staged-content-credential-guard.ts";

// ── Synthetic fixtures ────────────────────────────────────────────────────
// Invented values with the right SHAPE. None was ever issued.

/** `<8-10 digit id>:AA<32+ url-safe chars>` — the BotFather format. */
const SYNTHETIC_TELEGRAM_TOKEN = "7419283056:AAH9tRkQm3vZbN6xPwL2sD8fJ4gY7cV1uT0";
/** Bare 30-char mixed alphanumeric — the Pushover application-token shape. */
const SYNTHETIC_PUSHOVER_TOKEN = "a7k2mq9rd4xv8bn3ct6ye5zw1phs0j";
/** A ≥16-char literal for the provisioning-command detector. */
const SYNTHETIC_PROVISIONING_VALUE = "Kx7f2Qm9Rt4Wb1Zc6Yd3Nv8";

describe("escape-hatch classification", () => {
  test("a marker with a real reason excuses the file", () => {
    expect(classifyEscapeHatch("// SECRET-SCAN-OK: synthetic fixture for the suite")).toBe("valid");
  });

  test("a marker in any comment style is honored", () => {
    expect(classifyEscapeHatch("<!-- SECRET-SCAN-OK: synthetic fixture, never issued -->")).toBe(
      "valid",
    );
    expect(classifyEscapeHatch("# SECRET-SCAN-OK: revoked value quoted in a post-mortem")).toBe(
      "valid",
    );
  });

  test("a marker with an empty or too-short reason is REJECTED, not silently ignored", () => {
    // "rejected" rather than "absent" so the block message can say so: an
    // operator who believes they bypassed the guard, and did not, reaches for
    // --no-verify next.
    expect(classifyEscapeHatch("// SECRET-SCAN-OK:")).toBe("rejected");
    expect(classifyEscapeHatch("// SECRET-SCAN-OK: short")).toBe("rejected");
  });

  test("the marker without a colon is not the marker at all", () => {
    expect(classifyEscapeHatch("// SECRET-SCAN-OK")).toBe("absent");
  });

  test("a reason that is only placeholder syntax does NOT suppress", () => {
    // This is the rule that keeps a file which merely DOCUMENTS the marker from
    // exempting itself — this repo has a registry entry, a docs page and three
    // guards that all spell the marker beside an angle-bracketed <reason>.
    expect(classifyEscapeHatch("SECRET-SCAN-OK: <reason of at least 10 characters>")).toBe(
      "rejected",
    );
    expect(classifyEscapeHatch("<!-- SECRET-SCAN-OK: <reason> -->")).toBe("rejected");
  });

  test("a backtick-quoted MENTION of the marker is documentation, not a bypass", () => {
    // Without this, the sibling commit-message guard's own source — which
    // writes `SECRET-SCAN-OK:` in a doc comment — would exempt itself from
    // ever being scanned. Measured: it did, until this rule was added.
    expect(classifyEscapeHatch("True when the operator supplied `SECRET-SCAN-OK:` with a reason")).toBe(
      "absent",
    );
    expect(classifyEscapeHatch("Escape hatch: `SECRET-SCAN-OK: <reason>` (>=10 chars)")).toBe(
      "absent",
    );
  });

  test("a double-quoted marker still counts — JSON and YAML have no comments", () => {
    expect(classifyEscapeHatch('{"note": "SECRET-SCAN-OK: synthetic fixture, never live"}')).toBe(
      "valid",
    );
  });

  test("the HTML-escaped placeholder form a rendered changelog carries is rejected", () => {
    expect(classifyEscapeHatch("- SECRET-SCAN-OK: &lt;reason>, reason >=10 chars mandatory")).toBe(
      "rejected",
    );
  });

  test("a valid marker anywhere in the file wins over a documented one", () => {
    expect(
      classifyEscapeHatch(
        ["SECRET-SCAN-OK: <reason>", "SECRET-SCAN-OK: genuinely synthetic test vector"].join("\n"),
      ),
    ).toBe("valid");
  });

  test("no marker at all reads as absent", () => {
    expect(classifyEscapeHatch("const x = 1;\n")).toBe("absent");
  });
});

describe("binary sniffing", () => {
  test("a NUL in the first kilobyte marks the blob binary", () => {
    expect(isProbablyBinary(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0x1a]))).toBe(true);
  });

  test("ordinary UTF-8 text is not binary", () => {
    expect(isProbablyBinary(Buffer.from("const x = 1;\n// 你好\n", "utf8"))).toBe(false);
  });

  test("a NUL beyond the sniff window is not enough to skip the blob", () => {
    // The window is deliberately the PreToolUse credential guard's 1 KiB, so
    // both credential surfaces classify the same payload the same way.
    const blob = Buffer.concat([Buffer.alloc(2048, 0x41), Buffer.from([0x00])]);
    expect(isProbablyBinary(blob)).toBe(false);
  });
});

describe("credential detection over a staged blob", () => {
  test("BLOCKS a Telegram bot token", () => {
    const findings = scanStagedBlobContent(
      "docs/adr/example.md",
      `Set the token to ${SYNTHETIC_TELEGRAM_TOKEN} before deploying.\n`,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0]?.finding.kind).toBe("telegram-bot-token");
    expect(findings[0]?.filePath).toBe("docs/adr/example.md");
  });

  test("BLOCKS a bare Pushover-style token beside its naming cue", () => {
    const findings = scanStagedBlobContent(
      ".env.local",
      `PUSHOVER_APP_TOKEN=${SYNTHETIC_PUSHOVER_TOKEN}\n`,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0]?.finding.kind).toBe("pushover-style-bare-token");
  });

  test("BLOCKS a provisioning command carrying a literal value", () => {
    const findings = scanStagedBlobContent(
      "docs/design-spec.md",
      `Run: doppler secrets set STRIPE_API_KEY "${SYNTHETIC_PROVISIONING_VALUE}"\n`,
    );
    expect(findings.map((f) => f.finding.kind)).toContain("provisioning-command-literal-value");
  });

  test("reports the correct 1-based line number", () => {
    const findings = scanStagedBlobContent(
      "notes.md",
      ["# Notes", "", "token:", `${SYNTHETIC_TELEGRAM_TOKEN}`].join("\n"),
    );
    expect(findings[0]?.finding.line).toBe(4);
  });

  test("a valid in-file marker excuses the whole blob", () => {
    expect(
      scanStagedBlobContent(
        "fixtures.ts",
        `// SECRET-SCAN-OK: synthetic vector, never issued\nconst t = "${SYNTHETIC_TELEGRAM_TOKEN}";\n`,
      ),
    ).toHaveLength(0);
  });

  test("a documentation-shaped marker does NOT excuse a real-shaped value", () => {
    expect(
      scanStagedBlobContent(
        "docs/guard.md",
        `Write SECRET-SCAN-OK: <reason> to suppress.\n\n${SYNTHETIC_TELEGRAM_TOKEN}\n`,
      ),
    ).toHaveLength(1);
  });
});

describe("block message", () => {
  const findings = scanStagedBlobContent("docs/adr/example.md", `${SYNTHETIC_TELEGRAM_TOKEN}\n`);

  test("names the file and line", () => {
    expect(buildStagedCredentialBlock(findings)).toContain("docs/adr/example.md:1");
  });

  test("NEVER echoes the matched value", () => {
    // Hook output lands in scrollback, CI logs and screenshots. A guard that
    // prints the secret has moved the leak somewhere nobody rewrites.
    const block = buildStagedCredentialBlock(findings);
    expect(block).not.toContain(SYNTHETIC_TELEGRAM_TOKEN);
    expect(block).not.toContain("AAH9tRkQm3vZbN6xPwL2sD8fJ4gY7cV1uT0");
    expect(block).toContain("BLOCKED");
  });

  test("says to rotate, not merely to delete", () => {
    expect(buildStagedCredentialBlock(findings)).toContain("ROTATE IT");
  });

  test("explains a marker that was present but not honored", () => {
    const block = buildStagedCredentialBlock(findings, ["docs/adr/example.md"]);
    expect(block).toContain("NOT honored");
  });

  test("truncates a long finding list rather than paging the terminal", () => {
    const many = Array.from({ length: 9 }, (_, index) =>
      scanStagedBlobContent(`f${index}.md`, `${SYNTHETIC_TELEGRAM_TOKEN}\n`),
    ).flat();
    expect(buildStagedCredentialBlock(many)).toContain("…and 4 more");
  });
});

describe("false-positive floor — must stay silent on ordinary staged content", () => {
  test.each([
    [
      "ordinary source code that names the cue but quotes no value",
      [
        "export function readToken(): string {",
        "  const apiToken = process.env.PUSHOVER_APP_TOKEN ?? '';",
        "  if (apiToken.length !== 30) throw new Error('malformed app token');",
        "  return apiToken;",
        "}",
      ].join("\n"),
    ],
    [
      "a lockfile-shaped integrity hash",
      '"integrity": "sha512-9Ln0Vh7CzYX3PzKm4tR6bWqJfDs1oGyEuAv2ZcNiQ8kLpMrTsHdF3jXwUb5qYaeCgVnRkMzPtBu7WvJeSxDlA=="',
    ],
    [
      "a bare 40-hex git SHA",
      "reverted in 4f3c9ab1d2e8b7a6f5049c3d2e1b0a9f8c7d6e5b, see CHANGELOG",
    ],
    [
      "an abbreviated SHA beside release prose",
      "chore(release): v27.0.2 [skip ci] — follows 4f3c9ab, closes #1204",
    ],
    [
      "a documented placeholder in a provisioning command",
      'doppler secrets set TELEGRAM_BOT_TOKEN "<bot-token>"',
    ],
    [
      "a placeholder assignment with the naming cue right beside it",
      "export PUSHOVER_APP_TOKEN=<your-app-token>   # replace before running",
    ],
    [
      "a repeated-character filler token of exactly the real length",
      "PUSHOVER_APP_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    ],
    [
      "a SCREAMING_SNAKE variable name used as the value",
      'doppler secrets set BOT_TOKEN "TELEGRAM_BOT_TOKEN_VALUE"',
    ],
    [
      "a base64 blob with no naming cue anywhere near it",
      "cache key aGVsbG8gd29ybGQgdGhpcyBpcyBhIGxvbmcgYmFzZTY0IHN0cmluZw==",
    ],
    [
      "a UUID and an ISO timestamp",
      "run 3f2a9c41-77bd-4e0a-9c3e-1b5d8e6f0a72 at 2026-09-04T11:02:33Z",
    ],
  ])("stays silent on %s", (_label, content) => {
    expect(scanStagedBlobContent("fixture.txt", content)).toHaveLength(0);
  });
});

describe("argument parsing", () => {
  test("defaults to a check", () => {
    expect(parseArguments([]).kind).toBe("check");
    expect(parseArguments(["--check"]).kind).toBe("check");
  });

  test("rejects an unknown flag rather than silently scanning", () => {
    // A mis-invocation that exits 0 is an untraceable bypass that reads
    // exactly like a clean tree.
    expect(parseArguments(["--path", "x"]).kind).toBe("usage-error");
    expect(parseArguments(["--fix"]).kind).toBe("usage-error");
  });

  test("--help short-circuits", () => {
    expect(parseArguments(["--help"]).kind).toBe("help");
    expect(parseArguments(["-h"]).kind).toBe("help");
  });
});

// ── Integration: a real git index in a throwaway repository ───────────────

describe("staged-set enumeration against a real git index", () => {
  let repositoryDirectory = "";

  const git = (...args: string[]): string =>
    execFileSync("git", ["-C", repositoryDirectory, ...args], { encoding: "utf8" });

  beforeAll(() => {
    repositoryDirectory = mkdtempSync(join(tmpdir(), "staged-credential-guard-"));
    execFileSync("git", ["init", "-q", "--initial-branch=main", repositoryDirectory]);
    git("config", "user.email", "guard-suite@example.com");
    git("config", "user.name", "guard suite");
    git("config", "commit.gpgsign", "false");
    git("commit", "-q", "--allow-empty", "--no-verify", "-m", "chore: root");
  });

  afterAll(() => {
    if (repositoryDirectory !== "") rmSync(repositoryDirectory, { recursive: true, force: true });
  });

  const stage = (relativePath: string, content: string): void => {
    writeFileSync(join(repositoryDirectory, relativePath), content);
    git("add", "--", relativePath);
  };

  test("an unstaged file is invisible to the guard", () => {
    writeFileSync(join(repositoryDirectory, "untracked.md"), `${SYNTHETIC_TELEGRAM_TOKEN}\n`);
    expect(scanStagedChanges(repositoryDirectory).findings).toHaveLength(0);
    rmSync(join(repositoryDirectory, "untracked.md"));
  });

  test("a staged credential is found, with its path and line", () => {
    stage("leak.md", `# notes\n\nbot token ${SYNTHETIC_TELEGRAM_TOKEN}\n`);
    const result = scanStagedChanges(repositoryDirectory);
    expect(result.findings).toHaveLength(1);
    expect(result.findings[0]?.filePath).toBe("leak.md");
    expect(result.findings[0]?.finding.line).toBe(3);
    git("rm", "-q", "-f", "--", "leak.md");
  });

  test("reads the INDEX, not the working tree", () => {
    // The sharpest property of the whole guard. `git add -p` a clean hunk,
    // then keep editing: the bytes about to be committed are the staged ones.
    stage("partial.md", "nothing secret here\n");
    writeFileSync(
      join(repositoryDirectory, "partial.md"),
      `now with ${SYNTHETIC_TELEGRAM_TOKEN}\n`,
    );
    expect(scanStagedChanges(repositoryDirectory).findings).toHaveLength(0);

    // …and once that edit is staged, it blocks.
    git("add", "--", "partial.md");
    expect(scanStagedChanges(repositoryDirectory).findings).toHaveLength(1);
    git("rm", "-q", "-f", "--", "partial.md");
  });

  test("a file carrying a valid marker is excused, and reported as excused", () => {
    stage(
      "fixture.ts",
      `// SECRET-SCAN-OK: synthetic vector for the suite\nconst t = "${SYNTHETIC_TELEGRAM_TOKEN}";\n`,
    );
    const result = scanStagedChanges(repositoryDirectory);
    expect(result.findings).toHaveLength(0);
    expect(result.excusedFilePaths).toContain("fixture.ts");
    git("rm", "-q", "-f", "--", "fixture.ts");
  });

  test("a binary blob is skipped rather than decoded into garbage", () => {
    writeFileSync(
      join(repositoryDirectory, "blob.bin"),
      Buffer.concat([Buffer.from([0x00, 0x01, 0x02]), Buffer.from(SYNTHETIC_TELEGRAM_TOKEN)]),
    );
    git("add", "--", "blob.bin");
    expect(scanStagedChanges(repositoryDirectory).findings).toHaveLength(0);
    git("rm", "-q", "-f", "--", "blob.bin");
  });

  test("a path with a space survives the -z enumeration", () => {
    stage("a file with spaces.md", `token ${SYNTHETIC_TELEGRAM_TOKEN}\n`);
    const result = scanStagedChanges(repositoryDirectory);
    expect(result.findings[0]?.filePath).toBe("a file with spaces.md");
    git("rm", "-q", "-f", "--", "a file with spaces.md");
  });

  test("a staged DELETION contributes no content and is not scanned", () => {
    stage("doomed.md", `token ${SYNTHETIC_TELEGRAM_TOKEN}\n`);
    git("commit", "-q", "--no-verify", "-m", "chore: add fixture");
    git("rm", "-q", "--", "doomed.md");
    expect(scanStagedChanges(repositoryDirectory).findings).toHaveLength(0);
    git("commit", "-q", "--no-verify", "-m", "chore: remove fixture");
  });

  test("an empty index is clean", () => {
    expect(scanStagedChanges(repositoryDirectory).findings).toHaveLength(0);
  });
});
