#!/usr/bin/env python3
"""m3-probe — empirical MiniMax-M3 option / capability map.

Probes, against the LIVE API, what M3 actually accepts and how it behaves:
  thinking-mode variants, response_format (JSON), tools/tool_choice, vision,
  parameter honoring, and the output-token ceiling. Writes a JSON summary and
  prints a human-readable table. Cross-check against references/M3-EMPIRICAL.md.

Usage:
  uv run --python 3.14 --with requests,pillow python scripts/m3-probe.py [--out results.json]

Key from MINIMAX_API_KEY env or 1Password (see scripts/_m3_common.py).
"""
import io
import json
import sys
import time
import base64

from _m3_common import BASE, MODEL, NET_ERRORS, get_key, session, err_of

S = session()
HDR = {"Authorization": f"Bearer {get_key()}", "Content-Type": "application/json"}
URL = f"{BASE}/chat/completions"
out: dict = {}


def post(body, timeout=120):
    t0 = time.perf_counter()
    try:
        r = S.post(URL, headers=HDR, json=body, timeout=timeout)
        dt = time.perf_counter() - t0
        j = r.json()
    except NET_ERRORS as e:
        return {"err": str(e)[:160], "dt": round(time.perf_counter() - t0, 1)}
    ch = (j.get("choices") or [{}])[0]
    msg = ch.get("message", {}) or {}
    u = j.get("usage", {}) or {}
    reasoning = msg.get("reasoning_details") or msg.get("reasoning_content") or ch.get("reasoning")
    return {
        "dt": round(dt, 1), "err": err_of(j), "finish": ch.get("finish_reason"),
        "n_choices": len(j.get("choices") or []), "tool_calls": msg.get("tool_calls"),
        "content": (msg.get("content") or "")[:300], "msg_keys": sorted(msg.keys()),
        "reasoning_present": reasoning is not None,
        "reasoning_sample": (str(reasoning)[:150] if reasoning else None),
        "prompt_tokens": u.get("prompt_tokens"), "completion_tokens": u.get("completion_tokens"),
    }


REASON_Q = [{"role": "user", "content": "A train goes 60km at 30km/h, then 60km at 60km/h. Average speed over the whole trip? Give the number."}]  # ans 40

# ---- 1. THINKING / REASONING mode variants ----
print("## thinking modes", flush=True)
out["thinking"] = {}
variants = {
    "default": {},
    "reasoning_effort_low": {"reasoning_effort": "low"},
    "reasoning_disabled": {"reasoning": "disabled"},
    "reasoning_adaptive": {"reasoning": "adaptive"},
    "reasoning_obj_enabled_false": {"reasoning": {"enabled": False}},
    "reasoning_split": {"reasoning_split": True},
    "include_reasoning": {"include_reasoning": True},
    "thinking_false": {"thinking": False},
}
for name, extra in variants.items():
    res = post({"model": MODEL, "messages": REASON_Q, "max_tokens": 2048, "temperature": 0.2, **extra})
    out["thinking"][name] = res
    print(f"  {name:28s} ok={res.get('err') is None} dt={res.get('dt')} comp={res.get('completion_tokens')} "
          f"rsn_present={res.get('reasoning_present')} err={res.get('err')}", flush=True)

# ---- 2. response_format (JSON) ----
print("## response_format", flush=True)
out["response_format"] = {}
rf = post({"model": MODEL, "messages": [{"role": "user", "content": "Return an object with keys city and population for Tokyo."}],
           "response_format": {"type": "json_object"}, "max_tokens": 1024})
try:
    json.loads(rf["content"]); rf["parses"] = True
except (ValueError, TypeError):
    rf["parses"] = False
out["response_format"]["json_object"] = rf
print(f"  json_object: ok={rf.get('err') is None} parses={rf.get('parses')} content={rf.get('content')[:80]!r}", flush=True)

# ---- 3. tools + tool_choice ----
print("## tools/tool_choice", flush=True)
TOOLS = [{"type": "function", "function": {"name": "get_weather", "description": "Get weather",
          "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}]
forced = post({"model": MODEL, "messages": [{"role": "user", "content": "Hi"}], "tools": TOOLS,
               "tool_choice": {"type": "function", "function": {"name": "get_weather"}}, "max_tokens": 512})
none = post({"model": MODEL, "messages": [{"role": "user", "content": "Weather in Paris?"}], "tools": TOOLS,
             "tool_choice": "none", "max_tokens": 512})
out["tools"] = {"forced_choice": forced, "choice_none": none}
print(f"  forced: tool_calls={'YES' if forced.get('tool_calls') else 'NO'} err={forced.get('err')}", flush=True)
print(f"  none:   tool_calls={'yes' if none.get('tool_calls') else 'no'} (want no) err={none.get('err')}", flush=True)

# ---- 4. VISION ----
print("## vision", flush=True)
try:
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (320, 120), (255, 255, 255))
    ImageDraw.Draw(img).text((20, 40), "BANANA-7295", fill=(0, 0, 0))
    buf = io.BytesIO(); img.save(buf, "PNG")
    b64 = base64.b64encode(buf.getvalue()).decode()
    vis = post({"model": MODEL, "max_tokens": 256, "messages": [{"role": "user", "content": [
        {"type": "text", "text": "What exact text is written in this image? Reply with just the text."},
        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}}]}]})
    vis["read_correct"] = "BANANA-7295" in (vis.get("content") or "")
    out["vision"] = vis
    print(f"  vision: ok={vis.get('err') is None} read_correct={vis.get('read_correct')} err={vis.get('err')}", flush=True)
except ImportError:
    out["vision"] = {"skipped": "pillow not installed (add --with pillow)"}
    print("  vision: SKIPPED (pillow missing)", flush=True)

# ---- 5. param honoring sweep ----
print("## param honoring", flush=True)
out["params"] = {}
sweep = {"stop": {"stop": ["STOP"]}, "n_2": {"n": 2}, "seed": {"seed": 42},
         "presence_penalty": {"presence_penalty": 1.0}, "frequency_penalty": {"frequency_penalty": 1.0},
         "logprobs": {"logprobs": True, "top_logprobs": 3}, "top_p": {"top_p": 0.5}}
for name, extra in sweep.items():
    res = post({"model": MODEL, "messages": [{"role": "user", "content": "Count: one two three STOP four five"}], "max_tokens": 256, **extra})
    out["params"][name] = {"accepted": res.get("err") is None, "err": res.get("err"), "n_choices": res.get("n_choices")}
    print(f"  {name:18s} accepted={res.get('err') is None} n_choices={res.get('n_choices')} err={res.get('err')}", flush=True)

# ---- 6. output ceiling ----
print("## output ceiling", flush=True)
out["max_tokens_ceiling"] = {}
for mt in [131072, 262144, 524288, 1048576]:
    res = post({"model": MODEL, "messages": [{"role": "user", "content": "Reply: ok"}], "max_tokens": mt}, timeout=60)
    out["max_tokens_ceiling"][str(mt)] = {"accepted": res.get("err") is None, "err": res.get("err")}
    print(f"  max_tokens={mt}: accepted={res.get('err') is None} err={res.get('err')}", flush=True)

out_path = "m3_probe_results.json"
if "--out" in sys.argv:
    out_path = sys.argv[sys.argv.index("--out") + 1]
with open(out_path, "w") as f:
    json.dump(out, f, indent=2)
print(f"\nwrote {out_path}\nDONE", flush=True)
