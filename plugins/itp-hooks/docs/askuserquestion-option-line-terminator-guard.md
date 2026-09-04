# AskUserQuestion option line-terminator guard

- **Hook**: `pretooluse-askuserquestion-option-line-terminator-guard.ts` (PreToolUse, matcher `AskUserQuestion` — the first hook in this plugin to match that tool)
- **Detector SSoT**: `hooks/lib/askuserquestion-option-line-terminator-detector.ts` (pure, dependency-free)
- **Shared libs consumed**: `hooks/lib/shared-escape-hatch-marker-detection-helper-…-iter107.ts` (marker), `hooks/lib/shared-truncation-helper-…-iter106.ts` (deny-reason cap)
- **Tests**: `hooks/pretooluse-askuserquestion-option-line-terminator-guard.test.ts` (16 bun tests)
- **Escape hatch**: `ASK-OPTION-NEWLINE-OK` anywhere in the tool input — named here and in the hook source, never in the deny message (see "Why the deny message does not name the escape hatch")
- **Timeout**: `5` in `hooks.json`. That field is **seconds**, not milliseconds — the shipped binary computes `hook.timeout * 1000` at 15 call sites and its embedded zod schema describes the field as "Timeout in seconds for this specific command" (re-verified against 2.1.260). A four-digit value here would park the interactive question dialog for over an hour, and the timeout is the only backstop against a hang because the hook's top-level `catch` only covers a throw.
- **Upstream**: [anthropics/claude-code#88836](https://github.com/anthropics/claude-code/issues/88836) — open regression, introduced in 2.1.235

## Why it exists

Claude Code replaces every line terminator inside an AskUserQuestion option's `description` and `label` with U+FFFD before rendering, so a description written as two paragraphs reaches the user as `...forever.<FFFD><FFFD>II. SHORT-TERM WIN:`. The persisted tool input is clean — this is purely a rendering defect, and the model has no way to see the mangling it just caused.

Measured in the shipped binary at `~/.local/share/claude/versions/`: a one-line function replaces the class of LF, CR, U+2028 and U+2029 with U+FFFD, and it is applied to `displayDescription` in the option mapper and to each `option.label` in the option renderer. Present in 2.1.259 and re-measured still present in 2.1.260 (same function body, renamed by the minifier), which is the evidence that upstream has not quietly fixed it.

`question` and `preview` take newline-preserving paths and are therefore **not** inspected. Flagging them would be a pure false positive.

## What it inspects

Only `questions[i].options[j].label` and `questions[i].options[j].description`, and only when the value is a string. Everything else — a missing `questions` array, a non-object option, a numeric description — is **skipped**, never flagged.

## Detection

`detectOptionLineTerminators` walks the questions/options arrays and tests each inspected field against the same character class the upstream replacer uses (LF, CR, U+2028, U+2029) — deliberately identical, not broader. Each finding carries the zero-based question and option indices, the field name, every distinct terminator present (by Unicode name), and an escaped, length-capped sample of the field's own text.

The deny reason names the array path the model must edit (`questions[0].options[1].description`), the code point found, and the single fix: replace each break with `" — "` (space, em dash, space), joining the parts rather than dropping content. Terminators in the sample are rendered as visible escapes, so the deny reason can never itself carry one.

## PreToolUse dispatch to AskUserQuestion is confirmed — do not re-open this

Claude Code **does** dispatch PreToolUse hooks for the `AskUserQuestion` tool. Measured empirically, not inferred from the binary: a probe hook was registered in a local settings file with an `AskUserQuestion` matcher plus a `Bash` matcher as a control, a real AskUserQuestion was then issued, and the probe log recorded `PreToolUse AskUserQuestion` alongside the Bash control lines; settings hot-reloaded with no restart and no approval prompt. So this guard is not a no-op. The `var Ad = new Set([…, "AskUserQuestion", …])` inside `jn()` that looks like an exclusion list is permission-rule partitioning, not hook dispatch — a red herring, already chased and discarded.

## Why the deny message does not name the escape hatch

The marker is matched against the **whole serialized tool input**, and the deny message is handed to the model at exactly the moment it is about to re-emit that call. A message that spelled the token would let a retry which quotes the guard's own words into the `question` field carry the marker and permanently disarm the guard for that call — the guard would talk itself out of existence. So the message states that a documented escape hatch exists and points at this spoke, and the token itself lives only in the hook source, the detector, this spoke and the marker registry. This is the same containment the user-memory hub applies to the hard-wrap reminder, whose token is deliberately kept out of the always-loaded file that would otherwise silence it everywhere. Two tests hold the line: one asserts the built message does not contain the token, and one feeds the guard its own deny reason back as the question text and asserts it still denies.

## Why it denies instead of repairing

`hooks/lib/tool-schemas.ts` deliberately registers no schema for AskUserQuestion — its `StrictSchema` supports neither nested objects nor arrays of objects, and a tool absent from that registry cannot receive `updatedInput`. That is the safe default (a hook must not rewrite a payload it does not fully model), and a test asserts the absence. So this guard hands the call back with instructions rather than auto-fixing it, and **must not** be "improved" by widening that registry.

## Output & failure model

- On detection → PreToolUse **`deny`** with an `[ASKUSERQUESTION-OPTION-NEWLINE-GUARD]` reason, wrapped in the iter-106 truncation helper.
- **Fail-open everywhere**: unparseable stdin, an unexpected payload shape, or any thrown error → `allow`, via `trackHookError` + `allow()` in the top-level `catch`. A guard that crashes must never block the user's own question UI.
- Escape hatch is matched against the **serialized tool input**, not a file — AskUserQuestion carries no command string, so the marker is honored wherever the model puts it.

## Condition for removal

Delete the hook, the detector, the test, the `hooks.json` entry, the registry entry, the audit-cohort member and this spoke as soon as the installed Claude Code no longer maps line terminators to U+FFFD on the option `label` / `description` path. Verify by grepping the version binary for the replacer described above; when it is gone the guard has no value, and leaving it behind as a no-op is worse than removing it.

## Honest scope note

The harm is cosmetic and the measured base rate is low — a scan of 389 historical AskUserQuestion calls found only 4 with a newline in an option description, all within one 28-hour window. The guard is cheap, narrow and fail-open, but it is a workaround for someone else's bug with an explicit expiry condition, not a lasting invariant of this repo.

## Related

- Deny/allow/`parseStdinOrAllow`/fail-open structure mirrors [gmail-body-guard](./gmail-body-guard.md), which solves the sibling problem on the outbound-email surface.
- The wider "which surface renders a newline how" split is catalogued in [markdown-hard-wrap-reminder](./markdown-hard-wrap-reminder.md).
