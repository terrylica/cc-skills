# Using `claude -p` (headless) correctly — the SSoT

> **This file is the single source of truth.** Everything else — the `~/.claude` hub, per-repo
> `CLAUDE.md` files, and the `headless-claude-p-guard` PreToolUse hook — points HERE and holds no
> duplicate content. If a fact below changes, this is the only file to edit.

Every claim here was **measured on 2026-07-31** against Claude Code CLI **2.1.220** through the
`ccmax-claude` fleet wrapper (`ANTHROPIC_BASE_URL=https://nca.25u.com`), not read off a docs page and
assumed. Where a claim is unverified or path-specific, it says so.

The investigation that produced this cost most of a day, and every wrong turn in it came from the same
place: **reading a tool's silence as an answer.** That is the meta-lesson; the table of facts is the
artifact.

---

## The six things that will bite you

### 1. Omitting `--effort` is NOT "no reasoning" — it is `high`

Anthropic's CLI reference documents `--effort` as defaulting to **`high` on every model that supports
effort**. So a bare `claude -p "..."` is an extended-thinking call at high depth, billed accordingly.

Verified on the real path with `--output-format stream-json --verbose --include-partial-messages`,
identical reasoning-heavy prompt:

| invocation     | `content_block: thinking` | output tokens |
| -------------- | ------------------------- | ------------: |
| `--effort low` | present                   |            52 |
| **no flag**    | present                   |       **196** |
| `--effort max` | present                   |           373 |

Monotonic, ~7×. If you are doing bulk structured extraction and never set `--effort`, you are paying
for `high` reasoning on every call and have never decided to.

### 2. An invalid `--effort` value is accepted SILENTLY

`--effort bogus-level` → **exit 0**, normal answer. There is no enum validation on this path, so a typo
(`--effort hight`) does not fail — it quietly runs at the default. **Never assume an effort level
applied because the command succeeded.** Confirm via output tokens on a reasoning-heavy prompt.

### 3. `CLAUDE_EFFORT` the environment variable does nothing

It appears in no shell init, no `settings.json` schema, and no `--help` output. Measured across 8 calls
(4 `low` / 4 `xhigh`): no separation (883.5 ± 81.8 vs 834.2 ± 126.9, Welch p ≈ 0.53).

**Only the `--effort` FLAG works.** An env var and a flag are not the same knob. Conflating them
produced a confidently wrong conclusion ("effort is inert on this path") that survived two review passes
before the flag was tested directly.

### 4. `--output-format stream-json` emits NOTHING in `-p` without `--verbose`

```
Error: When using --print, --output-format=stream-json requires --verbose
```

The error goes to **stderr**. A probe that captures only stdout sees an empty stream and — if you are
not careful — reports "no thinking blocks found", which is a false negative, not a finding.
**A zero-line capture is a broken probe, never a negative result.**

### 5. High effort can trip a ~300 s STREAM IDLE TIMEOUT and return zero output

The most damaging failure found, because it looks like a model limitation and is not.

On a dense ~27 k-token prompt, `claude-sonnet-5 --effort max` thinks **silently** — emitting no stream
chunks — long enough that the client's stream-idle timeout fires. Reproduced twice, deterministically:

```
exit code   1
stdout      { "type":"result", "is_error":true, "stop_reason":"stop_sequence",
              "result":"API Error: Stream idle timeout - no chunks received",
              "duration_ms":302975, "usage":{"output_tokens":0} }
stderr      <fleet-identity banner only>
```

**Your own request timeout does not protect you.** That call had a 900 s budget and died at ~303 s: the
idle timer counts _silence between chunks_, not total duration. Raising `timeoutMs` changes nothing.

Consequences worth internalising:

- **`--effort max` is not safe for bulk work on large prompts.** The same pipeline succeeded at
  `--effort low` in ~29 s/call. Higher effort is not simply "slower" — past a threshold it returns
  **nothing at all**.
- **The failure is content-dependent, so it hides.** Sparse prompts answer fast and pass; dense ones
  think longer and die. In one 4-window extraction the two intake windows succeeded (legitimately
  charting nothing) while the two content-dense windows timed out — so the run produced a
  _complete, valid, empty_ result instead of an error.
- **On a non-zero exit the cause is in STDOUT, not stderr.** stderr holds only the banner. Any handler
  that reports stderr on failure discards the real message. Read stdout's `result` field.

### 6. Thinking _existence_ is observable; thinking _content_ is not

Blocks arrive as `{type:"thinking", thinking:"", signature:"<~1680 chars>"}`, and there are **no
`thinking_delta` events**. You can prove _that_ the model reasoned. You cannot read _what_ it reasoned.
Any plan that depends on inspecting the reasoning text does not work here.

---

## The ~59,300-token preamble

Every headless call carries a large system prefix before your prompt is reached. Measured with a
~5-token user prompt:

```
cache_creation 25,808  +  cache_read 33,535  +  input 2   =  59,345 tokens
```

Identical from three unrelated temp cwds, so it is **user-level** (the Claude Code harness plus
`~/.claude/CLAUDE.md`), not project memory. A call made from a `mktemp -d` cwd does **not** load a
project's `CLAUDE.md`, but still pays this.

**Consequence for anyone using `-p` as a plain LLM call:** your instructions are a minority of the
model's context. In the project-a extractor, a 17,499-token client prompt was **23%** of what the
model saw; the rest was coding-agent harness and unrelated policy (Python version rules, TypeScript
rules, git worktree doctrine).

