# Device calibration + Pushover API limits

Empirical facts the render + send skills rely on. SSoT for the numeric caps is
[`../pushover_api_limits.json`](../pushover_api_limits.json) — update there.

## Pushover message caps (UTF-8 chars)

| Field       | Limit                                |
| ----------- | ------------------------------------ |
| `message`   | 1024                                 |
| `title`     | 250                                  |
| `url`       | 512                                  |
| `url_title` | 100                                  |
| attachment  | 1 image ≤ 5 MB (`image/png`\|`jpeg`) |

The full 1024-char body IS delivered, but the **lock-screen/banner preview
truncates** — front-load the highest-value identifiers in the first ~120 chars
AND in the title. Offload long retrieval pointers / deep links to `url`+`url_title`.

## Incident-report image (verified on a physical iPhone 13 mini, 2026-05-30)

- **72-column hard wrap** is legible inline without pinch-zoom.
- Pushover **fits images to width** — it never crops horizontally.
- **No practical pixel-height ceiling** (a 30,000 px-tall image scrolls fine, far
  under 5 MB) → render the whole report in one tall image, never paginate.
- **Auto-fit width**: 72 cols is the MAX wrap, not a fixed canvas width. The canvas
  is sized to the longest actual line (`maxChars × charW + 2·pad`, monospace ⇒
  exact), so short reports don't waste right-margin whitespace — Pushover scales the
  snug image UP, rendering text larger.
- Render metrics (`pushover_core.ts`): fontSize 30, charW = round(30·0.6) = 18,
  lineH = round(30·1.42) = 43, pad 24. Theme `#0d1117` bg / `#c9d1d9` fg.
- **Word-aware wrap** (`fold -s`): break at spaces, never mid-word; only a single
  token longer than the column width (URLs/hashes/paths) is hard-broken.

## Priority + TTL

| Level | priority | Phone behavior                                                |
| ----- | -------- | ------------------------------------------------------------- |
| INFO  | -1       | silent, inbox-only                                            |
| WARN  | 0        | default sound + vibration                                     |
| ERROR | 1        | bypass quiet hours                                            |
| —     | 2        | emergency, repeats until acknowledged (retry/expire required) |

## Proxy gotcha

Always send to `api.pushover.net` with the sandbox MITM proxy unset
(`env -u HTTPS_PROXY -u HTTP_PROXY …`, or `curl --noproxy '*'`) — it returns
HTTP 502 on the Pushover hostname otherwise.
