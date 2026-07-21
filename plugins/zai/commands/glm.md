---
description: Consult GLM-5.2 (Z.ai) directly — fast by default, `--deep` for reasoning. Complementary to Claude.
argument-hint: "[--deep] [--effort max] [--file PATH] <question>"
allowed-tools: Bash
---

Run the `zai` CLI to consult GLM-5.2 with the user's arguments, then relay the answer (note it's GLM's,
not Claude's).

```bash
zai chat $ARGUMENTS
```

- If the user passed `--deep`/`--effort`, keep them (extended reasoning). Otherwise it runs fast.
- For a big document, they can pass `--file <path>` (GLM-5.2 accepts ~1M input tokens).
- For web research, use `zai websearch "<query>"` / `zai read <url>` instead.
- Full capability surface: the `zai` plugin's `references/CAPABILITIES.md`.
