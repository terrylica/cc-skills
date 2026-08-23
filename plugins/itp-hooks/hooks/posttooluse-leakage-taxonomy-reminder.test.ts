/**
 * Tests for posttooluse-leakage-taxonomy-reminder.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-leakage-taxonomy-reminder.test.ts
 *
 * Pins the temporal-leakage adjudication doctrine nudge: verdict-shaped
 * language (a leak-family term next to a judgement word) in a text file
 * surfaces the five-category taxonomy ONCE PER SESSION, while a passing
 * mention of "leak", unrelated code, binary payloads, non-text extensions,
 * malformed input, and the LEAK-TAXONOMY-OK escape token all stay silent.
 *
 * The load-bearing assertions, stated up front because they are the ones a
 * future refactor is most likely to break:
 *
 *   1. THE FIRING RULE. `DOMAIN ∧ (DECISIVE ∨ WEAK)` or `GENERIC ∧ DECISIVE`.
 *      A weak verdict word (`fails`, `invalid`, `artifact`) never fires on a
 *      bare `leak`. Drop this and the hook fires on every memory-leak test in
 *      the repository.
 *   2. THE SENSE WINDOW. `LeakyReLU`, a goroutine leak, a parser lookahead and
 *      an acausal DSP filter are not temporal leakage, and the neighbourhood of
 *      the word says so. Drop this and `torch.nn.LeakyReLU` burns the session.
 *   3. PRECISION IS THE SAME AXIS AS THE GATE. The card fires at most once per
 *      session, so every false positive is ALSO a false negative — it spends
 *      the single shot before the real verdict is written. That is why the
 *      false-positive suite below is as long as the true-positive suite.
 *   4. The hook NEVER blocks. It is guarding against over-ruling-out; a deny
 *      would be that same error committed by the guard itself.
 */

import { afterAll, beforeAll, describe, expect, it } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  classifyLeakageTaxonomyForPostToolUseOrchestrator,
  classifyTemporalLeakageAdjudicationVerdictLanguageOncePerSessionForPostToolUseOrchestrator,
  detectTemporalLeakageAdjudicationVerdictLanguage,
  findNearestNonOverlappingTermPair,
  hasNonTemporalLeakSenseEvidenceAroundSpan,
  isLeakageTaxonomyReminderEligibleTarget,
  isLeakTaxonomySuppressedByWholeFilePostEditMarker,
  LEAKAGE_TAXONOMY_ADJUDICATION_STATIC_REMINDER_MESSAGE,
  resolveProximityWindowForTierPair,
  sanitizeSessionIdentifierForGateFilePathComponent,
} from "./posttooluse-leakage-taxonomy-reminder.ts";
import type { PostToolUseInput } from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

// ── Fixtures ─────────────────────────────────────────────────────────────────

const DOC = "/Users/terryli/eon/opendeviationbar-patterns/docs/xaubot-audit.md";

/** A real adjudication: leak-family term + verdict word, one sentence apart. */
const VERDICT =
  "The H1 join is non-causal at decision time, so we reject the reported 0.7459 AUC as unusable.";

/** The same subject matter with NO judgement attached — must stay silent. */
const BARE_MENTION =
  "The pipeline had a memory leak in the tick buffer; the profiler traced it to the ring allocator.";

/** Ordinary code with no leakage vocabulary at all. */
const UNRELATED_CODE = [
  "export function computeRollingSharpe(returns: number[], window: number): number[] {",
  "  if (returns.length < window) throw new Error('window exceeds sample');",
  "  return returns.map((_, i) => mean(returns.slice(i, i + window)));",
  "}",
].join("\n");

/**
 * Each test gets its own session id so the once-per-session gate file cannot
 * leak across tests (a shared id would make test order load-bearing).
 */
let sessionCounter = 0;
const RUN_NONCE = `${process.pid}-${Date.now()}`;
const freshSessionId = (): string => `leaktax-test-${RUN_NONCE}-${++sessionCounter}`;

const write = (
  file_path: string,
  content: string,
  session_id: string = freshSessionId(),
): PostToolUseInput => ({
  tool_name: "Write",
  tool_input: { file_path, content },
  session_id,
});

const edit = (
  file_path: string,
  old_string: string,
  new_string: string,
  session_id: string = freshSessionId(),
): PostToolUseInput => ({
  tool_name: "Edit",
  tool_input: { file_path, old_string, new_string },
  session_id,
});

const multiEdit = (
  file_path: string,
  edits: Array<{ old_string: string; new_string: string }>,
  session_id: string = freshSessionId(),
): PostToolUseInput => ({
  tool_name: "MultiEdit",
  tool_input: { file_path, edits } as PostToolUseInput["tool_input"],
  session_id,
});

