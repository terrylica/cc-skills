/**
 * Detector SSoT for the AskUserQuestion option line-terminator guard.
 *
 * Pure and dependency-free (the shared iter-106 truncation helper is applied at the
 * emission site in the hook, not here) so the whole grammar is unit-testable without
 * spawning a hook process.
 *
 * NOTE TO EDITORS: never type a literal U+2028 / U+2029 into this file, and never spell
 * them as a backslash-u escape inside a regex literal either. They ARE line terminators:
 * a raw one ends the source line mid-token and the file stops parsing (measured while
 * writing this file — oxlint and biome both reported "unterminated regex literal"). Both
 * characters are therefore built with String.fromCharCode below, and every pattern that
 * needs them is compiled with `new RegExp`.
 *
 * WHAT IS WRONG UPSTREAM — https://github.com/anthropics/claude-code/issues/88836
 * Claude Code replaces every line terminator inside an AskUserQuestion option's
 * `description` and `label` with U+FFFD (the replacement character), so a two-paragraph
 * description renders as `...forever.<FFFD><FFFD>II. SHORT-TERM WIN:`. Measured in the
 * shipped binary (2.1.259, and still present in 2.1.260): a one-line function replacing
 * the class of LF / CR / U+2028 / U+2029 with U+FFFD, applied to `displayDescription` in
 * the option mapper and to each `option.label` in the option renderer.
 *
 * `question` and `preview` take newline-PRESERVING paths and are therefore NOT inspected
 * here — flagging them would be a pure false positive. The persisted tool input is clean
 * either way; this is a rendering defect only.
 *
 * CONDITION FOR DELETING THIS GUARD: when the installed Claude Code no longer maps line
 * terminators to U+FFFD on the option `description` / `label` path. Verify against a
 * specific build with
 *   LC_ALL=C grep -ac 'g,"[backslash]uFFFD")}' ~/.local/share/claude/versions/<version>
 * (spelling the escape literally); when that replacer is gone, delete this file, the
 * hook, its test, its hooks.json entry, its spoke, and the ASK-OPTION-NEWLINE-OK registry
 * entry. The guard has no value afterwards and must not be left behind as a no-op.
 */

/** Built by code point: writing either character literally would terminate this source line. */
const LINE_SEPARATOR_CHARACTER = String.fromCharCode(0x2028);
const PARAGRAPH_SEPARATOR_CHARACTER = String.fromCharCode(0x2029);

/** The exact four code points the upstream replacer mangles, with their Unicode names. */
const LINE_TERMINATOR_UNICODE_NAMES: ReadonlyArray<readonly [string, string]> = [
  ["\n", "U+000A LINE FEED"],
  ["\r", "U+000D CARRIAGE RETURN"],
  [LINE_SEPARATOR_CHARACTER, "U+2028 LINE SEPARATOR"],
  [PARAGRAPH_SEPARATOR_CHARACTER, "U+2029 PARAGRAPH SEPARATOR"],
];

/** Same character class as the upstream replacer — deliberately identical, not broader. */
const LINE_TERMINATOR_PATTERN = new RegExp(
  `[\n\r${LINE_SEPARATOR_CHARACTER}${PARAGRAPH_SEPARATOR_CHARACTER}]`,
);

/** The two option fields that get mangled. `question` and `preview` render newlines correctly. */
export const INSPECTED_OPTION_FIELDS = ["label", "description"] as const;
export type InspectedOptionField = (typeof INSPECTED_OPTION_FIELDS)[number];

export interface LineTerminatorFinding {
  /** Zero-based, matching the tool input's own array indexing. */
  readonly questionIndex: number;
  /** Zero-based, matching the tool input's own array indexing. */
  readonly optionIndex: number;
  readonly field: InspectedOptionField;
  /** Every distinct terminator present in that field, e.g. `["U+000A LINE FEED"]`. */
  readonly codepoints: readonly string[];
  /** The field's own text with terminators made visible, capped for the deny reason. */
  readonly sample: string;
}

/** How much of an offending field to echo back: long enough to locate, short enough to skim. */
const SAMPLE_CHARACTER_BUDGET = 160;

/** Render terminators as visible escapes, so the deny reason itself never contains one. */
function renderSample(text: string): string {
  const escaped = text
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n")
    .replace(new RegExp(LINE_SEPARATOR_CHARACTER, "g"), "\\u2028")
    .replace(new RegExp(PARAGRAPH_SEPARATOR_CHARACTER, "g"), "\\u2029");
  return escaped.length <= SAMPLE_CHARACTER_BUDGET
    ? escaped
    : `${escaped.slice(0, SAMPLE_CHARACTER_BUDGET)}…`;
}

