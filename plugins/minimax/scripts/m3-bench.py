#!/usr/bin/env python3
"""m3-bench — speed + quality benchmark for the current MiniMax model (the SSoT).

The model under test is read dynamically from the SSoT (MINIMAX_MODEL env, set by
~/.config/mise/config.toml) via scripts/_m3_common.py — this tool never pins or
benchmarks a prior model version. Each task is run in two reasoning modes:
`default` (native thinking on) and `reasoning_disabled` (reasoning:"disabled"),
so you can decide per consumer whether the default-thinking latency is acceptable
or whether to disable it for short/simple work.

Serial calls (accurate per-call latency), proxy-bypassed. Strips <think> for the
visible answer, then applies cheap task-specific quality checks.

Usage:
  uv run --python 3.14 --with requests python scripts/m3-bench.py

Key from MINIMAX_API_KEY env or 1Password (see scripts/_m3_common.py).
"""
import json
import re
import statistics
import sys
import time
from pathlib import Path

from _m3_common import BASE, MODEL, NET_ERRORS, get_key, session, err_of

S = session()
HDR = {"Authorization": f"Bearer {get_key()}", "Content-Type": "application/json"}
URL = f"{BASE}/chat/completions"
THINK = re.compile(r"<think>[\s\S]*?</think>\s*")

# The model under test is the SSoT model (MODEL, resolved dynamically in
# _m3_common). It must exist in the plugin's official catalog SSoT
# (references/fixtures/models-list-locked.json, review-gated, tripwired against
# /v1/models by scripts/minimax-check-upgrade) — fail loudly on drift instead of
# benchmarking a renamed/retired model id.
_CATALOG = Path(__file__).resolve().parent.parent / "references" / "fixtures" / "models-list-locked.json"
_official_ids = {m["id"] for m in json.loads(_CATALOG.read_text())["data"]}
if MODEL not in _official_ids:
    sys.exit(
        f"[m3-bench] model id {MODEL!r} absent from the official catalog snapshot "
        f"{_CATALOG.name} ({sorted(_official_ids)}). Audit the catalog tripwire "
        "(scripts/minimax-check-upgrade) and update the review-gated snapshot or "
        "the MINIMAX_MODEL SSoT."
    )

# Reasoning modes benchmarked for the single SSoT model — both stay on MODEL, so
# no prior version is ever invoked. "default" leaves native thinking on;
# "reasoning_disabled" sends reasoning:"disabled".
MODES = {"default": {}, "reasoning_disabled": {"reasoning": "disabled"}}
REPS = 2

JSON_SYS = ('Output ONLY a JSON object: {"action":"long"|"short"|"flat","confidence":0..1,'
            '"reasoning":"one sentence","stop_loss_pct":num,"take_profit_pct":num}. No prose, no fences.')
TASKS = {
    "short_tag":   {"max": 256,  "temp": 0.2, "sys": "Output ONLY 3-5 comma-separated lowercase tags. No prose.",
                    "user": "Tag: 'AAPL beats Q2 earnings, stock jumps 8% after hours on strong iPhone sales'."},
    "long_theory": {"max": 1536, "temp": 0.7, "sys": None,
                    "user": "Explain the Black-Scholes model and the meaning of N(d1) and N(d2) in ~220 words."},
    "reason_num":  {"max": 1536, "temp": 0.2, "sys": None,
                    "user": "A bond has modified duration 7. Its yield rises by 0.50%. Give the one-line "
                            "first-order formula for the approximate % price change and the numeric result."},
    "json_signal": {"max": 1536, "temp": 0.2, "sys": JSON_SYS,
                    "user": "Setup: EURUSD broke above its 50-day MA on above-average volume, RSI 61."},
}


def call(mode_extra, task):
    t = TASKS[task]
    msgs = ([{"role": "system", "content": t["sys"]}] if t["sys"] else []) + [{"role": "user", "content": t["user"]}]
    body = {"model": MODEL, "messages": msgs, "max_tokens": t["max"], "temperature": t["temp"], **mode_extra}
    t0 = time.perf_counter()
    try:
        r = S.post(URL, headers=HDR, json=body, timeout=120)
        dt = time.perf_counter() - t0
        j = r.json()
    except NET_ERRORS as e:
        return {"err": str(e)[:120], "dt": time.perf_counter() - t0}
    err = err_of(j)
    if err:
        return {"err": err, "dt": dt}
    ch = j["choices"][0]
    vis = THINK.sub("", ch["message"]["content"]).strip()
    u = j.get("usage", {})
    comp = u.get("completion_tokens", 0)
    return {"dt": round(dt, 2), "finish": ch.get("finish_reason"), "comp_tok": comp,
            "tps": round(comp / dt, 1) if dt > 0 else 0, "vis": vis[:240]}


def quality(task, vis):
    if task == "reason_num":
        return "≈-3.5% correct" if re.search(r"[-−]?3\.5\s*%", vis) else "MISS (-3.5% not found)"
    if task == "json_signal":
        try:
            d = json.loads(vis)
            ok = all(k in d for k in ("action", "confidence", "reasoning", "stop_loss_pct", "take_profit_pct"))
            return "valid JSON" if ok else "JSON parses, missing fields"
        except (ValueError, TypeError):
            return "INVALID JSON (try reasoning_split:true + fence-extract)"
    if task == "long_theory":
        hits = sum(1 for k in ("d1", "d2", "n(", "volatil", "strike", "risk-free", "black") if k in vis.lower())
        return f"theory keywords {hits}/7"
    return f"{len(vis)} chars"


print(f"# m3-bench — model under test: {MODEL} (SSoT: MINIMAX_MODEL)", flush=True)
results = {}
for mode, extra in MODES.items():
    print(f"\n### {MODEL} [{mode}]", flush=True)
    results[mode] = {}
    for task in TASKS:
        runs = [call(extra, task) for _ in range(REPS)]
        for rep, res in enumerate(runs):
            print(f"  {task} r{rep}: dt={res.get('dt')}s tps={res.get('tps')} "
                  f"comp={res.get('comp_tok')} {res.get('err', '')}", flush=True)
        ok = [r for r in runs if "err" not in r]
        if ok:
            best = max(ok, key=lambda r: len(r["vis"]))
            results[mode][task] = {
                "lat_med": round(statistics.median(r["dt"] for r in ok), 2),
                "tps_med": round(statistics.median(r["tps"] for r in ok), 1),
                "comp_tok": best["comp_tok"], "finish": best["finish"], "quality": quality(task, best["vis"])}
        else:
            results[mode][task] = {"error": runs[0].get("err")}

print("\n=== SUMMARY (median latency / median TPS / quality) ===", flush=True)
for mode in MODES:
    print(f"\n{MODEL} [{mode}]", flush=True)
    for task in TASKS:
        r = results[mode][task]
        if "error" in r:
            print(f"  {task:12s} ERROR {r['error']}", flush=True)
        else:
            print(f"  {task:12s} lat={r['lat_med']:>6}s tps={r['tps_med']:>5} comp={r['comp_tok']:>4} "
                  f"fin={r['finish']:<6} | {r['quality']}", flush=True)
print("\nDONE", flush=True)
