/**
 * Shared detector for CREDENTIAL and THIRD-PARTY-PII exposure in edited text.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  The incident this exists for (2026-08-28, 23-repo audit)
 * ════════════════════════════════════════════════════════════════════════
 *
 * A 23-repository sweep of the published tree found, AFTER two deliberate
 * scrub campaigns had already run:
 *
 *   1. A LIVE Telegram bot token. It survived both scrubs because gitleaks
 *      HAS NO TELEGRAM-BOT-TOKEN RULE. Only trufflehog's provider-side
 *      verification caught it.
 *   2. LIVE Pushover application tokens and a user key. These are bare
 *      30-character alphanumerics with NO prefix: trufflehog has no detector
 *      for them at all, and gitleaks caught exactly one — by luck, because
 *      the adjacent variable happened to be named `PUSHOVER_APP_TOKEN`.
 *   3. A third-party contact's real name, business email and phone number
 *      REINTRODUCED into the published tree six days after an eleven-agent
 *      scrub of 2,602 files. A one-time sweep does not hold; only an
 *      edit-time gate holds.
 *   4. Every single credential found sat in an ADR, a design spec or a
 *      planning document — pasted as a worked example of a
 *      `doppler secrets set …` provisioning command, frequently in a file
 *      that simultaneously stated the secret lived in Doppler.
 *      **`docs/` is the dangerous directory, not `src/`.**
 *
 * The structural gap is therefore NOT "we need another scanner in CI". It is
 * that nothing looked at the bytes at the moment they were written, and the
 * two scanners in the audit gate are each blind to exactly the token shapes
 * this operator actually uses.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Two classes, two severities — deliberately asymmetric
 * ════════════════════════════════════════════════════════════════════════
 *
 * CREDENTIAL findings are high-confidence, structurally distinctive, and
 * catastrophic if published, so they are consumed by a PreToolUse guard that
 * DENIES the write outright (`pretooluse-secret-exposure-guard.ts`).
 *
 * PII findings are inherently fuzzier — an email address in a doc is often
 * legitimate (a vendor support address, an RFC author, a git commit trailer)
 * — so they are consumed by a PostToolUse hook that only INJECTS A REMINDER
 * (`posttooluse-pii-exposure-reminder.ts`). A noisy guard gets disabled, and
 * a disabled guard is strictly worse than no guard; blocking on the fuzzy
 * class would buy exactly that outcome.
 *
 * Every detector below is calibrated for LOW FALSE POSITIVES over high
 * recall. This is a last line of defense at the keystroke, not a substitute
 * for the audit-gate scanners.
 */

// ══════════════════════════════════════════════════════════════════════════
//  Types
// ══════════════════════════════════════════════════════════════════════════

/** High-confidence credential shapes. Consumed by the blocking PreToolUse guard. */
export type CredentialFindingKind =
  | "telegram-bot-token"
  | "pushover-style-bare-token"
  | "provisioning-command-literal-value";

/**
 * Fuzzier third-party-identity shapes. Consumed by the non-blocking reminder.
 *
 * The last three were added after the 2026-08-29 release-notes incident (see
 * the "second incident" note below). None of them is a usable credential on its
 * own — an AWS account ID cannot authenticate, a Workers hostname is public DNS,
 * and a 1Password item ID is inert without the vault — so all three REMIND
 * rather than block. What they leak is ATTRIBUTION: whose account, which
 * client, which deal.
 */
export type PiiFindingKind =
  | "third-party-email"
  | "third-party-phone-number"
  | "aws-account-id"
  | "client-scoped-workers-dev-hostname"
  | "vault-item-identifier";

export interface ExposureFinding<K extends string> {
  /** Which detector fired. */
  kind: K;
  /** 1-based line number within the scanned fragment. */
  line: number;
  /** Redacted, human-readable excerpt safe to echo back into the transcript. */
  excerpt: string;
  /** Why this specific detector treats the match as real rather than a placeholder. */
  rationale: string;
}

export type CredentialFinding = ExposureFinding<CredentialFindingKind>;
export type PiiFinding = ExposureFinding<PiiFindingKind>;

