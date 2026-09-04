import { describe, expect, it } from "bun:test";
import { join } from "node:path";
import {
  buildLineTerminatorDenyMessage,
  detectOptionLineTerminators,
  ESCAPE_HATCH_MARKER_TOKEN,
  findingPath,
} from "./lib/askuserquestion-option-line-terminator-detector.ts";

const HOOK_PATH = join(
  import.meta.dir,
  "pretooluse-askuserquestion-option-line-terminator-guard.ts",
);

// Built by code point: a literal U+2028/U+2029 in this source would terminate the line.
const LINE_SEPARATOR = String.fromCharCode(0x2028);
const PARAGRAPH_SEPARATOR = String.fromCharCode(0x2029);

// ── Fixtures ──────────────────────────────────────────────────────────────

/** The shape that renders correctly: one unbroken line per field, em dash as the joiner. */
const CLEAN_QUESTION = {
  question: "Which path should we take?",
  header: "Path",
  multiSelect: false,
  options: [
    { label: "Ship it", description: "Land the guard now — the operator asked for it." },
    { label: "Hold", description: "Wait for upstream to fix the renderer." },
  ],
};

const askPayload = (questions: unknown) => ({
  tool_name: "AskUserQuestion",
  tool_input: { questions },
});

// ── Detector (pure) ───────────────────────────────────────────────────────

describe("detectOptionLineTerminators", () => {
  it("finds nothing in a clean call", () => {
    expect(detectOptionLineTerminators({ questions: [CLEAN_QUESTION] })).toEqual([]);
  });

  it("reports the exact path, field and code point for a description", () => {
    const findings = detectOptionLineTerminators({
      questions: [
        CLEAN_QUESTION,
        {
          ...CLEAN_QUESTION,
          options: [
            CLEAN_QUESTION.options[0],
            { label: "Hold", description: "First paragraph.\n\nII. SHORT-TERM WIN:" },
          ],
        },
      ],
    });
    expect(findings.length).toBe(1);
    expect(findingPath(findings[0])).toBe("questions[1].options[1].description");
    expect(findings[0].field).toBe("description");
    expect(findings[0].codepoints).toEqual(["U+000A LINE FEED"]);
    // The sample never carries a raw terminator — it would corrupt the deny reason too.
    expect(findings[0].sample).toContain("\\n");
    expect(findings[0].sample.includes("\n")).toBe(false);
  });

  it("flags each of the four terminators, in either inspected field", () => {
    for (const [char, name] of [
      ["\n", "U+000A LINE FEED"],
      ["\r", "U+000D CARRIAGE RETURN"],
      [LINE_SEPARATOR, "U+2028 LINE SEPARATOR"],
      [PARAGRAPH_SEPARATOR, "U+2029 PARAGRAPH SEPARATOR"],
    ] as const) {
      const viaDescription = detectOptionLineTerminators({
        questions: [{ options: [{ label: "a", description: `x${char}y` }] }],
      });
      expect(viaDescription.map((f) => f.codepoints)).toEqual([[name]]);
      const viaLabel = detectOptionLineTerminators({
        questions: [{ options: [{ label: `x${char}y`, description: "a" }] }],
      });
      expect(viaLabel.map((f) => f.field)).toEqual(["label"]);
    }
  });

  it("ignores `question` and `preview` — those render newlines correctly", () => {
    expect(
      detectOptionLineTerminators({
        questions: [
          {
            question: "Line one\nline two",
            header: "H",
            options: [{ label: "a", description: "b", preview: "p1\np2" }],
          },
        ],
      }),
    ).toEqual([]);
  });

  it("skips every malformed shape instead of reporting it", () => {
    expect(detectOptionLineTerminators(undefined)).toEqual([]);
    expect(detectOptionLineTerminators(null)).toEqual([]);
    expect(detectOptionLineTerminators("questions")).toEqual([]);
    expect(detectOptionLineTerminators([])).toEqual([]);
    expect(detectOptionLineTerminators({})).toEqual([]);
    expect(detectOptionLineTerminators({ questions: "nope" })).toEqual([]);
    expect(detectOptionLineTerminators({ questions: [null, 7, "x"] })).toEqual([]);
    expect(detectOptionLineTerminators({ questions: [{ options: "nope" }] })).toEqual([]);
    expect(detectOptionLineTerminators({ questions: [{ options: [null] }] })).toEqual([]);
    expect(
      detectOptionLineTerminators({ questions: [{ options: [{ description: 42 }] }] }),
    ).toEqual([]);
  });
});