const fires = async (input: PostToolUseInput): Promise<boolean> =>
  (await classifyLeakageTaxonomyForPostToolUseOrchestrator(input)).kind === "additional_context";

/**
 * Whole-file suppression reads the real filesystem, and `/tmp` is exempt from
 * the activation gate, so a temp path cannot exercise it. The fixture therefore
 * lives beside this test file — a durable, non-temp, in-repo path.
 */
const WHOLE_FILE_FIXTURE = join(import.meta.dir, ".leakage-taxonomy-whole-file-fixture.md");

beforeAll(() => {
  writeFileSync(
    WHOLE_FILE_FIXTURE,
    ["<!-- LEAK-TAXONOMY-OK: this document IS the doctrine -->", "", VERDICT, ""].join("\n"),
    "utf8",
  );
});

afterAll(() => {
  // The gate files and the whole-file fixture are the only side effects this
  // suite produces. Leaving a gate file behind would silently disarm a later
  // real session that happened to reuse the id, so sweep the namespace dir.
  try {
    rmSync("/tmp/.claude-leakage-taxonomy-reminder", { recursive: true, force: true });
  } catch {
    /* best-effort cleanup; a leftover gate file never fails a build */
  }
  try {
    rmSync(WHOLE_FILE_FIXTURE, { force: true });
  } catch {
    /* best-effort */
  }
});

// ── FIRES: genuine adjudication ──────────────────────────────────────────────

describe("FIRES: verdict-shaped leakage language", () => {
  it("fires on a Write containing a true verdict", async () => {
    expect(await fires(write(DOC, VERDICT))).toBe(true);
  });

  it("fires on an Edit that introduces the verdict", async () => {
    expect(await fires(edit(DOC, "TODO: assess the H1 join", VERDICT))).toBe(true);
  });

  it("fires when only a LATER MultiEdit fragment carries the verdict", async () => {
    const input = multiEdit(DOC, [
      { old_string: "alpha", new_string: "beta" },
      { old_string: "gamma", new_string: UNRELATED_CODE },
      { old_string: "delta", new_string: VERDICT },
    ]);
    expect(await fires(input)).toBe(true);
  });

  it("fires on the several verdict spellings the doctrine names", async () => {
    const phrasings = [
      "Order-block features are non-causal, so the backtest is invalid.",
      "Whole-sequence Viterbi is look-ahead; this arm is disqualified from OOS.",
      "The run counter is contaminated by future bars — discard the result.",
      "This is CAT-3 leakage, not CAT-2, so the walk-forward number is rejected.",
      "Data snooping here is fatal to the claim.",
      "The lookahead in the H1 merge is why the walk-forward fails.",
      "Given the leakage we rule out the 0.737 figure.",
      "Because the feature is acausal at t, we dismiss the Sharpe.",
    ];
    for (const phrasing of phrasings) {
      expect(await fires(write(DOC, phrasing))).toBe(true);
    }
  });

  it("fires in a code file's comment prose, not only in markdown", async () => {
    const py = "# consecutive_direction is non-causal at bar t, so this feature is rejected\nX = df\n";
    expect(await fires(write("/repo/features.py", py))).toBe(true);
  });
});

// ── Recall regression: the register this corpus actually writes verdicts in ──

describe("RECALL: verbatim verdict fields from the xaubot adjudication corpus", () => {
  /**
   * Every string below is a VERBATIM canonical verdict field from
   * video-forensics/corpus/xaubot. The first implementation's vocabulary was
   * written from intuition and missed all of them at document level; these are
   * the regression that keeps the vocabulary tied to real usage.
   */
  const CORPUS_VERDICTS: ReadonlyArray<readonly [string, string]> = [
    [
      "VERDICT.json $.SUPERSEDED_BY",
      "the model's claimed AUC turns out to be a look-ahead artifact (0.7459 -> 0.5164 once corrected).",
    ],
    [
      "DEEP-DIVE-VERDICT.json $.verdict",
      "THE FILL LOG IS GENUINE; THE MODEL'S SKILL IS NOT. Its claimed AUC collapses from 0.7459 to 0.5164 -- a coin flip -- once a look-ahead leak is removed.",
    ],
    [
      "DEEP-DIVE-VERDICT.json $.THE_DECISIVE_FINDING.headline",
      "The claimed Test AUC of 0.7339 is a real output of their code, and it is manufactured by look-ahead.",
    ],
    [
      "RETRAIN-VERDICT.json $.purpose",
      "v10.0.15 established that the model's claimed AUC was a look-ahead artifact, but left it condemned by a leak the author may not have known about.",
    ],
    [
      "SEED-AVERAGING-VERDICT.json $.verdict",
      "CLAIM FALSIFIED for this subject; the operator is right in principle about CAT-2 but CAT-2 is 1.9% of the effect here",
    ],
    [
      "retrain-workflow.json $.synthesis",
      "describing the result as removing five leaks overstates the count.",
    ],
  ];

  for (const [provenance, text] of CORPUS_VERDICTS) {
    it(`fires on ${provenance}`, () => {
      expect(findNearestNonOverlappingTermPair(text)).not.toBeNull();
    });
  }

  it("stays silent on a measurement report that merely names leaks twice", () => {
    // Verbatim from RETRAIN-VERDICT.json. The first implementation listed
    // `leaky` as a VERDICT word, which collapsed the two-term conjunction into
    // "mentions leak twice" and fired on this line. It is a measurement, not a
    // ruling, and 15 of 15 sentence-level fires over 1,448 corpus sentences
    // were exactly this shape.
    const measurementReport =
      "three named leaks fixed = 0.7328 against a leaky control of 0.7520 (faithful-OB figures).";
    expect(findNearestNonOverlappingTermPair(measurementReport)).toBeNull();
  });
});

