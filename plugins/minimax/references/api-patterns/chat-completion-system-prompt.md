# Chat Completion — System Prompt Behavior

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/chat-completion-system-prompt.md` (source-of-truth — read-only, source iter-3). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-8).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. Tests two requests with identical user message but with/without a system message; compares output, reasoning, latency, and token accounting.

## Test setup

| Variant          | System message                                                                                           | User message                       |
| ---------------- | -------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| E1 (with system) | `"You are a pirate from the 1700s. Every response uses pirate vocabulary (Arr, Aye, ye, lubber, etc.)."` | `"What is the capital of France?"` |
| E2 (no system)   | (omitted)                                                                                                | `"What is the capital of France?"` |

`max_tokens: 512` in both. Default temperature/top_p.

## Results

| Metric              | E1 (with system) | E2 (no system) | Δ                                                          |
| ------------------- | ---------------- | -------------- | ---------------------------------------------------------- |
| HTTP status         | 200              | 200            | —                                                          |
| Latency             | 2.98s            | 1.79s          | +1.2s with system                                          |
| `prompt_tokens`     | 50               | 48             | **+2 only** ⚠️ (system message ~25 tokens by visual count) |
| `completion_tokens` | 101              | 46             | +55                                                        |
| `reasoning_tokens`  | 67               | 38             | +29 (system prompt causes more reasoning)                  |
| `finish_reason`     | "stop"           | "stop"         | —                                                          |

### Visible outputs (after `<think>` stripping)

E1: `"Arr, ye landlubber be askin' a simple one! The capital of France be **Paris**, ye scurvy dog! 🏴‍☠️"`

E2: `"The capital of France is **Paris**."`

## Finding 1: System prompt IS strongly honored

Persona fully takes effect — pirate voice, pirate vocabulary ("Arr", "ye", "landlubber", "scurvy dog"), period emoji (🏴‍☠️). MiniMax does not weakly-apply the persona; it commits to the role consistently. Same persona-honoring strength as OpenAI's behavior.

## Finding 2: System prompt causes ~75% more reasoning tokens

E1 used 67 reasoning tokens; E2 used 38. The model spends extra reasoning on **how to phrase** under the persona constraint, not just **what to say**. Visible from the `<think>` trace:

> "The user is asking a simple factual question about the capital of France. I need to respond as a pirate from the 1700s, using pirate vocabulary like 'Arr,' 'Aye,' 'ye,' 'lubber,' etc."

Practical implication: persona-heavy prompts should budget more `max_tokens` than plain factual prompts. For Karakeep/Linkwarden tagging where we want crisp output, **avoid persona system prompts** — use direct instructional system prompts instead.

## Finding 3: ⚠️ prompt_tokens accounting anomaly (system messages may be discount-billed)

This is unexpected and worth investigating further. The system message contains roughly 25 tokens of content (counted manually), but `prompt_tokens` only increased by 2 (50 vs 48). Possibilities:

- **MiniMax has an implicit baseline system prompt** that's being REPLACED (not added to) by the explicit one — so the net token change is just the difference between baseline and custom
- **System messages are tokenized differently** — e.g., compressed or partially-discounted at the API boundary
- **User message tokenization is non-deterministic** — same user content tokenized to a different number of tokens in each request (unlikely but possible)

**Promote to T3.x for follow-up**: send a deliberately-long system prompt (e.g., 500 tokens) and observe how `prompt_tokens` scales. If it doesn't scale proportionally, MiniMax has a non-standard billing model for system messages worth documenting prominently.

Until verified, **don't assume system messages are billed at OpenAI-standard rates**.

## Finding 4: Default formatting is Markdown + emoji

Both responses used `**Paris**` (Markdown bold). The persona response added 🏴‍☠️ pirate emoji unprompted. So MiniMax defaults:

- **Markdown bold/italic for emphasis** even without instruction
- **Decorative emoji** when persona/style allows

For services that need plain text output (e.g., terminal clients, plain-text logs):

```yaml
system: "Output plain text only. No Markdown formatting. No emoji."
```

## Idiomatic wiring patterns by use case

### Tagging (Karakeep / Linkwarden style)

```json
{
  "model": "MiniMax-M2.7-highspeed",
  "messages": [
    {
      "role": "system",
      "content": "You generate concise tags for bookmarked content. Output exactly 3-5 single-word tags, lowercase, comma-separated. No explanations, no Markdown."
    },
    { "role": "user", "content": "<page content here>" }
  ],
  "max_tokens": 512
}
```

The "no explanations, no Markdown" line is critical to suppress MiniMax's default formatting habit.

### Summarization

```json
{
  "messages": [
    {
      "role": "system",
      "content": "You produce 2-sentence summaries. Plain text. No formatting."
    },
    { "role": "user", "content": "<long text>" }
  ],
  "max_tokens": 1024
}
```

### Persona / chat assistant

```json
{
  "messages": [
    { "role": "system", "content": "You are <persona>. Stay in character." },
    { "role": "user", "content": "<question>" }
  ],
  "max_tokens": 2048
}
```

Budget HIGHER `max_tokens` for personas — Finding 2 showed reasoning ~doubles.

## Provenance

| Probe            | trace-id     | Latency | Tokens (prompt+completion) |
| ---------------- | ------------ | ------- | -------------------------- |
| E1 (with system) | (in fixture) | 2.984s  | 50+101                     |
| E2 (no system)   | (in fixture) | 1.791s  | 48+46                      |

Fixtures:

- [`fixtures/chat-completion-system-prompt-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-system-prompt-2026-04-28.json)
- [`fixtures/chat-completion-no-system-2026-04-28.json`](~/own/amonic/minimax/api-patterns/fixtures/chat-completion-no-system-2026-04-28.json)

Verifier: autonomous-loop iter-3.
