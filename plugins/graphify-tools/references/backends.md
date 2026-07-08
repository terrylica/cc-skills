# graphify backend routing (SSoT)

Which LLM does the semantic-extraction step call? graphify's `--backend` selects it. This file is the single source of truth for the three backends wired for this operator; `setup`, `build-graph`, and `query-and-explain` all point here.

> **Every backend below needs the proxy unset.** ccmax-claude injects `HTTPS_PROXY=127.0.0.1:<port>` (bearer-pin CONNECT proxy) into every child env; it 502s any host it doesn't intercept — including `eon.25u.com`, `api.minimax.io`, and Google. Prefix runs with:
>
> ```bash
> unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
> ```

## The three backends (empirical, 2026-07-07)

| Backend                                    | Speed                                    | Ban-risk                               | Cost             | Use for                                                                   |
| ------------------------------------------ | ---------------------------------------- | -------------------------------------- | ---------------- | ------------------------------------------------------------------------- |
| **fleet Opus 4.8** (`openai` → sub2api)    | fast, clean                              | ⚠ HEART-103 bypass on eon Max accounts | sub2api wallet   | interactive / smaller graphs, best quality via "our LLM"                  |
| **gemini-2.5-flash**                       | fast, reliable                           | none (3rd-party)                       | ~$0.15 / 15 docs | large bulk runs — the safe default for whole-repo                         |
| **MiniMax-M3** (`openai` → api.minimax.io) | **slow** (~5 min / 6 files, thinking-on) | none (3rd-party)                       | ~$0.04 / 6 files | rich extraction when latency doesn't matter; NOT ideal for 1000s of files |

### A. Fleet Opus 4.8 (dedicated `graphify` sub2api key)

Routes through the same sub2api OpenAI gateway markmind/harpa use. 1Password item `2eeg5h4n3st6kcmt3icjhfjiiy` ("graphify sub2api OpenAI integration", Claude Automation vault). sub2api user `graphify` (id 102, group 5, $50 wallet). Kill-switch: `UPDATE api_keys SET status='disabled' WHERE id=20148;`.

```bash
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
export OPENAI_API_KEY=$(op read "op://Claude Automation/2eeg5h4n3st6kcmt3icjhfjiiy/api_key")
export OPENAI_BASE_URL="https://eon.25u.com:8450/v1"     # on-LAN; off-LAN → https://bigblack.tail0f299b.ts.net:8450/v1
export GRAPHIFY_LLM_TEMPERATURE=omit                     # REQUIRED — Opus 4.8 rejects `temperature` (HTTP 400)
graphify extract <target> --backend openai --model claude-opus-4-8
graphify cluster-only <target> --backend openai --model claude-opus-4-8
```

- **`GRAPHIFY_LLM_TEMPERATURE=omit` is mandatory** — without it: `400 temperature is deprecated for this model`.
- **Ban-risk**: the OpenAI path bypasses doorward's HEART-103 fidelity guard, so extraction hits the primary eon Max accounts. Fine for trivial volume; a whole-repo bulk run materially raises exposure (see the fleet docs' HARPA/MarkMind risk section). Prefer gemini for bulk.
- Off-LAN, swap `OPENAI_BASE_URL` to the tailnet fallback field in the same 1Password item.

### B. Gemini 2.5-flash (bulk default)

`GEMINI_API_KEY` is already in the environment. Pin the model explicitly — the default gemini model 503s under load.

```bash
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
graphify extract <target> --backend gemini --model gemini-2.5-flash
graphify cluster-only <target> --backend gemini --model gemini-2.5-flash
```

### C. MiniMax-M3 (rich but slow)

1Password item `e54cb3ujopexslaq7loywpuycm` ("MiniMax API - High-Speed Plan", field `credential`). OpenAI-compatible at `api.minimax.io/v1`.

```bash
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
export OPENAI_API_KEY=$(op read "op://Claude Automation/e54cb3ujopexslaq7loywpuycm/credential")
export OPENAI_BASE_URL="https://api.minimax.io/v1"
graphify extract <target> --backend openai --model MiniMax-M3
graphify cluster-only <target> --backend openai --model MiniMax-M3
```

- M3 has thinking ON by default and graphify's plain `openai` client **cannot** send M3's `reasoning_split`/`reasoning:"disabled"` flags, so responses occasionally come back as a "hollow response" that graphify's adaptive retry bisects and recovers — correct results, but slow. Empirically ~5 min for 6 files.
- M3 accepts `temperature`, so `GRAPHIFY_LLM_TEMPERATURE=omit` is NOT needed (harmless if set).
- Verdict: great for a handful of dense files where you want maximum extraction; avoid for 1000s of files.

## `claude` backend is BLOCKED — do not use

`graphify --backend claude` reads `ANTHROPIC_BASE_URL`, which on this fleet points at doorward's **fidelity-guarded** `/v1/messages` door. Direct Anthropic-SDK calls lack the `X-Ccmax-Wrapper-Version` header only ccmax-claude's proxy injects → HTTP 426 `wrapper_version_too_old`. Use backend **A** (fleet Opus via the _OpenAI_ door) instead — same accounts, unguarded path.

## Install extras

Backends B and the `openai` path need the extras: `uv tool install "graphifyy[anthropic,gemini]"`. Bare install is AST-only and fails semantic extraction with a missing-package error.
