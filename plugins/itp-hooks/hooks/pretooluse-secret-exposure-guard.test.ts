#!/usr/bin/env bun
/**
 * Tests for the credential + third-party-PII exposure detectors and the two
 * hooks that consume them.
 *
 * Every "positive" fixture below is SYNTHETIC — invented for this file, never
 * issued by a provider. They exist because the 23-repo audit proved that a
 * detector nobody tested against a realistic token shape is a detector that
 * silently misses. The negative fixtures matter just as much: the design
 * constraint is LOW false positives, since a noisy guard gets disabled and a
 * disabled guard is worse than no guard.
 *
 * SECRET-SCAN-OK: synthetic non-live fixtures for the exposure guard's own test suite
 * PII-SCAN-OK
 */

import { describe, expect, test } from "bun:test";
import {
  buildCredentialDenyReason,
  detectCredentialExposure,
  detectProvisioningCommandLiteralValues,
  detectPushoverStyleBareTokens,
  detectTelegramBotTokens,
  detectThirdPartyEmailAddresses,
  detectThirdPartyPhoneNumbers,
  detectThirdPartyPiiExposure,
  isPlaceholderSecretValue,
  redactSecretForTranscriptEcho,
} from "./lib/secret-and-pii-exposure-detector.ts";
import {
  collectNewContentFragmentsFromToolInput,
  evaluateNewContentForCredentialExposure,
} from "./pretooluse-secret-exposure-guard.ts";
import {
  evaluatePiiExposureContent,
  isPiiReminderEligibleTarget,
} from "./posttooluse-pii-exposure-reminder.ts";

// Synthetic, never-issued fixtures.
const SYNTHETIC_TELEGRAM_TOKEN = "8123456789:AAF3n7Qz1kLpXyR2vBcD4eF5gH6iJ7kL8mN";
const SYNTHETIC_PUSHOVER_TOKEN = "azGDORePK8gMaC0QOYAMyEEuzJnyUi";

describe("telegram bot token detector", () => {
  test("fires on a BotFather-shaped token — the class gitleaks has no rule for", () => {
    const findings = detectTelegramBotTokens(
      `TELEGRAM_BOT_TOKEN=${SYNTHETIC_TELEGRAM_TOKEN}\nsee docs`,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0]?.kind).toBe("telegram-bot-token");
    expect(findings[0]?.line).toBe(1);
  });

  test("fires inside prose in a design doc — docs/ is the dangerous directory", () => {
    const doc = [
      "## Provisioning",
      "",
      "The secret lives in Doppler. For reference the value was",
      SYNTHETIC_TELEGRAM_TOKEN,
      "at the time of writing.",
    ].join("\n");
    expect(detectTelegramBotTokens(doc)).toHaveLength(1);
    expect(detectTelegramBotTokens(doc)[0]?.line).toBe(4);
  });

  test("does NOT fire on an x-masked placeholder", () => {
    expect(
      detectTelegramBotTokens("TELEGRAM_BOT_TOKEN=123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"),
    ).toHaveLength(0);
  });

  test("does NOT fire on an angle-bracket placeholder or an env reference", () => {
    expect(detectTelegramBotTokens("TELEGRAM_BOT_TOKEN=<telegram-bot-token>")).toHaveLength(0);
    expect(detectTelegramBotTokens('token = os.environ["TELEGRAM_BOT_TOKEN"]')).toHaveLength(0);
  });

  test("never echoes the raw token back into the transcript", () => {
    const findings = detectTelegramBotTokens(SYNTHETIC_TELEGRAM_TOKEN);
    expect(findings[0]?.excerpt).not.toContain("AAF3n7Qz1kLpXyR2vBcD4e");
    expect(findings[0]?.excerpt).toContain("*");
  });
});