// ── SILENT: the false positives that would get this hook disabled ────────────

describe("SILENT: a bare mention of leak is not an adjudication", () => {
  it("does NOT fire on a passing mention of the word leak", async () => {
    expect(await fires(write(DOC, BARE_MENTION))).toBe(false);
  });

  it("does NOT fire on leak-family vocabulary with no verdict anywhere", async () => {
    const descriptive =
      "The H1 bar is stamped at open, and the join_asof attaches the same-hour bar on every row.";
    expect(
      await fires(
        write(DOC, `${descriptive}\nLook-ahead freedom is a temporal non-interference property.`),
      ),
    ).toBe(false);
  });

  it("does NOT fire on a verdict with no leakage vocabulary", async () => {
    expect(
      await fires(write(DOC, "The Sharpe convention is inconsistent, so the number is invalid.")),
    ).toBe(false);
  });

  it("does NOT fire on unrelated code", async () => {
    expect(await fires(write("/repo/metrics.ts", UNRELATED_CODE))).toBe(false);
  });

  it("does NOT fire when the two terms are far apart in an unrelated document", async () => {
    const filler = "x".repeat(600);
    const far = `We reviewed the ring-allocator leak report.\n${filler}\nThe integration test fails on CI.`;
    expect(await fires(write(DOC, far))).toBe(false);
  });

  it('does NOT let a lone "leaky" satisfy both halves of the conjunction', async () => {
    // Historical: "leaky" once matched BOTH patterns at the same offset, so a
    // lone "leaky" self-satisfied the conjunction. It has since been removed
    // from the verdict vocabulary entirely, which is a second, independent
    // reason this line stays silent. Both belts are asserted.
    expect(await fires(write(DOC, "The leaky arm reports OOS AUC 0.737 across eight folds."))).toBe(
      false,
    );
    expect(findNearestNonOverlappingTermPair("the leaky arm")).toBeNull();
  });
});

// ── The firing rule: DOMAIN ∧ (DECISIVE ∨ WEAK) | GENERIC ∧ DECISIVE ─────────

describe("FIRING RULE: leak tier × verdict tier", () => {
  it("DOMAIN leak + DECISIVE verdict fires", () => {
    const match = findNearestNonOverlappingTermPair(
      "The H1 join is non-causal, so the 0.7459 AUC is rejected.",
    );
    expect(match?.leakTermTier).toBe("domain");
    expect(match?.verdictTermTier).toBe("decisive");
  });

  it("DOMAIN leak + WEAK verdict fires", () => {
    const match = findNearestNonOverlappingTermPair(
      "The look-ahead makes the reported number an artifact.",
    );
    expect(match?.leakTermTier).toBe("domain");
    expect(match?.verdictTermTier).toBe("weak");
  });

  it("GENERIC leak + DECISIVE verdict fires", () => {
    const match = findNearestNonOverlappingTermPair(
      "That leak is why we reject the walk-forward Sharpe.",
    );
    expect(match?.leakTermTier).toBe("generic");
    expect(match?.verdictTermTier).toBe("decisive");
  });

  it("GENERIC leak + WEAK verdict stays SILENT — the whole precision story", () => {
    // "A leak here fails the budget" is a memory-leak test, not an
    // adjudication. This single rule removes the memory-leak, fd-leak,
    // CSS-`leak`-class and news-leak false positives at once.
    expect(findNearestNonOverlappingTermPair("A leak here fails the byte budget.")).toBeNull();
    expect(
      findNearestNonOverlappingTermPair("fd leaks make the soak run invalid, discarding results"),
    ).toBeNull();
  });

  it("treats CAT-[123] as the SUBJECT of an adjudication, not the ruling", () => {
    // Naming a category is naming a leak, not passing judgement on it. If
    // CAT-N sits on the verdict side, "CAT-2 vs CAT-3" prose self-satisfies.
    const match = findNearestNonOverlappingTermPair("CAT-2 here is falsified as a source of lift.");
    expect(match?.leakTerm).toBe("CAT-2");
    expect(match?.leakTermTier).toBe("domain");
  });
});