describe("buildLineTerminatorDenyMessage", () => {
  it("names the guard, the fix and the upstream issue", () => {
    const findings = detectOptionLineTerminators({
      questions: [{ options: [{ label: "a", description: "one\ntwo" }] }],
    });
    const message = buildLineTerminatorDenyMessage(findings);
    expect(message).toContain("[ASKUSERQUESTION-OPTION-NEWLINE-GUARD]");
    expect(message).toContain("questions[0].options[0].description");
    expect(message).toContain("U+000A LINE FEED");
    expect(message).toContain(" — "); // the prescribed replacement separator
    expect(message).toContain("anthropics/claude-code#88836");
  });

  /**
   * Regression guard for a self-disarming message. The marker is matched against the whole
   * serialized tool input, so a deny message that spelled the token would let a retry that
   * echoes the guard's own words silence the guard for that very call.
   */
  it("never spells the escape-hatch token, but does point at the spoke", () => {
    const findings = detectOptionLineTerminators({
      questions: [
        { options: [{ label: `a${LINE_SEPARATOR}b`, description: "one\r\ntwo" }] },
      ],
    });
    const message = buildLineTerminatorDenyMessage(findings);
    expect(findings.length).toBe(2);
    expect(message).not.toContain(ESCAPE_HATCH_MARKER_TOKEN);
    expect(message.toLowerCase()).toContain("escape hatch");
    expect(message).toContain("askuserquestion-option-line-terminator-guard.md");
  });

});

// ── Hook end-to-end (spawned) ─────────────────────────────────────────────

interface HookDecision {
  hookSpecificOutput: {
    permissionDecision: "allow" | "deny" | "ask";
    permissionDecisionReason?: string;
  };
}

async function runHookWithRawStdin(stdinText: string): Promise<HookDecision> {
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  proc.stdin.write(stdinText);
  proc.stdin.end();
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  return JSON.parse(out.trim()) as HookDecision;
}

const runHook = (payload: object) => runHookWithRawStdin(JSON.stringify(payload));

describe("hook process (spawned end-to-end)", () => {
  it("allows a clean AskUserQuestion call", async () => {
    const d = await runHook(askPayload([CLEAN_QUESTION]));
    expect(d.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("denies a newline in an option description", async () => {
    const d = await runHook(
      askPayload([
        { ...CLEAN_QUESTION, options: [{ label: "Ship it", description: "A.\n\nB." }] },
      ]),
    );
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(d.hookSpecificOutput.permissionDecisionReason).toContain(
      "questions[0].options[0].description",
    );
  });

  it("denies a newline in an option label", async () => {
    const d = await runHook(
      askPayload([
        { ...CLEAN_QUESTION, options: [{ label: "Ship\nit", description: "Land it." }] },
      ]),
    );
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(d.hookSpecificOutput.permissionDecisionReason).toContain(
      "questions[0].options[0].label",
    );
  });

  it("denies a U+2028 line separator in an option description", async () => {
    const d = await runHook(
      askPayload([
        {
          ...CLEAN_QUESTION,
          options: [{ label: "Ship it", description: `A.${LINE_SEPARATOR}B.` }],
        },
      ]),
    );
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(d.hookSpecificOutput.permissionDecisionReason).toContain(
      "U+2028 LINE SEPARATOR",
    );
  });

  it("allows a newline in `question` (renders correctly upstream)", async () => {
    const d = await runHook(
      askPayload([{ ...CLEAN_QUESTION, question: "Line one\nline two" }]),
    );
    expect(d.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("allows a newline in `preview` (renders correctly upstream)", async () => {
    const d = await runHook(
      askPayload([
        {
          ...CLEAN_QUESTION,
          options: [{ label: "Ship it", description: "Land it.", preview: "a\nb" }],
        },
      ]),
    );
    expect(d.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  /**
   * End-to-end version of the deny-message invariant: feeding the guard's own deny reason
   * back as the `question` text must still deny. If the message ever regains the token
   * this fails, because the marker search covers the whole serialized tool input.
   */
  it("stays armed when its own deny message is echoed back into the question", async () => {
    const seed = buildLineTerminatorDenyMessage(
      detectOptionLineTerminators({
        questions: [{ options: [{ label: "a", description: "one\ntwo" }] }],
      }),
    );
    const d = await runHook(
      askPayload([
        {
          ...CLEAN_QUESTION,
          question: seed.replace(/\n/g, " "),
          options: [{ label: "Ship it", description: "A.\n\nB." }],
        },
      ]),
    );
    expect(d.hookSpecificOutput.permissionDecision).toBe("deny");
  });

  it("allows an offending call carrying the escape-hatch marker in the tool input", async () => {
    const d = await runHook(
      askPayload([
        {
          ...CLEAN_QUESTION,
          question: `Which path? ${ESCAPE_HATCH_MARKER_TOKEN}`,
          options: [{ label: "Ship it", description: "A.\n\nB." }],
        },
      ]),
    );
    expect(d.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("allows malformed input: unparseable stdin, wrong shape, other tools", async () => {
    expect(
      (await runHookWithRawStdin("not json at all")).hookSpecificOutput
        .permissionDecision,
    ).toBe("allow");
    expect(
      (await runHookWithRawStdin("")).hookSpecificOutput.permissionDecision,
    ).toBe("allow");
    expect(
      (await runHook({ tool_name: "AskUserQuestion" })).hookSpecificOutput
        .permissionDecision,
    ).toBe("allow");
    expect(
      (await runHook(askPayload("not-an-array"))).hookSpecificOutput.permissionDecision,
    ).toBe("allow");
    expect(
      (await runHook({ tool_name: "Bash", tool_input: { command: "echo hi" } }))
        .hookSpecificOutput.permissionDecision,
    ).toBe("allow");
  });
});