### What does NOT remove it (all measured)

| attempt                                    | result                                                                                                                                                               |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--system-prompt "<text>"`                 | prefix **+98** tokens, sentinel instruction **not obeyed** — reaches the request but neither replaces the harness nor takes effect                                   |
| `--append-system-prompt "<text>"`          | prefix **unchanged**, sentinel **not obeyed** — no observable effect                                                                                                 |
| `--exclude-dynamic-system-prompt-sections` | prefix went **UP** (60,275 vs 59,343). It _relocates_ per-machine sections into the first user message for cache reuse, as documented — it does not shrink the total |
| `--allowedTools ""`                        | already in use; does not remove the preamble                                                                                                                         |

Sentinel method: user prompt `What is 2+2?`, system prompt `Begin every reply with the word ARRR.` —
non-conflicting, so compliance is unambiguous. Reply was a bare `4` in every arm.

> **If you need a clean system prompt, `claude -p` is the wrong tool.** Use the Anthropic Messages API
> directly (`anthropic` SDK), where `system` is exactly what you set and `response_format` /
> structured outputs are available. `-p` is an agent harness, not a thin LLM shim.

---

## Is this the wrapper's fault? No — and here is the discriminator

It is tempting to blame `ccmax-claude` for the flags that do nothing. **One test settles it:**

```bash
ccmax-claude -p "hi" --output-format json --model claude-opus-5 --zzz-not-a-real-flag
#   exit 1  -> argv IS forwarded; claude's own parser rejected the unknown flag
#   exit 0  -> the wrapper filters argv against an allowlist
```

Measured: **exit 1.** The wrapper forwards argv. So `--system-prompt` not taking effect is behaviour of
`claude`/the fleet on this path, **not** the wrapper swallowing it.

This matters because the two diagnoses are bugs against different projects. An earlier revision of this
investigation asserted "ccmax silently drops `--system-prompt`" on the strength of one confounded
sentinel test (the user prompt said "Say OK." while the system prompt said "reply BANANA" — two
CONFLICTING instructions, so obedience to the user was an ordinary explanation). **Run the
discriminator before filing anything.**

---

## Recipes

```bash
# Cheap, shallow — bulk classification/extraction where you do NOT want high reasoning
claude -p "$PROMPT" --output-format json --model claude-opus-5 --allowedTools "" --effort low

# Deep — when the task genuinely needs reasoning (and you accept ~7x the output tokens)
claude -p "$PROMPT" --output-format json --model claude-opus-5 --allowedTools "" --effort max

# Prove whether it thought at all (NOTE: --verbose is mandatory with stream-json under -p)
claude -p "$PROMPT" --output-format stream-json --verbose --include-partial-messages \
  --model claude-opus-5 --allowedTools "" | grep -c '"type":"thinking"'

# Confirm an effort level actually applied (a bad value exits 0 and runs at the default)
for e in low max; do
  claude -p "$HARD_REASONING_PROMPT" --output-format json --model claude-opus-5 \
    --allowedTools "" --effort "$e" | jq ".usage.output_tokens"
done   # expect a large, monotonic gap; no gap => it did not apply
```

### Probing gotchas that cost real time here

- **Never pipe `ccmax-claude` straight into a parser.** The wrapper signals its **process group** on
  exit and the downstream process dies with `Killed: 9`, which is indistinguishable from a parse
  failure. Capture stdout into a variable first, then parse.
- **Keep stdout and stderr separate.** The wrapper prints a banner (containing `{`) to stderr; a
  `2>&1` capture plus a "first `{`" heuristic parses the banner, not the result.
- **Don't inline the parser as `python3 -c '...'`** inside a single-quoted shell string — `\"` reaches
  Python as a literal backslash-quote and raises `SyntaxError`, which `2>/dev/null` then hides. Put it
  in a `.py` file.
- **Don't `set -e` inside a probe helper function.** It enables errexit for the whole script from that
  point, so the first expected non-zero exit kills the run.

---

## What is still unknown

- Whether extended thinking would be **forwarded by the doorward proxy** if requested through the raw
  Messages API. Direct probes return `INVALID_API_KEY`: the key is doorward-scoped and the router
  rejects non-Claude-Code-shaped requests (`request_fidelity_violation`). Everything above had to be
  established through the CLI.
- The **raw `claude` binary** cannot be tested standalone here — it returns `401 Invalid API key`
  because auth flows through the wrapper's fleet rotation.
- Whether `--system-prompt` behaves differently **off** the fleet (first-party key, no proxy). Untested.
- The `--system-prompt` "+98 tokens but no effect" result is from **one** sentinel. It is enough to say
  "does not take effect", not enough to say precisely where it goes.

---

## Enforcement

`hooks/pretooluse-headless-claude-p-guard.ts` hard-blocks only **provably broken** invocations — the
ones that cannot do what the author intends:

| blocked                                                        | why it is provable                                                          |
| -------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `-p` + `--output-format stream-json` without `--verbose`       | the CLI refuses and emits nothing; the command cannot ever produce a stream |
| `CLAUDE_EFFORT=<x>` prefixed on a `claude`/`ccmax-claude` call | the variable is not an input; it reads as reasoning control and is a no-op  |
| `--effort <value not in the enum>`                             | silently ignored, so the author's intent is silently discarded              |

Escape hatch: add `HEADLESS-P-OK` to the command. Everything else — including calling without
`--effort` — is allowed without comment, because it is often correct.