// ── Sense disambiguation: the non-temporal senses of "leak" ──────────────────

describe("SENSE WINDOW: non-temporal senses stay silent", () => {
  const NON_TEMPORAL_SENSES: ReadonlyArray<readonly [string, string, string]> = [
    [
      "LeakyReLU as an nn.Module",
      ".py",
      "self.net = nn.Sequential(nn.Linear(d, 4 * d), nn.LeakyReLU(negative_slope=0.01))\n# leaky_relu keeps a small gradient so dead units cannot fail the whole layer.",
    ],
    [
      "functional leaky_relu with a NaN guard",
      ".py",
      'h = F.leaky_relu(z, 0.2)\nif torch.isnan(h).any():\n    raise ValueError("leaky_relu produced NaN; the run is invalid")',
    ],
    [
      "goroutine leak in a Go test",
      ".go",
      "func TestNoGoroutineLeak(t *testing.T) {\n\tdefer goleak.VerifyNone(t)\n\t// A leaked goroutine fails this test and invalidates the benchmark below.\n}",
    ],
    [
      "file-descriptor leak in a shell soak check",
      ".sh",
      '# Detect file-descriptor leaks before they fail the soak test.\nif [ "$COUNT" -gt "$FD_LIMIT" ]; then echo "fd leak: soak run invalid, discarding results"; fi',
    ],
    [
      "heap leak in a render test",
      ".ts",
      'test("no memory leak after 10k renders", () => {\n  // A leak here fails the budget; historically the listener map leaked.\n  expect(after - before).toBeLessThan(LEAK_BUDGET_BYTES);\n});',
    ],
    [
      "one-token parser lookahead",
      ".ts",
      "// One-token lookahead. If the lookahead does not match, the production fails\n// and we discard the partial node.\nconst la = this.peek(1);",
    ],
    [
      "acausal zero-phase DSP filter",
      ".py",
      "# filtfilt is acausal (zero-phase, forward+backward). For offline plotting only.\n# Applying it in the live path would fail the latency budget.\ny = signal.filtfilt(b, a, x)",
    ],
    [
      "a water leak and a rejected invoice",
      ".md",
      "The building manager confirmed a water leak in the third-floor riser. The repair failed twice, and the contractor's invoice was rejected by accounts payable.",
    ],
    [
      "a memo leaked to the press",
      ".md",
      "The memo leaked to the press on Tuesday. The committee dismissed the leaked draft as invalid, noting that it had been superseded twice.",
    ],
    [
      "secret leakage flagged by gitleaks",
      ".md",
      "gitleaks reported credential leakage in the fixture; the release is rejected until the key is rotated.",
    ],
  ];

  for (const [label, ext, text] of NON_TEMPORAL_SENSES) {
    it(`stays silent on ${label}`, async () => {
      expect(await fires(write(`/repo/sample${ext}`, text))).toBe(false);
    });
  }

  it("exposes the sense probe directly", () => {
    const torchLine = "self.act = nn.LeakyReLU(0.01)";
    const index = torchLine.indexOf("LeakyReLU");
    expect(hasNonTemporalLeakSenseEvidenceAroundSpan(torchLine, index, index + 9)).toBe(true);

    const adjudication = "the H1 leakage is decisive";
    const at = adjudication.indexOf("leakage");
    expect(hasNonTemporalLeakSenseEvidenceAroundSpan(adjudication, at, at + 7)).toBe(false);
  });

  it("does NOT treat `cache invalidation` as a verdict", () => {
    // `invalid\w*` matched "invalidation", and cache invalidation was the
    // single most common false-positive source in real source files. The
    // invalid family is now an explicit alternation.
    expect(
      findNearestNonOverlappingTermPair(
        "Fixes the MPS look-ahead buffer reuse and the cache invalidation path.",
      ),
    ).toBeNull();
  });
});

// ── Proximity is tiered ──────────────────────────────────────────────────────

