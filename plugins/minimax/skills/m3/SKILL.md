---
name: m3
description: Production wiring for the MiniMax-M3 model — empirically verified flags, capabilities, and limits (thinking control via reasoning_split, native vision, response_format, 512K input ceiling, 512K output cap, n=1, docs-vs-reality discrepancies). Use when wiring or tuning MiniMax-M3, choosing M3 vs M2.7/-highspeed, switching a service off M2.7-highspeed onto M3, getting clean output without <think>, or asking what M3 supports / how big its context is. TRIGGERS - MiniMax M3, MiniMax-M3, M3 model, switch to M3, reasoning_split, M3 context length, M3 vision, M3 options, get the most out of M3.
---

# MiniMax-M3 — Production Wiring (empirical)

The M3 companion to [`../minimax/SKILL.md`](../minimax/SKILL.md) (M2.7). Every claim here was
**live-probed 2026-06-01** on the Plus-High-Speed key. Full evidence + copy-paste snippets:
[`../../references/M3-EMPIRICAL.md`](../../references/M3-EMPIRICAL.md).

> **Self-Evolving Skill**: improves through use. If a flag stopped working, a limit moved, or
> the docs caught up with reality — fix this file + `references/M3-EMPIRICAL.md` immediately,
> don't defer. Re-verify with the scripts below before changing a documented fact.

---

## The one rule: default to `reasoning_split: true`

M3 still emits `<think>…</think>` inside `content` **by default** (same footgun as M2.7).
Setting `reasoning_split: true` moves the reasoning into a separate `reasoning_content` /
`reasoning_details` field and leaves `content` **clean** — no regex stripping. This is the
chosen default profile for everything migrating off M2.7-highspeed.

```python
body = {
    "model": "MiniMax-M3",
    "messages": messages,
    "max_tokens": 4096,          # >= 1024 — thinking consumes budget before visible content
    "temperature": 0.2,
    "reasoning_split": True,     # clean content; reasoning in reasoning_content/_details
}
answer = resp["choices"][0]["message"]["content"]   # already clean — display directly
```

Need M2.7-highspeed-class **speed** on short/simple tasks? Add `"reasoning": "disabled"`
(≈2× fewer tokens, ≈2× faster) — and keep the M2.7 `<think>` strip as a safety net, since
`"disabled"` shortens but doesn't always remove the block. Keep thinking ON (default /
`"adaptive"`) for hard reasoning, coding, and agentic loops.

---

## When to use M3 vs M2.7

| Workload                                          | Verdict                                                                  |
| ------------------------------------------------- | ------------------------------------------------------------------------ |
| Clean chat / judgment / theory / JSON             | ✅ M3 + `reasoning_split:true` (the new default)                         |
| Short tagging / classification, latency-sensitive | ✅ M3 + `reasoning:"disabled"`, **or** stay on plain `MiniMax-M2.7`      |
| **Vision** (OCR, charts, screenshots)             | ✅ **M3 only** — M2.7 is text-only; M3 reads images correctly            |
| Structured JSON                                   | ✅ M3 (`response_format` accepted) + `reasoning_split` + defensive parse |
| Long context up to ~500K tokens                   | ✅ M3 (retrieval verified at 128K/400K); **keep ≤ 512K — hard cap**      |
| Raw math / QP / risk on realistic N               | ❌ still route to Python (the M2.7 saturation guidance carries over)     |
| Final deployable code                             | ⚠️ scaffold-only; sandbox-validate (unchanged from M2.7)                 |

---

## Hard limits & gotchas (live-verified)

- **Input context ≈ 512K tokens (hard cap).** 512,180 accepted; 575K+ → `400`. Docs claim 1M —
  **not on this key.** Operate at ≤ 512K input.
- **Output `max_tokens` ≤ 512,000.** > 512000 → `2013`.
- **`n > 1` rejected** (`2013`). One choice per call.
- **`response_format` accepted but not a hard JSON guarantee** — M3 may still wrap with `<think>`
  / ` ```json ` fences / a trailing note. Pair with `reasoning_split` + try/except `json.loads`.
- **`tool_choice` forced did NOT compel a call** in the trivial-prompt probe — re-test with a
  tool-relevant prompt before relying on forced tool calls.
- **No `MiniMax-M3-highspeed`** on this key (`2013 unknown model`) despite docs.
- All the M2.7 defensive snippets (`<think>` strip, `base_resp` rate-limit retry, cached-token
  reader) in [`../minimax/SKILL.md`](../minimax/SKILL.md) apply unchanged.

---

## Re-verify / detect drift

Scripts live at the plugin **source** checkout (`scripts/` is stripped from the runtime cache),
run from `~/eon/cc-skills/plugins/minimax`:

```bash
export MINIMAX_API_KEY=...        # or rely on the 1Password op-path default (see m3-verify -h)

./scripts/m3-verify                                                   # fast drift check vs locked snapshot (0/1/2)
uv run --python 3.14 --with requests,pillow python scripts/m3-probe.py        # full option/capability map
uv run --python 3.14 --with requests        python scripts/m3-context-probe.py # ceiling + needle retrieval
uv run --python 3.14 --with requests        python scripts/m3-bench.py         # speed/quality vs M2.7/-highspeed
./scripts/minimax-check-upgrade                                       # catalog drift (lock now includes MiniMax-M3)
```

Locked invariants: [`../../references/fixtures/m3-capabilities-locked-2026-06-01.json`](../../references/fixtures/m3-capabilities-locked-2026-06-01.json).
Schedule `m3-verify` + `minimax-check-upgrade` (launchd template in `templates/`) to catch the
day MiniMax ships `M3-highspeed`, opens up 1M context, or changes a limit.

## Post-Execution Reflection

0. **Locate yourself.** — Confirm this is the canonical `skills/m3/SKILL.md` before editing.
1. **What failed?** — A flag that worked now errors, or vice-versa → fix here + M3-EMPIRICAL.md.
2. **What drifted?** — `m3-verify` flagged an invariant change → review, then bump the locked snapshot.
3. **Log it.** — Append to the Evolution log in `references/M3-EMPIRICAL.md` with trigger + fix + evidence.