describe("pushover-style bare 30-char token detector", () => {
  test("fires on a bare 30-char alnum beside a PUSHOVER cue", () => {
    const findings = detectPushoverStyleBareTokens(
      `PUSHOVER_APP_TOKEN=${SYNTHETIC_PUSHOVER_TOKEN}`,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0]?.kind).toBe("pushover-style-bare-token");
  });

  test("fires on a user_key cue too", () => {
    expect(
      detectPushoverStyleBareTokens(`user_key: ${SYNTHETIC_PUSHOVER_TOKEN}`),
    ).toHaveLength(1);
  });

  test("does NOT fire on the same 30-char shape with no credential context", () => {
    // A git-tree-ish / nanoid-ish blob in unrelated prose must stay silent.
    expect(
      detectPushoverStyleBareTokens(`The build fingerprint was ${SYNTHETIC_PUSHOVER_TOKEN} today.`),
    ).toHaveLength(0);
  });

  test("does NOT fire on `<pushover-app-token>` placeholder syntax", () => {
    expect(detectPushoverStyleBareTokens("PUSHOVER_APP_TOKEN=<pushover-app-token>")).toHaveLength(
      0,
    );
  });

  test("does NOT fire on a shell variable reference", () => {
    expect(
      detectPushoverStyleBareTokens('curl -d "token=$PUSHOVER_APP_TOKEN" https://api.pushover.net'),
    ).toHaveLength(0);
  });

  test("does NOT fire on a 30-char run of letters only (an English-ish identifier)", () => {
    expect(
      detectPushoverStyleBareTokens("PUSHOVER_APP_TOKEN=abcdefghijklmnopqrstuvwxyzabcd"),
    ).toHaveLength(0);
  });
});

describe("provisioning-command literal-value detector", () => {
  test("fires on `doppler secrets set` carrying a real value", () => {
    const findings = detectProvisioningCommandLiteralValues(
      'doppler secrets set STRIPE_KEY "sk9Fh2kdlSowqmZx71bQ4tGv"',
    );
    expect(findings).toHaveLength(1);
    expect(findings[0]?.kind).toBe("provisioning-command-literal-value");
  });

  test("fires on `op item create` and `gh secret set` too", () => {
    expect(
      detectProvisioningCommandLiteralValues("gh secret set DEPLOY_KEY='k3JqW9zPl2xNv7Bd4Rt1'"),
    ).toHaveLength(1);
    expect(
      detectProvisioningCommandLiteralValues('op item create --title api "Zx41pQ7mR8vT2yNc9Lk3"'),
    ).toHaveLength(1);
  });

  test("does NOT fire on the placeholder form the docs are supposed to use", () => {
    expect(
      detectProvisioningCommandLiteralValues(
        'doppler secrets set TELEGRAM_BOT_TOKEN "<telegram-bot-token>"',
      ),
    ).toHaveLength(0);
    expect(
      detectProvisioningCommandLiteralValues('doppler secrets set STRIPE_KEY "$STRIPE_KEY"'),
    ).toHaveLength(0);
    expect(
      detectProvisioningCommandLiteralValues(
        'doppler secrets set STRIPE_KEY "YOUR_SECRET_KEY_HERE"',
      ),
    ).toHaveLength(0);
  });

  test("does NOT fire on a prose flag value", () => {
    expect(
      detectProvisioningCommandLiteralValues(
        'op item create --title "Telegram bot token for prod 2026"',
      ),
    ).toHaveLength(0);
  });

  test("does NOT fire on an unrelated command that merely mentions a long token", () => {
    expect(
      detectProvisioningCommandLiteralValues('echo "sk9Fh2kdlSowqmZx71bQ4tGv" > /dev/null'),
    ).toHaveLength(0);
  });
});

describe("third-party email detector", () => {
  test("fires on a real routable domain", () => {
    const findings = detectThirdPartyEmailAddresses("Contact: j.doe@acmewidgets.co.uk");
    expect(findings).toHaveLength(1);
    expect(findings[0]?.kind).toBe("third-party-email");
  });

  test("does NOT fire on RFC 2606 reserved domains", () => {
    expect(detectThirdPartyEmailAddresses("jane@example.com bob@example.org")).toHaveLength(0);
  });

  test("does NOT fire on GitHub noreply or the operator's own addresses", () => {
    expect(
      detectThirdPartyEmailAddresses(
        "1234+user@users.noreply.github.com amonic@gmail.com rickychanbc@gmail.com",
      ),
    ).toHaveLength(0);
  });

  test("does NOT fire on role addresses", () => {
    expect(detectThirdPartyEmailAddresses("support@pushover.net info@acme.io")).toHaveLength(0);
  });

  test("redacts the local part", () => {
    const findings = detectThirdPartyEmailAddresses("j.doe@acmewidgets.co.uk");
    expect(findings[0]?.excerpt).not.toContain("doe@");
  });
});