describe("tiered proximity windows", () => {
  it("gives a decisive verdict the longest reach and a weak one the shortest", () => {
    expect(resolveProximityWindowForTierPair("domain", "decisive")).toBe(200);
    expect(resolveProximityWindowForTierPair("generic", "decisive")).toBe(100);
    expect(resolveProximityWindowForTierPair("domain", "weak")).toBe(80);
    expect(resolveProximityWindowForTierPair("generic", "weak")).toBe(80);
  });

  it("keeps a DOMAIN + DECISIVE pair 150 chars apart, drops it at 400", () => {
    expect(findNearestNonOverlappingTermPair(`non-causal${"z".repeat(150)} reject`)).not.toBeNull();
    expect(findNearestNonOverlappingTermPair(`non-causal${"z".repeat(400)} reject`)).toBeNull();
  });

  it("drops a WEAK pair past 80 chars — the build-artifact false positive", () => {
    expect(findNearestNonOverlappingTermPair(`look-ahead${"z".repeat(40)} artifact`)).not.toBeNull();
    expect(findNearestNonOverlappingTermPair(`look-ahead${"z".repeat(140)} artifact`)).toBeNull();
  });

  it("drops a GENERIC + DECISIVE pair past 100 chars", () => {
    expect(findNearestNonOverlappingTermPair(`the leak${"z".repeat(60)} rejects`)).not.toBeNull();
    expect(findNearestNonOverlappingTermPair(`the leak${"z".repeat(160)} rejects`)).toBeNull();
  });
});

// ── Activation gate: tool, extension, temp scratch ───────────────────────────

describe("isLeakageTaxonomyReminderEligibleTarget", () => {
  it("accepts text files on every file-edit tool", () => {
    for (const tool of ["Write", "Edit", "MultiEdit"]) {
      expect(isLeakageTaxonomyReminderEligibleTarget(tool, DOC)).toBe(true);
      expect(isLeakageTaxonomyReminderEligibleTarget(tool, "/a/notes.txt")).toBe(true);
      expect(isLeakageTaxonomyReminderEligibleTarget(tool, "/a/audit.py")).toBe(true);
      expect(isLeakageTaxonomyReminderEligibleTarget(tool, "/a/study.ipynb")).toBe(true);
    }
  });

  it("is case-insensitive about the extension", () => {
    expect(isLeakageTaxonomyReminderEligibleTarget("Write", "/a/NOTES.MD")).toBe(true);
  });

  it("rejects non-edit tools", () => {
    expect(isLeakageTaxonomyReminderEligibleTarget("Bash", DOC)).toBe(false);
    expect(isLeakageTaxonomyReminderEligibleTarget("Read", DOC)).toBe(false);
    expect(isLeakageTaxonomyReminderEligibleTarget("", DOC)).toBe(false);
  });

  it("rejects an empty or extensionless path", () => {
    expect(isLeakageTaxonomyReminderEligibleTarget("Write", "")).toBe(false);
    expect(isLeakageTaxonomyReminderEligibleTarget("Write", "/a/Makefile")).toBe(false);
  });

  it("exempts a throwaway scratch copy in a temp directory", () => {
    expect(isLeakageTaxonomyReminderEligibleTarget("Write", "/tmp/scratch-audit.md")).toBe(false);
  });
});

// ── Non-text / binary ────────────────────────────────────────────────────────

describe("non-text and binary payloads", () => {
  const NUL = String.fromCharCode(0); // never a literal NUL in this source file

  it("does NOT fire on a non-text extension even with verdict language", async () => {
    for (const path of ["/a/frame.png", "/a/bars.parquet", "/a/clip.mp4", "/a/model.bin"]) {
      expect(await fires(write(path, VERDICT))).toBe(false);
    }
  });

  it("does NOT fire when a text-extension file carries a binary payload", async () => {
    const binaryish = `${NUL}PNG${NUL}${VERDICT}`;
    expect(await fires(write("/a/blob.txt", binaryish))).toBe(false);
  });

  it("still fires when the NUL sits beyond the 1 KiB sniff prefix", async () => {
    // Documents the boundary honestly: the sniff is a cheap prefix probe, not a
    // whole-file scan, so a NUL past 1 KiB does not exempt the content.
    const padded = `${VERDICT}\n${"y".repeat(1100)}${NUL}`;
    expect(await fires(write("/a/blob.txt", padded))).toBe(true);
  });

  it("this source file contains no raw NUL byte", () => {
    // The first implementation shipped an ACTUAL NUL inside `.includes(...)`.
    // It was invisible to Read, silenced grep, and defeated Edit. Assert it.
    for (const path of [
      join(import.meta.dir, "posttooluse-leakage-taxonomy-reminder.ts"),
      import.meta.path,
    ]) {
      expect(readFileSync(path, "utf8").indexOf(NUL)).toBe(-1);
    }
  });
});

// ── Missing / malformed fields ───────────────────────────────────────────────

