---
name: glm
description: Manually consult GLM-5.2 (Z.ai) via the `zai` CLI — fast by default, `--deep` for reasoning. The user-invoked `/zai:glm` surface; complementary to Claude, never a replacement. For autonomous cross-checks use the `ask-glm` skill instead.
argument-hint: "[--deep] [--effort max] [--file PATH] <question>"
allowed-tools: Bash
disable-model-invocation: true
---

# glm — manual GLM-5.2 consult (`/zai:glm`)

Run the `zai` CLI to consult GLM-5.2 with the user's arguments, then relay the answer
(note it's GLM's, not Claude's).

```bash
zai chat $ARGUMENTS
```

- If the user passed `--deep`/`--effort`, keep them (extended reasoning). Otherwise it runs fast.
- For a big document, they can pass `--file <path>` (GLM-5.2 accepts ~1M input tokens).
- For web research, use `zai websearch "<query>"` / `zai read <url>` instead.
- Full capability surface: the `zai` plugin's [`references/CAPABILITIES.md`](../../references/CAPABILITIES.md).

> This is the **manual** surface (`disable-model-invocation: true`) — it fires only when the
> user types `/zai:glm`. When Claude should consult GLM on its own initiative, that's the
> `ask-glm` skill, not this one.