function codepointsPresentIn(text: string): string[] {
  return LINE_TERMINATOR_UNICODE_NAMES.filter(([char]) => text.includes(char)).map(
    ([, name]) => name,
  );
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Find every option `label` / `description` carrying a line terminator.
 *
 * Shape-tolerant by design: anything that is not the expected object/array/string shape
 * is SKIPPED rather than treated as a finding. A guard that denied on an unfamiliar
 * payload would block the user's own question UI over a schema change, which is strictly
 * worse than the cosmetic defect it exists to prevent.
 */
export function detectOptionLineTerminators(toolInput: unknown): LineTerminatorFinding[] {
  const findings: LineTerminatorFinding[] = [];
  if (!isPlainObject(toolInput)) return findings;

  const questions = toolInput.questions;
  if (!Array.isArray(questions)) return findings;

  questions.forEach((question, questionIndex) => {
    if (!isPlainObject(question)) return;
    const options = question.options;
    if (!Array.isArray(options)) return;

    options.forEach((option, optionIndex) => {
      if (!isPlainObject(option)) return;
      for (const field of INSPECTED_OPTION_FIELDS) {
        const value = option[field];
        if (typeof value !== "string") continue;
        if (!LINE_TERMINATOR_PATTERN.test(value)) continue;
        findings.push({
          questionIndex,
          optionIndex,
          field,
          codepoints: codepointsPresentIn(value),
          sample: renderSample(value),
        });
      }
    });
  });

  return findings;
}

/** `questions[0].options[1].description` — the exact path the model can edit. */
export function findingPath(finding: LineTerminatorFinding): string {
  return `questions[${finding.questionIndex}].options[${finding.optionIndex}].${finding.field}`;
}

/** The separator that replaces a line break: space, em dash, space. */
export const REPLACEMENT_SEPARATOR = " — ";

/** Escape-hatch marker token; registered in the iter-111 canonical registry. */
export const ESCAPE_HATCH_MARKER_TOKEN = "ASK-OPTION-NEWLINE-OK";

/**
 * Where the deny message points instead of naming the marker. See the comment on
 * `buildLineTerminatorDenyMessage` for why the token must never appear in that message.
 */
const ESCAPE_HATCH_SPOKE_PATH =
  "plugins/itp-hooks/docs/askuserquestion-option-line-terminator-guard.md";

/**
 * The deny message MUST NOT contain ESCAPE_HATCH_MARKER_TOKEN.
 *
 * The marker is matched against the whole serialized tool input, and this message is
 * handed back to the model at precisely the moment it is about to re-emit that call. If
 * the message named the token, a retry that quoted the guard's own words back into the
 * `question` field would carry the marker and permanently disarm the guard for that call —
 * the guard would talk itself out of existence.
 *
 * This is the same containment the user-memory hub applies to the hard-wrap reminder,
 * which keeps its token in the hook and the spoke and deliberately out of the
 * always-loaded file that would otherwise silence it everywhere. So: say that an escape
 * hatch exists, say where it is documented, never spell it. A test asserts the absence.
 */
export function buildLineTerminatorDenyMessage(
  findings: readonly LineTerminatorFinding[],
): string {
  const lines: string[] = [
    "[ASKUSERQUESTION-OPTION-NEWLINE-GUARD] Line terminator in an option field Claude Code cannot render.",
    "",
    'Claude Code replaces every line terminator (LF, CR, U+2028, U+2029) inside an option `label` or `description` with U+FFFD, so the option renders as "...forever.<FFFD><FFFD>II. SHORT-TERM WIN:" instead of breaking. Upstream regression anthropics/claude-code#88836, introduced in 2.1.235 and still open.',
    "",
    `${findings.length} offending field${findings.length === 1 ? "" : "s"}:`,
  ];

  for (const finding of findings) {
    lines.push(`  - ${findingPath(finding)} — contains ${finding.codepoints.join(", ")}`);
    lines.push(`      ${finding.sample}`);
  }

  lines.push(
    "",
    `FIX: re-send the same AskUserQuestion call with every line break in those fields replaced by "${REPLACEMENT_SEPARATOR}" (space, em dash, space). Do not drop the content — join the parts.`,
    "",
    "`question` and `preview` are unaffected and were not inspected — genuinely multi-line material belongs there, or in an ordinary message before the question.",
    "",
    `Escape hatch: a documented marker exists for the rare case where a literal line break is genuinely wanted despite the mangling. It is named in ${ESCAPE_HATCH_SPOKE_PATH} and in this guard's source, and is deliberately NOT spelled in this message — the marker is matched against the whole tool input, so quoting this text back into your next call would silence the guard instead of fixing the option.`,
  );

  return lines.join("\n");
}