describe("missing fields and malformed input", () => {
  it("returns noop rather than throwing when tool_input is absent", async () => {
    const input = { tool_name: "Write" } as unknown as PostToolUseInput;
    expect(await fires(input)).toBe(false);
  });

  it("returns noop when tool_input is empty", async () => {
    expect(await fires({ tool_name: "Edit", tool_input: {} } as PostToolUseInput)).toBe(false);
  });

  it("returns noop when file_path is missing but content carries a verdict", async () => {
    const input = { tool_name: "Write", tool_input: { content: VERDICT } } as PostToolUseInput;
    expect(await fires(input)).toBe(false);
  });

  it("returns noop when a MultiEdit has no edits array", async () => {
    const input = { tool_name: "MultiEdit", tool_input: { file_path: DOC } } as PostToolUseInput;
    expect(await fires(input)).toBe(false);
  });

  it("returns noop when the content is empty", async () => {
    expect(await fires(write(DOC, ""))).toBe(false);
  });

  it("never returns anything but noop or additional_context (non-blocking)", async () => {
    for (const input of [write(DOC, VERDICT), write(DOC, BARE_MENTION)]) {
      const decision = await classifyLeakageTaxonomyForPostToolUseOrchestrator(input);
      expect(["noop", "additional_context"]).toContain(decision.kind);
      expect(decision).not.toHaveProperty("permissionDecision");
    }
  });
});

// ── Escape hatch ─────────────────────────────────────────────────────────────

describe("LEAK-TAXONOMY-OK escape hatch", () => {
  it("suppresses when the token is in the written content", async () => {
    expect(await fires(write(DOC, `<!-- LEAK-TAXONOMY-OK -->\n\n${VERDICT}`))).toBe(false);
  });

  it("suppresses when the token is in the edited fragment", async () => {
    expect(await fires(edit(DOC, "placeholder", `${VERDICT} <!-- LEAK-TAXONOMY-OK -->`))).toBe(
      false,
    );
  });

  it("suppresses from the post-edit FILE even when the fragment lacks the token", async () => {
    // THE regression this closes: in the first implementation `classify()`
    // called the detector with one argument, so the whole-file arm was dead
    // code — and an ordinary Edit to a marker-bearing doctrine file fired the
    // hook on its own doctrine. Exercised against a real file on disk, not a
    // string handed to a parameter production never populated.
    expect(isLeakTaxonomySuppressedByWholeFilePostEditMarker(WHOLE_FILE_FIXTURE)).toBe(true);
    expect(await fires(edit(WHOLE_FILE_FIXTURE, "x", VERDICT))).toBe(false);
  });

  it("does not suppress from a file that lacks the marker", () => {
    expect(isLeakTaxonomySuppressedByWholeFilePostEditMarker(DOC)).toBe(false);
  });

  it("fails open when the post-edit file cannot be read", () => {
    expect(
      isLeakTaxonomySuppressedByWholeFilePostEditMarker("/nonexistent/nowhere/absent.md"),
    ).toBe(false);
  });

  it("suppresses on the doctrine spoke itself when it is present", () => {
    // The spoke names LEAK-TAXONOMY-OK in its own header, so editing the
    // doctrine must never fire the hook the doctrine specifies.
    const spoke = `${process.env.HOME}/.claude/leakage-taxonomy-CLAUDE.md`;
    if (!existsSync(spoke)) return; // machine-dependent; skip rather than fail
    expect(isLeakTaxonomySuppressedByWholeFilePostEditMarker(spoke)).toBe(true);
  });

  it("does NOT suppress the OTHER fragments of a MultiEdit that lack the token", async () => {
    const input = multiEdit(DOC, [
      { old_string: "a", new_string: `harmless <!-- LEAK-TAXONOMY-OK -->` },
      { old_string: "b", new_string: VERDICT },
    ]);
    expect(await fires(input)).toBe(true);
  });

  it("is case-sensitive — a lowercase marker does not suppress", async () => {
    expect(await fires(write(DOC, `<!-- leak-taxonomy-ok -->\n\n${VERDICT}`))).toBe(true);
  });
});

// ── Session-id sanitisation ──────────────────────────────────────────────────