// ══════════════════════════════════════════════════════════════════════════
//  Shared placeholder recognition
// ══════════════════════════════════════════════════════════════════════════

/**
 * Tokens that mark a value as a DOCUMENTATION PLACEHOLDER rather than a live
 * secret. Docs are the dangerous directory precisely because they are full of
 * worked examples, so recognizing the example form is the single highest-value
 * false-positive suppressor in this file.
 */
const PLACEHOLDER_SUBSTRING_MARKERS: readonly string[] = [
  "xxxx",
  "your",
  "redact",
  "example",
  "placeholder",
  "changeme",
  "change-me",
  "dummy",
  "sample",
  "fake",
  "notreal",
  "abcdef123456",
  "0123456789",
  "deadbeef",
  "s3cret",
  "hunter2",
];

/** Angle-bracket / brace / shell-expansion placeholder syntax, e.g. `<pushover-app-token>`. */
const PLACEHOLDER_SYNTAX_PATTERN = /[<>{}$*]|\.\.\./;

/**
 * A candidate secret value is a placeholder when it uses placeholder syntax,
 * names itself as an example, is a single repeated character, or is a bare
 * SCREAMING_SNAKE_CASE identifier (i.e. a variable name, not its value).
 */
export function isPlaceholderSecretValue(rawValue: string): boolean {
  const value = rawValue.trim();
  if (value.length === 0) return true;
  if (PLACEHOLDER_SYNTAX_PATTERN.test(value)) return true;
  if (/^(.)\1+$/.test(value)) return true;
  if (/^[A-Z][A-Z0-9_]*$/.test(value)) return true;
  const lowered = value.toLowerCase();
  return PLACEHOLDER_SUBSTRING_MARKERS.some((marker) => lowered.includes(marker));
}

/**
 * A real machine-generated secret mixes character classes. Requiring both a
 * letter and a digit discards English words, file paths and prose fragments
 * that would otherwise satisfy a bare length threshold.
 */
export function hasMixedAlphanumericCharacterClasses(value: string): boolean {
  return /[A-Za-z]/.test(value) && /\d/.test(value);
}

/** Mask the middle of a matched secret so the transcript never re-publishes it. */
export function redactSecretForTranscriptEcho(value: string): string {
  if (value.length <= 8) return "*".repeat(value.length);
  return `${value.slice(0, 4)}…${"*".repeat(6)}…${value.slice(-2)}`;
}

/** 1-based line number of a character offset within a blob. */
function lineNumberAtOffset(blob: string, offset: number): number {
  let line = 1;
  for (let i = 0; i < offset && i < blob.length; i++) {
    if (blob.charCodeAt(i) === 10) line++;
  }
  return line;
}

