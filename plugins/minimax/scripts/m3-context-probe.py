#!/usr/bin/env python3
"""m3-context-probe — pin MiniMax-M3's input-context ceiling and verify long-context retrieval.

Sends escalating payloads with a hidden needle and checks (a) whether the request is accepted
and (b) whether M3 retrieves the needle. Thinking is disabled and max_tokens is adequate so the
answer is not eaten by a <think> block (the artifact that produced false "not retrieved" earlier).

Usage:
  uv run --python 3.14 --with requests python scripts/m3-context-probe.py

Key from MINIMAX_API_KEY env or 1Password (see scripts/_m3_common.py).
Expected on the Plus-High-Speed key (2026-06-01): retrieval OK at 128K/400K; accepted at 512K;
rejected (400) at 575K/700K -> input ceiling ~512K tokens (docs claim 1M).
"""
import json
import time

from _m3_common import BASE, MODEL, NET_ERRORS, get_key, session, err_of

S = session()
HDR = {"Authorization": f"Bearer {get_key()}", "Content-Type": "application/json"}
URL = f"{BASE}/chat/completions"
FILLER = "The quick brown fox jumps over the lazy dog. "
NEEDLE = "The SECRET-CODE is ZX9Q7-DELTA."
CHARS_PER_TOK = 4.5  # measured for this filler on the MiniMax tokenizer


def run(target_tok, max_out, needle=True):
    body_txt = FILLER * (int(target_tok * CHARS_PER_TOK) // len(FILLER))
    if needle:
        ins = int(len(body_txt) * 0.8)
        body_txt = body_txt[:ins] + " " + NEEDLE + " " + body_txt[ins:]
        q = "\n\nWhat is the SECRET-CODE? Reply with just the code."
    else:
        q = "\n\nReply: ok"
    t0 = time.perf_counter()
    try:
        r = S.post(URL, headers=HDR, timeout=240, json={
            "model": MODEL, "messages": [{"role": "user", "content": body_txt + q}],
            "max_tokens": max_out, "temperature": 0, "reasoning": "disabled"})
        dt = round(time.perf_counter() - t0, 1)
        j = r.json()
    except NET_ERRORS as e:
        return {"target_tok": target_tok, "err": str(e)[:120], "dt": round(time.perf_counter() - t0, 1)}
    err = err_of(j)
    ch = (j.get("choices") or [{}])[0]
    content = (ch.get("message", {}) or {}).get("content", "") or ""
    return {"target_tok": target_tok, "accepted": err is None,
            "prompt_tokens": (j.get("usage") or {}).get("prompt_tokens"),
            "retrieved": ("ZX9Q7-DELTA" in content) if needle else None,
            "finish": ch.get("finish_reason"), "dt": dt, "err": err}


print("=== needle retrieval (thinking OFF, max_tokens 256) ===", flush=True)
for tk in [128_000, 400_000]:
    print(json.dumps(run(tk, 256)), flush=True)
print("=== ceiling pin (needle off, max_tokens 32) ===", flush=True)
for tk in [512_000, 575_000, 700_000]:
    print(json.dumps(run(tk, 32, needle=False)), flush=True)
print("DONE", flush=True)