describe("third-party phone detector", () => {
  test("fires on an E.164 number with no context word needed", () => {
    expect(detectThirdPartyPhoneNumbers("+1 437 291 6053")).toHaveLength(1);
  });

  test("fires on a NANP number beside a telephony cue", () => {
    expect(detectThirdPartyPhoneNumbers("phone: 437-291-6053")).toHaveLength(1);
    expect(detectThirdPartyPhoneNumbers("Direct line (437) 291-6053")).toHaveLength(1);
  });

  test("does NOT fire on the reserved fictional 555-01xx range", () => {
    expect(detectThirdPartyPhoneNumbers("Call us at 604-555-0142")).toHaveLength(0);
    expect(detectThirdPartyPhoneNumbers("+1 604 555 0142")).toHaveLength(0);
    expect(detectThirdPartyPhoneNumbers("555-0142")).toHaveLength(0);
  });

  test("does NOT fire on a bare digit triple with no telephony cue", () => {
    expect(detectThirdPartyPhoneNumbers("The range 100-200-3000 was swept.")).toHaveLength(0);
    expect(detectThirdPartyPhoneNumbers("build 240-113-2026 finished")).toHaveLength(0);
  });

  test("does NOT fire on version strings or IP-like text", () => {
    expect(detectThirdPartyPhoneNumbers("v1.2.3 / 192.168.1.100 / 2026-08-28")).toHaveLength(0);
  });
});

describe("shared placeholder helpers", () => {
  test.each([
    "<pushover-app-token>",
    "{{token}}",
    "YOUR_TOKEN",
    "TELEGRAM_BOT_TOKEN",
    "xxxxxxxxxxxx",
    "aaaaaaaaaaaa",
    "example-secret",
  ])("%s is recognized as a placeholder", (value) => {
    expect(isPlaceholderSecretValue(value)).toBe(true);
  });

  test("a realistic secret is not a placeholder", () => {
    expect(isPlaceholderSecretValue("sk9Fh2kdlSowqmZx71bQ4tGv")).toBe(false);
  });

  test("redaction keeps the value unreconstructable", () => {
    expect(redactSecretForTranscriptEcho("abcd1234efgh5678")).toBe("abcd…******…78");
    expect(redactSecretForTranscriptEcho("short")).toBe("*****");
  });
});