/** The ±`radius` character neighbourhood around a match, for context tests. */
function neighbourhoodAround(blob: string, start: number, end: number, radius: number): string {
  return blob.slice(Math.max(0, start - radius), Math.min(blob.length, end + radius));
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 1 — Telegram bot tokens
// ══════════════════════════════════════════════════════════════════════════

/**
 * `<numeric bot id>:AA<35 url-safe base64 chars>` — the shape BotFather issues.
 * Structurally unmistakable, which is why this one is safe to hard-block. The
 * `AA` prefix is part of the format, not a coincidence, and gitleaks ships no
 * rule for it (incident finding #1).
 */
const TELEGRAM_BOT_TOKEN_PATTERN = /\b\d{8,10}:AA[A-Za-z0-9_-]{32,}\b/g;

export function detectTelegramBotTokens(blob: string): CredentialFinding[] {
  const findings: CredentialFinding[] = [];
  for (const match of blob.matchAll(TELEGRAM_BOT_TOKEN_PATTERN)) {
    const token = match[0];
    const secretBody = token.slice(token.indexOf(":") + 3);
    if (isPlaceholderSecretValue(secretBody)) continue;
    findings.push({
      kind: "telegram-bot-token",
      line: lineNumberAtOffset(blob, match.index ?? 0),
      excerpt: redactSecretForTranscriptEcho(token),
      rationale:
        "matches the BotFather `<bot-id>:AA…` format exactly; gitleaks has no rule for this shape",
    });
  }
  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 2 — Pushover-style bare 30-character tokens
// ══════════════════════════════════════════════════════════════════════════

/**
 * Pushover application tokens and user keys are 30 characters of bare
 * alphanumerics with NO prefix whatsoever. In isolation that shape is
 * indistinguishable from a hash fragment, a nanoid, or a base32 blob — so
 * matching it unconditionally would be intolerably noisy.
 *
 * The discriminator is CONTEXT: the audit found these tokens only ever
 * appear beside a naming cue (`PUSHOVER_APP_TOKEN`, `user_key`, `--token`).
 * Requiring that cue within ±80 characters is what makes this detector quiet
 * enough to be allowed to block.
 */
const PUSHOVER_CONTEXT_PATTERN =
  /pushover|app[_\s-]?token|user[_\s-]?key|api[_\s-]?token|--token\b|PO_(?:APP|USER)/i;

const BARE_THIRTY_CHAR_ALNUM_PATTERN = /\b[A-Za-z0-9]{30}\b/g;

const PUSHOVER_CONTEXT_RADIUS_CHARACTERS = 80;

export function detectPushoverStyleBareTokens(blob: string): CredentialFinding[] {
  const findings: CredentialFinding[] = [];
  for (const match of blob.matchAll(BARE_THIRTY_CHAR_ALNUM_PATTERN)) {
    const token = match[0];
    const start = match.index ?? 0;
    if (isPlaceholderSecretValue(token)) continue;
    if (!hasMixedAlphanumericCharacterClasses(token)) continue;
    const context = neighbourhoodAround(
      blob,
      start,
      start + token.length,
      PUSHOVER_CONTEXT_RADIUS_CHARACTERS,
    );
    if (!PUSHOVER_CONTEXT_PATTERN.test(context)) continue;
    findings.push({
      kind: "pushover-style-bare-token",
      line: lineNumberAtOffset(blob, start),
      excerpt: redactSecretForTranscriptEcho(token),
      rationale:
        "bare 30-char alphanumeric beside a Pushover/app-token/user-key cue; no scanner detects this shape",
    });
  }
  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 3 — provisioning command carrying a real literal value
// ══════════════════════════════════════════════════════════════════════════

/**
 * The exact shape that leaked every credential in the audit: a worked example
 * of a secret-manager provisioning command with the REAL value left in.
 *
 *   doppler secrets set TELEGRAM_BOT_TOKEN "8123456789:AAF…"   ← leaked
 *   doppler secrets set TELEGRAM_BOT_TOKEN "<bot-token>"       ← fine
 *
 * The command families are enumerated rather than generalized, because a
 * generic "assignment with a long value" rule fires on lockfiles, hashes and
 * base64 fixtures constantly.
 */
const PROVISIONING_COMMAND_PATTERN =
  /\b(?:doppler\s+secrets\s+set|op\s+item\s+(?:create|edit)|vault\s+(?:set|put)|gh\s+secret\s+set|wrangler\s+secret\s+put|aws\s+secretsmanager\s+(?:create|put)-secret|security\s+add-generic-password)\b[^\n]*/g;

/** A quoted or bare literal long enough to be a credential. */
const PROVISIONING_LITERAL_VALUE_PATTERN = /"([^"\n]{16,})"|'([^'\n]{16,})'|=([^\s"'\n]{16,})/g;

const MINIMUM_PROVISIONING_LITERAL_LENGTH = 16;

export function detectProvisioningCommandLiteralValues(blob: string): CredentialFinding[] {
  const findings: CredentialFinding[] = [];
  for (const commandMatch of blob.matchAll(PROVISIONING_COMMAND_PATTERN)) {
    const commandText = commandMatch[0];
    const commandStart = commandMatch.index ?? 0;
    for (const valueMatch of commandText.matchAll(PROVISIONING_LITERAL_VALUE_PATTERN)) {
      const value = valueMatch[1] ?? valueMatch[2] ?? valueMatch[3] ?? "";
      if (value.length < MINIMUM_PROVISIONING_LITERAL_LENGTH) continue;
      if (isPlaceholderSecretValue(value)) continue;
      if (!hasMixedAlphanumericCharacterClasses(value)) continue;
      // A value containing whitespace is prose (a `--note "…"` flag), not a key.
      if (/\s/.test(value)) continue;
      findings.push({
        kind: "provisioning-command-literal-value",
        line: lineNumberAtOffset(blob, commandStart),
        excerpt: redactSecretForTranscriptEcho(value),
        rationale:
          "secret-manager provisioning command with a real literal value — the exact shape that leaked in the audit",
      });
    }
  }
  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 4 — third-party email addresses
// ══════════════════════════════════════════════════════════════════════════

const EMAIL_PATTERN = /\b[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)\b/g;

/** RFC 2606 reserved / non-routable / CI-synthetic domains: never real people. */
const NON_REAL_EMAIL_DOMAIN_PATTERN =
  /^(?:example\.(?:com|org|net)|example|test|invalid|localhost|localdomain|[^.]+\.(?:example|test|invalid|local|localhost)|users\.noreply\.github\.com|noreply\.github\.com|email\.com|domain\.com|mail\.com|yourdomain\.com|company\.com)$/i;

/**
 * The operator's OWN addresses. Publishing these is a deliberate, standing
 * choice (they are in the public marketplace metadata already), so flagging
 * them would be pure noise on every plugin manifest edit.
 */
const OPERATOR_OWN_EMAIL_ADDRESSES: ReadonlySet<string> = new Set([
  "amonic@gmail.com",
  "rickychanbc@gmail.com",
  "terry@eonlabs.com",
  "terryli@eonlabs.com",
]);

/** Role addresses are organizational, not personal — out of scope for a PII reminder. */
const ROLE_LOCAL_PART_PATTERN =
  /^(?:noreply|no-reply|donotreply|support|hello|info|admin|contact|security|abuse|help|sales|team|dev|ops)$/i;

export function detectThirdPartyEmailAddresses(blob: string): PiiFinding[] {
  const findings: PiiFinding[] = [];
  for (const match of blob.matchAll(EMAIL_PATTERN)) {
    const address = match[0];
    const domain = match[1] ?? "";
    const localPart = address.slice(0, address.lastIndexOf("@"));
    if (NON_REAL_EMAIL_DOMAIN_PATTERN.test(domain)) continue;
    if (OPERATOR_OWN_EMAIL_ADDRESSES.has(address.toLowerCase())) continue;
    if (ROLE_LOCAL_PART_PATTERN.test(localPart)) continue;
    findings.push({
      kind: "third-party-email",
      line: lineNumberAtOffset(blob, match.index ?? 0),
      excerpt: `${localPart.slice(0, 2)}…@${domain}`,
      rationale: "email address at a real, routable domain that is not the operator's own",
    });
  }
  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 5 — third-party phone numbers
// ══════════════════════════════════════════════════════════════════════════

/** `+1 604 555 0142`, `+8613800138000` — the leading `+` is itself strong evidence. */
const E164_PHONE_PATTERN = /\+\d{1,3}[\s.\-()]*\d{2,4}[\s.\-()]*\d{3}[\s.\-()]*\d{2,4}\b/g;

/** `(604) 555-0142`, `604-555-0142`, `604.555.0142` — needs a context word to fire. */
const NANP_PHONE_PATTERN = /(?:\(\d{3}\)\s*|\b\d{3}[\s.-])\d{3}[\s.-]\d{4}\b/g;

/**
 * A bare `nnn-nnn-nnnn` also matches version ranges, ID sequences and part
 * numbers, so the NANP form requires a telephony cue within ±40 characters.
 * The E.164 form does not — nothing else in a repo starts with `+` and 11
 * digits.
 */
const PHONE_CONTEXT_PATTERN =
  /\b(?:phone|tel|telephone|mobile|cell|call|calling|fax|whatsapp|sms|text me|contact|reach(?:able)? at|direct line)\b/i;

const PHONE_CONTEXT_RADIUS_CHARACTERS = 40;

/**
 * NANP reserves `555-0100` through `555-0199` for fictional use. Every doc
 * example should use one, and none of them is ever a real person.
 */
const RESERVED_FICTIONAL_NANP_PATTERN = /\b555[\s.-]?01\d{2}\b/;

function isReservedOrDegeneratePhoneNumber(raw: string): boolean {
  if (RESERVED_FICTIONAL_NANP_PATTERN.test(raw)) return true;
  const digits = raw.replace(/\D/g, "");
  // All-identical or strictly ascending/descending runs are documentation filler.
  if (/^(\d)\1+$/.test(digits)) return true;
  if (digits.includes("1234567") || digits.includes("0000000")) return true;
  return false;
}

export function detectThirdPartyPhoneNumbers(blob: string): PiiFinding[] {
  const findings: PiiFinding[] = [];

  for (const match of blob.matchAll(E164_PHONE_PATTERN)) {
    const raw = match[0];
    if (isReservedOrDegeneratePhoneNumber(raw)) continue;
    findings.push({
      kind: "third-party-phone-number",
      line: lineNumberAtOffset(blob, match.index ?? 0),
      excerpt: `${raw.slice(0, 3)}…${raw.slice(-2)}`,
      rationale: "E.164-formatted telephone number outside the reserved fictional ranges",
    });
  }

  for (const match of blob.matchAll(NANP_PHONE_PATTERN)) {
    const raw = match[0];
    const start = match.index ?? 0;
    if (isReservedOrDegeneratePhoneNumber(raw)) continue;
    // Skip anything already reported by the E.164 pass (a `+1 604-555-…` overlap).
    if (start > 0 && /[+\d]/.test(blob[start - 1] ?? "")) continue;
    const context = neighbourhoodAround(
      blob,
      start,
      start + raw.length,
      PHONE_CONTEXT_RADIUS_CHARACTERS,
    );
    if (!PHONE_CONTEXT_PATTERN.test(context)) continue;
    findings.push({
      kind: "third-party-phone-number",
      line: lineNumberAtOffset(blob, start),
      excerpt: `${raw.slice(0, 3)}…${raw.slice(-2)}`,
      rationale: "NANP-formatted number beside a telephony cue, outside the 555-01xx range",
    });
  }

  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 6 — AWS 12-digit account IDs
// ══════════════════════════════════════════════════════════════════════════
//
//  ── The second incident (2026-08-29), which these three detectors exist for
//
//  An audit found that this repo's own PII-SCRUB COMMITS republished, verbatim
//  and publicly, every value they redacted: semantic-release turns commit
//  bodies into release prose, so a conscientious "removed X, Y, Z" message
//  became the leak, and the habit outlived the scrub by two releases.
//
//  Detectors 1–5 could not have caught it, because none of the leaked classes
//  is a credential and the leak was in a COMMIT MESSAGE, a surface no
//  Write/Edit hook ever sees. Detectors 6–8 cover the identifier classes that
//  actually leaked; the commit-message surface is covered by
//  `scripts/commit-message-exposure-guard.ts`.

/** Bare 12-digit run — an AWS account ID, but also a timestamp or an ID column. */
const TWELVE_DIGIT_RUN_PATTERN = /\b\d{12}\b/g;

/**
 * 12 digits alone is far too common to report, so an AWS cue is required
 * within ±80 characters. `arn:aws:` is included because an ARN embeds the
 * account ID as its fifth colon-separated field.
 */
const AWS_ACCOUNT_CONTEXT_PATTERN =
  /\b(?:aws|arn:aws|account[_\s-]?id|iam|sts|assume[_\s-]?role|organizations?|payer|root account)\b/i;

const AWS_ACCOUNT_CONTEXT_RADIUS_CHARACTERS = 80;

/** Runs like `000000000000` or `123456789012` are AWS's own doc examples. */
function isDocumentationFillerDigitRun(digits: string): boolean {
  if (/^(\d)\1+$/.test(digits)) return true;
  return digits === "123456789012" || digits === "210987654321";
}

export function detectAwsAccountIdentifiers(blob: string): PiiFinding[] {
  const findings: PiiFinding[] = [];
  for (const match of blob.matchAll(TWELVE_DIGIT_RUN_PATTERN)) {
    const digits = match[0];
    const start = match.index ?? 0;
    if (isDocumentationFillerDigitRun(digits)) continue;
    const context = neighbourhoodAround(
      blob,
      start,
      start + digits.length,
      AWS_ACCOUNT_CONTEXT_RADIUS_CHARACTERS,
    );
    if (!AWS_ACCOUNT_CONTEXT_PATTERN.test(context)) continue;
    findings.push({
      kind: "aws-account-id",
      line: lineNumberAtOffset(blob, start),
      excerpt: `${digits.slice(0, 2)}…${"*".repeat(8)}`,
      rationale:
        "12-digit run beside an AWS/ARN/IAM cue — identifies whose account, and both a company and a personal one leaked",
    });
  }
  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 7 — *.workers.dev hostnames carrying a client handle
// ══════════════════════════════════════════════════════════════════════════

/**
 * `<project>.<account-handle>.workers.dev` — Cloudflare's default Workers
 * hostname. The account handle is the client's, and the project label is
 * frequently a private deal or client name, so the hostname alone discloses
 * both the customer and the engagement. Exactly what leaked.
 */
const WORKERS_DEV_HOSTNAME_PATTERN = /\b([a-z0-9][a-z0-9.-]*)\.workers\.dev\b/gi;

/**
 * A generic label — `example`, `my-worker`, `<name>` — is documentation. Only a
 * label that looks like a real identifier is reported. A single label (bare
 * `foo.workers.dev`) is also skipped: it names no account, so it discloses
 * nothing about a third party.
 */
export function detectClientScopedWorkersDevHostnames(blob: string): PiiFinding[] {
  const findings: PiiFinding[] = [];
  for (const match of blob.matchAll(WORKERS_DEV_HOSTNAME_PATTERN)) {
    const labels = (match[1] ?? "").split(".").filter((label) => label !== "");
    if (labels.length < 2) continue;
    if (labels.some((label) => isPlaceholderSecretValue(label))) continue;
    if (labels.some((label) => /^(?:my|test|demo|hello|worker|app|site|foo|bar)$/i.test(label))) {
      continue;
    }
    findings.push({
      kind: "client-scoped-workers-dev-hostname",
      line: lineNumberAtOffset(blob, match.index ?? 0),
      excerpt: `${labels[0]?.slice(0, 2)}…….workers.dev`,
      rationale:
        "multi-label workers.dev hostname — the account label names the client and the project label often names the deal",
    });
  }
  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Detector 8 — 1Password / base32 vault item identifiers
// ══════════════════════════════════════════════════════════════════════════

/** 1Password item and vault IDs are 26 lowercase Crockford-ish base32 chars. */
const BASE32_ITEM_IDENTIFIER_PATTERN = /\b[a-z2-7]{26}\b/g;

const VAULT_ITEM_CONTEXT_PATTERN =
  /\b(?:1password|onepassword|op\s+item|op:\/\/|item[_\s-]?id|vault[_\s-]?id|uuid)\b/i;

const VAULT_ITEM_CONTEXT_RADIUS_CHARACTERS = 80;

export function detectVaultItemIdentifiers(blob: string): PiiFinding[] {
  const findings: PiiFinding[] = [];
  for (const match of blob.matchAll(BASE32_ITEM_IDENTIFIER_PATTERN)) {
    const identifier = match[0];
    const start = match.index ?? 0;
    if (isPlaceholderSecretValue(identifier)) continue;
    const context = neighbourhoodAround(
      blob,
      start,
      start + identifier.length,
      VAULT_ITEM_CONTEXT_RADIUS_CHARACTERS,
    );
    if (!VAULT_ITEM_CONTEXT_PATTERN.test(context)) continue;
    findings.push({
      kind: "vault-item-identifier",
      line: lineNumberAtOffset(blob, start),
      excerpt: redactSecretForTranscriptEcho(identifier),
      rationale:
        "26-char base32 identifier beside a 1Password/vault cue — inert alone, but it maps a public doc to a private vault entry",
    });
  }
  return findings;
}

// ══════════════════════════════════════════════════════════════════════════
//  Aggregators
// ══════════════════════════════════════════════════════════════════════════

/** All three high-confidence credential detectors. Feeds the blocking guard. */
export function detectCredentialExposure(blob: string): CredentialFinding[] {
  return [
    ...detectTelegramBotTokens(blob),
    ...detectPushoverStyleBareTokens(blob),
    ...detectProvisioningCommandLiteralValues(blob),
  ].toSorted((a, b) => a.line - b.line);
}

/** Both fuzzy PII detectors. Feeds the non-blocking reminder. */
export function detectThirdPartyPiiExposure(blob: string): PiiFinding[] {
  return [
    ...detectThirdPartyEmailAddresses(blob),
    ...detectThirdPartyPhoneNumbers(blob),
    ...detectAwsAccountIdentifiers(blob),
    ...detectClientScopedWorkersDevHostnames(blob),
    ...detectVaultItemIdentifiers(blob),
  ].toSorted((a, b) => a.line - b.line);
}

// ══════════════════════════════════════════════════════════════════════════
//  Message builders
// ══════════════════════════════════════════════════════════════════════════

/**
 * Exported so surfaces other than a file write (e.g. the commit-message guard)
 * can render findings in their own prose without re-deriving the vocabulary.
 */
export const CREDENTIAL_LABELS: Record<CredentialFindingKind, string> = {
  "telegram-bot-token": "Telegram bot token",
  "pushover-style-bare-token": "Pushover-style bare 30-char token",
  "provisioning-command-literal-value": "provisioning command with a literal secret",
};

export function buildCredentialDenyReason(
  filePath: string,
  findings: readonly CredentialFinding[],
): string {
  const lines = findings
    .slice(0, 5)
    .map((f) => `  • line ${f.line}: ${CREDENTIAL_LABELS[f.kind]} — ${f.excerpt} (${f.rationale})`);
  return [
    `BLOCKED: this write would put a live credential into ${filePath}.`,
    "",
    ...lines,
    findings.length > 5 ? `  • …and ${findings.length - 5} more` : "",
    "",
    "Every credential found in the 23-repo audit sat in an ADR / design spec / planning",
    "doc, pasted as a worked example of a provisioning command — often in a file that",
    "simultaneously said the secret lived in Doppler. docs/ is the dangerous directory.",
    "",
    "Fix: replace the value with a placeholder (`<telegram-bot-token>`), or reference the",
    "secret by name only. If the value was ever real, ROTATE IT — it is in your shell",
    "history and possibly in a git object already.",
    "",
    "Escape hatch: add `SECRET-SCAN-OK: <reason>` (reason ≥10 chars) to the file when the",
    "value is genuinely synthetic — e.g. a test fixture for this very guard.",
  ]
    .filter((line) => line !== "")
    .join("\n");
}

/** Exported for the same reason as `CREDENTIAL_LABELS`. */
export const PII_LABELS: Record<PiiFindingKind, string> = {
  "third-party-email": "email address",
  "third-party-phone-number": "phone number",
  "aws-account-id": "AWS account ID",
  "client-scoped-workers-dev-hostname": "client-scoped workers.dev hostname",
  "vault-item-identifier": "vault item identifier",
};

export function buildPiiReminder(filePath: string, findings: readonly PiiFinding[]): string {
  const lines = findings
    .slice(0, 5)
    .map((f) => `  • line ${f.line}: ${PII_LABELS[f.kind]} — ${f.excerpt}`);
  return [
    `Third-party personal data may have just been written to ${filePath}:`,
    ...lines,
    findings.length > 5 ? `  • …and ${findings.length - 5} more` : "",
    "",
    "A contact's real name, business email and phone were reintroduced into the published",
    "tree six days after an eleven-agent scrub of 2,602 files. A one-time sweep does not",
    "hold. If this repo is public, or is published to a marketplace, use a placeholder,",
    "example.com, or a 555-01xx number instead.",
    "",
    "This is a reminder, not a block. Suppress with a `PII-SCAN-OK` comment when the data",
    "is intentional (a public maintainer address, an RFC author, a quoted upstream doc).",
  ]
    .filter((line) => line !== "")
    .join("\n");
}