describe("session-id sanitisation for the gate-file path", () => {
  it("reduces a traversal payload to a single harmless component", () => {
    expect(sanitizeSessionIdentifierForGateFilePathComponent("../../tmp/pwned")).toBe("pwned");
    expect(sanitizeSessionIdentifierForGateFilePathComponent("a/b/../c")).toBe("c");
    expect(sanitizeSessionIdentifierForGateFilePathComponent("..\\..\\win")).toBe("win");
  });

  it("collapses degenerate ids to a named constant rather than to an empty string", () => {
    expect(sanitizeSessionIdentifierForGateFilePathComponent("")).toBe("unknown-session");
    expect(sanitizeSessionIdentifierForGateFilePathComponent("..")).toBe("unknown-session");
    expect(sanitizeSessionIdentifierForGateFilePathComponent("/")).toBe("unknown-session");
  });

  it("leaves an ordinary UUID-shaped session id untouched", () => {
    const uuid = "6f1c2f4e-6a2b-4c1d-9f8a-2b7e5d0c1a33";
    expect(sanitizeSessionIdentifierForGateFilePathComponent(uuid)).toBe(uuid);
  });

  it("cannot create a gate file outside the gate directory", async () => {
    // Measured before the fix: session_id "../../tmp/pwned" created
    // /tmp/pwned.reminded. The shared gate helper interpolates the id straight
    // into its path, so the sanitisation has to happen here.
    const escapeDir = mkdtempSync("/tmp/leaktax-escape-");
    const escapeTarget = join(escapeDir, "pwned.reminded");
    try {
      const traversal = `../..${escapeDir}/pwned`;
      await classifyLeakageTaxonomyForPostToolUseOrchestrator(write(DOC, VERDICT, traversal));
      expect(existsSync(escapeTarget)).toBe(false);
    } finally {
      rmSync(escapeDir, { recursive: true, force: true });
    }
  });
});

// ── Once per session ─────────────────────────────────────────────────────────

describe("once-per-session gate", () => {
  it("fires on the first adjudication and stays silent on the second", async () => {
    const session = freshSessionId();
    expect(await fires(write(DOC, VERDICT, session))).toBe(true);
    expect(await fires(write(DOC, VERDICT, session))).toBe(false);
    expect(await fires(edit(DOC, "x", VERDICT, session))).toBe(false);
  });

  it("fires again in a DIFFERENT session", async () => {
    const first = freshSessionId();
    const second = freshSessionId();
    expect(await fires(write(DOC, VERDICT, first))).toBe(true);
    expect(await fires(write(DOC, VERDICT, second))).toBe(true);
  });

  it("does NOT burn the gate on a non-matching edit", async () => {
    // The gate is claimed only after a match. If that ever inverts, a session
    // that edited one unrelated file would lose its reminder entirely.
    const session = freshSessionId();
    expect(await fires(write(DOC, BARE_MENTION, session))).toBe(false);
    expect(await fires(write("/repo/metrics.ts", UNRELATED_CODE, session))).toBe(false);
    expect(await fires(write(DOC, VERDICT, session))).toBe(true);
  });

  it("does NOT burn the gate on a temp-scratch adjudication", async () => {
    const session = freshSessionId();
    expect(await fires(write("/tmp/scratch-audit.md", VERDICT, session))).toBe(false);
    expect(await fires(write(DOC, VERDICT, session))).toBe(true);
  });

  it("does NOT burn the gate on a LeakyReLU edit — the compound failure", async () => {
    // Precision and the gate are one axis: a false positive here would spend
    // the session's only reminder before the real verdict was written.
    const session = freshSessionId();
    const torch = "self.act = nn.LeakyReLU(0.01)  # leaky_relu, so dead units cannot fail\n";
    expect(await fires(write("/repo/model.py", torch, session))).toBe(false);
    expect(await fires(write(DOC, VERDICT, session))).toBe(true);
  });

  it("does NOT burn the gate on a marker-suppressed doctrine edit", async () => {
    const session = freshSessionId();
    expect(await fires(edit(WHOLE_FILE_FIXTURE, "x", VERDICT, session))).toBe(false);
    expect(await fires(write(DOC, VERDICT, session))).toBe(true);
  });
});

// ── Detection helper contract ────────────────────────────────────────────────

describe("detectTemporalLeakageAdjudicationVerdictLanguage", () => {
  it("reports which two terms conjoined and how far apart", () => {
    const match = detectTemporalLeakageAdjudicationVerdictLanguage(write(DOC, VERDICT));
    expect(match).not.toBeNull();
    expect(match?.leakTerm.toLowerCase()).toBe("non-causal");
    expect(match?.verdictTerm.toLowerCase()).toBe("reject");
    expect(match?.characterDistance).toBeGreaterThan(0);
    expect(match?.characterDistance).toBeLessThanOrEqual(200);
  });

  it("scans MultiEdit fragments SEPARATELY, never concatenated", () => {
    // "leakage" ends fragment 1 and "invalid" opens fragment 2. Joining the
    // fragments would manufacture an adjacency that exists nowhere in the file.
    const input = multiEdit(DOC, [
      { old_string: "a", new_string: "The paper discusses leakage" },
      { old_string: "b", new_string: "invalid UTF-8 in the loader" },
    ]);
    expect(detectTemporalLeakageAdjudicationVerdictLanguage(input)).toBeNull();
  });

  it("returns the CLOSEST qualifying pair", () => {
    const text = "leakage is discussed here; later the walk-forward fails. Then: leakage — rejected.";
    const match = findNearestNonOverlappingTermPair(text);
    expect(match).not.toBeNull();
    expect(match?.verdictTerm.toLowerCase()).toBe("rejected");
  });

  it("is stateless across calls despite the /g patterns", () => {
    // A shared lastIndex would make the second call miss. Regression guard for
    // the fresh-RegExp-per-call construction in collectMatchedTermSpans.
    for (let i = 0; i < 3; i++) {
      expect(findNearestNonOverlappingTermPair(VERDICT)).not.toBeNull();
    }
  });
});

