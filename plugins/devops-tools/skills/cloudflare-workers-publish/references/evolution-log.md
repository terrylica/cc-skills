# cloudflare-workers-publish Evolution Log

Reverse-chronological log of skill improvements.

---

## 2026-02-18: Initial skill creation

**Source**: Empirical discovery during rangebar-patterns static hosting setup for Bokeh equity charts (10-15MB HTML files too large for GitHub).

**Reference implementation**: `rangebar-patterns` repository

- `results/published/wrangler.toml` — minimal Workers Static Assets config
- `scripts/publish_findings.sh` — 3-phase deploy (1Password creds, index gen, wrangler deploy)
- `.mise/tasks/publish.toml` — mise task wrapper

**Gotchas documented**: 15 anti-patterns (CFW-01 through CFW-15) covering:

- Cloudflare Pages deprecation (April 2025)
- 1Password service account limitations (read-only, no create)
- CONCEALED field `--reveal` requirement
- macOS bash 3 portability
- workers.dev subdomain discovery
- SSL/TLS handshake failure with macOS curl
- Git LFS pointer vs actual file content
- Tera template conflicts in mise TOML

**Validation**: Deployed 13MB Bokeh HTML chart to `https://rangebar-findings.terry-301.workers.dev/` successfully.

---

## 2026-06-30 — Large files & ZIP delivery (CFW-16, CFW-17)

**Trigger**: Delivering ~125 iPhone HEIC photos as a JPEG gallery + bulk ZIP to car dealers.
A first deploy including the 109 MiB full-res ZIP failed with `Asset too large`.

**Evidence**: `wrangler 4.106.0` rejects any single asset > 25 MiB at deploy time
(`Cloudflare Workers supports assets with sizes of up to 25 MiB. We found a file …bundle.zip
with a size of 109 MiB`). No flag raises it. The gallery + a 24 MiB downscaled, ZipCrypto-
encrypted ZIP deployed fine to `corolla-cross-trade-in.dmd0876.workers.dev`.

**Added**:

- Anti-patterns **CFW-16** (25 MiB/file hard cap) and **CFW-17** (bulk-ZIP exceeds cap →
  downscale or split hosts).
- New section "Large files & ZIP delivery" + reference doc
  [`references/large-files-and-zip-delivery.md`](./large-files-and-zip-delivery.md): host
  decision table, R2/Release/own-server options, and the **password-on-the-gateway** pattern
  (encrypt the ZIP, put the password only on the shared gateway, never on the Workers page).
- Cross-links to companion skills `media-tools/heic-to-jpeg-bundle` and
  `media-tools/photo-gallery-delivery`.

**Also discovered**: the Workers-Scripts deploy token cannot access R2
(`Please enable R2 through the Cloudflare Dashboard [code: 10042]`) — R2 needs a separate
scoped token + dashboard enablement.
