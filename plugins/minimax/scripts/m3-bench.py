#!/usr/bin/env python3
"""m3-bench — head-to-head speed + quality benchmark: M2.7 vs M2.7-highspeed vs M3.

Serial calls (accurate per-call latency), proxy-bypassed. Strips <think> for the visible
answer, then applies cheap task-specific quality checks. Use to decide per-consumer whether the
M3 latency (default thinking) is acceptable, or whether to add reasoning:"disabled".

Usage:
  uv run --python 3.14 --with requests python scripts/m3-bench.py

Key from MINIMAX_API_KEY env or 1Password (see scripts/_m3_common.py).
"""
import json
import re
import statistics
import time

from _m3_common import BASE, NET_ERRORS, get_key, session, err_of

S = session()
HDR = {"Authorization": f"Bearer {get_key()}", "Content-Type": "application/json"}
URL = f"{BASE}/chat/completions"
THINK = re.compile(r"<think>[\s\S]*?</think>\s*")
MODELS = ["MiniMax-M2.7", "MiniMax-M2.7-highspeed", "MiniMax-M3"]
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


def call(model, task):
    t = TASKS[task]
    msgs = ([{"role": "system", "content": t["sys"]}] if t["sys"] else []) + [{"role": "user", "content": t["user"]}]
    body = {"model": model, "messages": msgs, "max_tokens": t["max"], "temperature": t["temp"]}
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


results = {}
for model in MODELS:
    print(f"\n### {model}", flush=True)
    results[model] = {}
    for task in TASKS:
        runs = [call(model, task) for _ in range(REPS)]
        for rep, res in enumerate(runs):
            print(f"  {task} r{rep}: dt={res.get('dt')}s tps={res.get('tps')} "
                  f"comp={res.get('comp_tok')} {res.get('err', '')}", flush=True)
        ok = [r for r in runs if "err" not in r]
        if ok:
            best = max(ok, key=lambda r: len(r["vis"]))
            results[model][task] = {
                "lat_med": round(statistics.median(r["dt"] for r in ok), 2),
                "tps_med": round(statistics.median(r["tps"] for r in ok), 1),
                "comp_tok": best["comp_tok"], "finish": best["finish"], "quality": quality(task, best["vis"])}
        else:
            results[model][task] = {"error": runs[0].get("err")}

print("\n### probe MiniMax-M3-highspeed (docs claim it exists)", flush=True)
hs = call("MiniMax-M3-highspeed", "short_tag")
print(f"  -> {hs.get('err') or 'ACCEPTED (no error)'}", flush=True)

print("\n=== SUMMARY (median latency / median TPS / quality) ===", flush=True)
for m in MODELS:
    print(f"\n{m}", flush=True)
    for task in TASKS:
        r = results[m][task]
        if "error" in r:
            print(f"  {task:12s} ERROR {r['error']}", flush=True)
        else:
            print(f"  {task:12s} lat={r['lat_med']:>6}s tps={r['tps_med']:>5} comp={r['comp_tok']:>4} "
                  f"fin={r['finish']:<6} | {r['quality']}", flush=True)
print("\nDONE", flush=True)
