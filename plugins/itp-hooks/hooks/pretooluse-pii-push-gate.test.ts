// SECRET-SCAN-OK: synthetic fixtures for the secret-detection guard under test; no value here
// was ever issued by any provider. Each is hand-built to match a shape and nothing more.

import { describe, expect, test } from "bun:test";
import {
  explainPiiFindings,
  findPiiFindings,
  isPublishingPush,
} from "./pretooluse-pii-push-gate.ts";

const labels = (lines: string[], vis: "PUBLIC" | "PRIVATE" | "UNKNOWN") =>
  findPiiFindings(lines, vis).map((f) => f.label);

describe("secrets block regardless of visibility", () => {
  // The whole point of separating severities: a private repo is a legitimate home for
  // identity detail and never a legitimate home for a live credential.
  const cases: Array<[string, string]> = [
    ["GitHub token", "token = ghp_SYNTHETICfixtureNOTAREALtoken12345"],
    ["OpenAI-style key", 'OPENAI_KEY="sk-SYNTHETICfixtureNOTAREALkey1234"'],
    ["AWS access key id", "aws_access_key_id = AKIASYNTHETICNOTREAL"],
    ["Slack token", "SLACK=xoxb-000SYNTHETIC-fixtureNOTAREAL"],
    [
      "Telegram bot token",
      "BOT=1234567890:AAsynthetic_fixture_value_never_issued_x",
    ],
    ["private key block", "-----BEGIN OPENSSH PRIVATE KEY-----"],
  ];

  for (const [label, line] of cases) {
    test(`${label} blocks in a PRIVATE repo`, () => {
      expect(labels([line], "PRIVATE")).toContain(label);
    });
  }
});

describe("identity detail is visibility-dependent", () => {
  const identityLines = [
    "cd /Users/someone/projects/thing",
    "contact: person@example.org",
    "ssh 100.101.102.103",
    "router at 192.168.1.1",
  ];

  test("blocks when the repo is PUBLIC", () => {
    expect(findPiiFindings(identityLines, "PUBLIC").length).toBeGreaterThan(0);
  });

  // Measured 2026-09-20: applying the public policy to a private sole-owner repo produced
  // six DO-NOT-PUSH findings on content that repo exists to store.
  test("passes when the repo is PRIVATE", () => {
    expect(findPiiFindings(identityLines, "PRIVATE")).toEqual([]);
  });

  // An unknown-visibility repo scanned under the private policy would pass identity detail
  // silently, and the failure would only surface once published.
  test("UNKNOWN is treated as PUBLIC, not as PRIVATE", () => {
    expect(findPiiFindings(identityLines, "UNKNOWN").length).toBeGreaterThan(0);
  });
});

describe("placeholders are not findings", () => {
  // A gate that fires on its own documentation teaches people to reach for the escape hatch
  // by reflex, which is strictly worse than having no gate.
  test("documentation-shaped values pass", () => {
    const docs = [
      'password: "your-password-here"',
      "api_key = <YOUR_API_KEY>",
      // Escaped inside a template literal on purpose: the two characters "${" ARE the
      // fixture, and in a plain string a linter reads them as a mistyped placeholder.
      `token: "\${GITHUB_TOKEN}"`,
      "secret = changeme12345",
      "access_token: EXAMPLE_TOKEN_VALUE",
    ];
    expect(
      findPiiFindings(docs, "PUBLIC").filter((f) => f.severity === "secret"),
    ).toEqual([]);
  });

  test("but a real-looking assignment still blocks", () => {
    expect(labels(['password: "Tr0ub4dor&3xKcd9uPPer"'], "PUBLIC")).toContain(
      "credential assignment",
    );
  });

  test("the word alone in prose is not a finding", () => {
    expect(findPiiFindings(["the password is rotated quarterly"], "PUBLIC")).toEqual([]);
  });
});

describe("push detection", () => {
  test("recognises a plain push", () => {
    expect(isPublishingPush("git push origin main")).toBe(true);
    expect(isPublishingPush("git push --force-with-lease")).toBe(true);
    expect(isPublishingPush("git -C /repo push")).toBe(true);
  });

  // --dry-run publishes nothing; blocking it would block the safest way to inspect a push.
  test("ignores a dry run", () => {
    expect(isPublishingPush("git push --dry-run origin main")).toBe(false);
  });

  test("ignores non-push git commands", () => {
    expect(isPublishingPush("git status")).toBe(false);
    expect(isPublishingPush("git log --oneline")).toBe(false);
  });

  // Documented rather than fixed: the detector reads a command string, so a push named
  // inside an echo is indistinguishable from one being run. It errs toward scanning,
  // which costs a diff read and never costs a leak.
  test("a mention inside a string is treated as a push (accepted over-match)", () => {
    expect(isPublishingPush("echo 'remember to git push later'")).toBe(true);
  });
});

describe("reporting", () => {
  test("one finding per label, so a large diff stays readable", () => {
    const many = Array.from({ length: 500 }, (_, i) => `/Users/someone/file${i}`);
    expect(findPiiFindings(many, "PUBLIC")).toHaveLength(1);
  });

  test("secrets are ordered before identity detail", () => {
    const mixed = [
      "/Users/someone/x",
      "token = ghp_SYNTHETICfixtureNOTAREALtoken12345",
    ];
    expect(findPiiFindings(mixed, "PUBLIC")[0]?.severity).toBe("secret");
  });

  test("explanation names the escape hatch and the rotation duty", () => {
    const text = explainPiiFindings(
      findPiiFindings(["token = ghp_SYNTHETICfixtureNOTAREALtoken12345"], "PUBLIC"),
      "PUBLIC",
    );
    expect(text).toContain("PII-GATE-OK");
    expect(text).toContain("Rotate the credential FIRST");
  });

  test("explanation tells a private repo how to stop being asked", () => {
    const text = explainPiiFindings(
      findPiiFindings(["/Users/someone/x"], "UNKNOWN"),
      "UNKNOWN",
    );
    expect(text).toContain("claude-pii-visibility");
    // The reason `gh` is not simply called by the hook must travel with the advice,
    // or the next maintainer will "simplify" it back into the hook.
    expect(text).toContain("process storms");
  });
});

describe("empty and irrelevant input", () => {
  test("no added lines yields no findings", () => {
    expect(findPiiFindings([], "PUBLIC")).toEqual([]);
  });

  test("ordinary code yields no findings", () => {
    expect(
      findPiiFindings(
        ["export function add(a: number, b: number) { return a + b }"],
        "PUBLIC",
      ),
    ).toEqual([]);
  });
});