describe("PreToolUse credential guard", () => {
  test("collects new content from Write, Edit and MultiEdit shapes", () => {
    expect(collectNewContentFragmentsFromToolInput({ content: "a" })).toEqual(["a"]);
    expect(collectNewContentFragmentsFromToolInput({ new_string: "b" })).toEqual(["b"]);
    expect(
      collectNewContentFragmentsFromToolInput({
        edits: [{ new_string: "c" }, { new_string: "d" }, { old_string: "ignored" }],
      }),
    ).toEqual(["c", "d"]);
  });

  test("denies a doc write that carries a live-shaped token", () => {
    const reason = evaluateNewContentForCredentialExposure("docs/adr/2026-08-28-bot.md", [
      `doppler secrets set TELEGRAM_BOT_TOKEN "${SYNTHETIC_TELEGRAM_TOKEN}"`,
    ]);
    expect(reason).not.toBeNull();
    expect(reason).toContain("BLOCKED");
    expect(reason).toContain("docs/adr/2026-08-28-bot.md");
  });

  test("allows the placeholder form of the same doc", () => {
    expect(
      evaluateNewContentForCredentialExposure("docs/adr/2026-08-28-bot.md", [
        'doppler secrets set TELEGRAM_BOT_TOKEN "<telegram-bot-token>"',
      ]),
    ).toBeNull();
  });

  test("SECRET-SCAN-OK with a ≥10-char reason suppresses the deny", () => {
    expect(
      evaluateNewContentForCredentialExposure("test/fixtures.md", [
        `<!-- SECRET-SCAN-OK: synthetic fixture for the guard test suite -->\n${SYNTHETIC_TELEGRAM_TOKEN}`,
      ]),
    ).toBeNull();
  });

  test("a bare SECRET-SCAN-OK with no reason does NOT suppress", () => {
    expect(
      evaluateNewContentForCredentialExposure("test/fixtures.md", [
        `<!-- SECRET-SCAN-OK -->\n${SYNTHETIC_TELEGRAM_TOKEN}`,
      ]),
    ).not.toBeNull();
  });

  test("MultiEdit fragments are scanned separately so context cannot be stitched", () => {
    // "PUSHOVER" in one edit must not license a 30-char blob in a different edit.
    expect(
      evaluateNewContentForCredentialExposure("notes.md", [
        "PUSHOVER_APP_TOKEN is stored in the vault.",
        `fingerprint ${SYNTHETIC_PUSHOVER_TOKEN}`,
      ]),
    ).toBeNull();
  });

  test("aggregate detector reports every class at once", () => {
    const blob = [
      `TELEGRAM_BOT_TOKEN=${SYNTHETIC_TELEGRAM_TOKEN}`,
      `PUSHOVER_APP_TOKEN=${SYNTHETIC_PUSHOVER_TOKEN}`,
      'doppler secrets set STRIPE_KEY "sk9Fh2kdlSowqmZx71bQ4tGv"',
    ].join("\n");
    const kinds = detectCredentialExposure(blob).map((f) => f.kind);
    expect(kinds).toContain("telegram-bot-token");
    expect(kinds).toContain("pushover-style-bare-token");
    expect(kinds).toContain("provisioning-command-literal-value");
  });

  test("the deny reason names the escape hatch and the rotation duty", () => {
    const reason = buildCredentialDenyReason("docs/x.md", detectCredentialExposure(
      `TELEGRAM_BOT_TOKEN=${SYNTHETIC_TELEGRAM_TOKEN}`,
    ));
    expect(reason).toContain("SECRET-SCAN-OK");
    expect(reason).toContain("ROTATE IT");
  });
});

describe("PostToolUse PII reminder", () => {
  test("is eligible for docs and config, not for source or scratch", () => {
    expect(isPiiReminderEligibleTarget("Write", "/repo/docs/adr/x.md")).toBe(true);
    expect(isPiiReminderEligibleTarget("Edit", "/repo/config.yaml")).toBe(true);
    expect(isPiiReminderEligibleTarget("Write", "/repo/src/index.ts")).toBe(false);
    expect(isPiiReminderEligibleTarget("Bash", "/repo/docs/x.md")).toBe(false);
    expect(isPiiReminderEligibleTarget("Write", "/tmp/scratch/x.md")).toBe(false);
  });

  test("reminds on a real contact block", () => {
    const reminder = evaluatePiiExposureContent(
      "docs/design/vendor.md",
      "Primary contact: j.doe@acmewidgets.co.uk, phone: 437-291-6053",
    );
    expect(reminder).not.toBeNull();
    expect(reminder).toContain("PII-SCAN-OK");
  });

  test("stays silent on the sanitized form of the same block", () => {
    expect(
      evaluatePiiExposureContent(
        "docs/design/vendor.md",
        "Primary contact: contact@example.com, phone: 604-555-0142",
      ),
    ).toBeNull();
  });

  test("a bare PII-SCAN-OK comment suppresses it", () => {
    expect(
      evaluatePiiExposureContent(
        "docs/design/vendor.md",
        "<!-- PII-SCAN-OK -->\nMaintainer: j.doe@acmewidgets.co.uk",
      ),
    ).toBeNull();
  });

  test("aggregate PII detector returns findings sorted by line", () => {
    const findings = detectThirdPartyPiiExposure(
      ["line one", "phone: 437-291-6053", "j.doe@acmewidgets.co.uk"].join("\n"),
    );
    expect(findings.map((f) => f.line)).toEqual([2, 3]);
  });
});