// ── The injected message ─────────────────────────────────────────────────────

describe("LEAKAGE_TAXONOMY_ADJUDICATION_STATIC_REMINDER_MESSAGE", () => {
  const message = LEAKAGE_TAXONOMY_ADJUDICATION_STATIC_REMINDER_MESSAGE;

  it("stays within its budget in BOTH units, because the two differ", () => {
    // The card contains `·` and `—`, so UTF-16 length and UTF-8 bytes are not
    // the same number: 896 chars but 907 bytes. Pinning only `.length` would
    // let a byte-denominated budget be breached unnoticed.
    expect(message.length).toBeLessThanOrEqual(900);
    expect(Buffer.byteLength(message, "utf8")).toBeLessThanOrEqual(960);
    expect(Buffer.byteLength(message, "utf8")).toBeGreaterThan(message.length);
  });

  it("names all five categories with their dispositions", () => {
    for (const category of ["CB", "PT", "BP", "EC", "DN"]) {
      expect(message).toContain(category);
    }
    expect(message).toContain("ACCEPT");
    expect(message).toContain("ACCEPT WITH DECLARATION");
    expect(message).toContain("REJECT as OOS");
    expect(message).toContain("REJECT until exact records removed");
    expect(message).toContain("REJECT for that decision time");
  });

  it("states that CAT-2 is not a leak, with the measured range", () => {
    expect(message).toContain("CAT-2");
    expect(message).toContain("+0.0014..+0.0042");
    expect(message).toContain("scaler fitted on the training fold");
    expect(message).toContain("Never lump it with CAT-3");
  });

  it("states that UNKNOWN is not a leak finding", () => {
    expect(message).toContain("UNKNOWN is not a leak finding");
  });

  it("names prefix invariance as the decisive test, over intent and plausibility", () => {
    expect(message).toContain("prefix invariance");
    expect(message).toContain("prefix replay");
    expect(message).toContain("Not intent, not plausibility");
  });

  it("splits the mandatory availability exclusion from the optional dependence gap", () => {
    expect(message).toContain("mandatory availability exclusion");
    expect(message).toContain("OPTIONAL dependence gap");
    expect(message).toContain("dependence_gap=0");
  });

  it("carries the SSoT pointer and the escape token", () => {
    expect(message).toContain("~/.claude/leakage-taxonomy-CLAUDE.md");
    expect(message).toContain("LEAK-TAXONOMY-OK");
  });

  it("is what the classifier actually injects", async () => {
    const decision =
      await classifyTemporalLeakageAdjudicationVerdictLanguageOncePerSessionForPostToolUseOrchestrator(
        write(DOC, VERDICT),
      );
    expect(decision.kind).toBe("additional_context");
    if (decision.kind === "additional_context") {
      expect(decision.message).toBe(message);
    }
  });

  it("would not re-trigger the hook if it were itself written to a file", async () => {
    // The card contains both a leak term and verdict words. Writing doctrine
    // into a file must not start a reminder loop — the embedded
    // LEAK-TAXONOMY-OK token is what prevents it.
    expect(await fires(write(DOC, message))).toBe(false);
  });
});

// ── Export symmetry with the sibling subhooks ────────────────────────────────

describe("orchestrator contract", () => {
  it("exposes the alias the orchestrator registry imports", () => {
    expect(classifyLeakageTaxonomyForPostToolUseOrchestrator).toBe(
      classifyTemporalLeakageAdjudicationVerdictLanguageOncePerSessionForPostToolUseOrchestrator,
    );
  });

  it("resolves a Promise for every input shape without throwing", async () => {
    const inputs: PostToolUseInput[] = [
      write(DOC, VERDICT),
      edit(DOC, "a", "b"),
      multiEdit(DOC, []),
      { tool_name: "Bash", tool_input: { command: "echo leakage rejected" } } as PostToolUseInput,
      {} as PostToolUseInput,
    ];
    for (const input of inputs) {
      const decision = await classifyLeakageTaxonomyForPostToolUseOrchestrator(input);
      expect(decision).toHaveProperty("kind");
    }
  });
});
