# Large files & ZIP delivery on Cloudflare Workers

How to serve **downloadable files** (a ZIP bundle, a dataset, an image set) from a
Workers static deployment, the hard size limit you'll hit, and the
**password-on-the-gateway** pattern for gating an otherwise-unlisted download.

Companion skill for producing the artifacts: `media-tools/heic-to-jpeg-bundle`
(builds a gallery + a size-capped, optionally password-protected ZIP).

## The 25 MiB hard cap (CFW-16)

Cloudflare Workers **Static Assets** reject any single file larger than **25 MiB**.
It's a deploy-time error, not a runtime one:

```
✘ [ERROR] Asset too large.
  Cloudflare Workers supports assets with sizes of up to 25 MiB. We found a file
  …/bundle.zip with a size of 109 MiB.
```

There's no flag to raise it. Confirmed empirically (June 2026, wrangler 4.x). Plan around
it: **anything you put in the `[assets]` directory must be ≤ 25 MiB per file.**

A gallery of individual web-res JPEGs is fine (each photo is well under the cap, even with
hundreds of files). A **single ZIP of a whole photo set is not** — ~120 full-res iPhone
JPEGs zip to 100–500 MB.

## Decision: where does each artifact go?

| Artifact                             | Typical size | Host                                                |
| ------------------------------------ | ------------ | --------------------------------------------------- |
| Gallery `index.html` + thumbnails    | tiny         | **Workers** ✅                                      |
| Individual web-res JPEGs (per photo) | ~0.3–1.5 MB  | **Workers** ✅ (each file ≤ 25 MiB)                 |
| Web-res ZIP, downscaled to fit       | ≤ 25 MiB     | **Workers** ✅ (use `--zip-cap-mib 25`)             |
| Full-res ZIP (whole set)             | 100–500 MB   | **R2** / GitHub Release / your own server ❌Workers |

So the common shape is **hybrid**: gallery + a small capped ZIP on Workers, and (optionally)
a full-resolution ZIP on a large-file host linked from the same gallery.

### Large-file host options (all give an "anyone-with-link" URL)

- **Cloudflare R2** (`pub-<hash>.r2.dev` public bucket): no per-file cap, unlisted, durable.
  Requires enabling R2 in the dashboard once (a payment method on file; generous free tier)
  and an **R2-scoped API token** (the Workers-Scripts token used for deploys can't touch R2 —
  you'll get `Please enable R2 through the Cloudflare Dashboard [code: 10042]`).
- **GitHub Release asset**: up to 2 GB/asset, anonymous download — but only on a **public**
  repo, so the file is world-readable/indexed. Avoid for personal/PII content.
- **Your own server** (Caddy + Cloudflare Tunnel / Tailscale Funnel): durable + unlisted, but
  you have to wire the route.

## The password-on-the-gateway pattern

Goal: a download that's effectively gated, without standing up auth, when you're already
sharing a single **gateway** link (a gist, an email, a landing page).

1. **Encrypt the ZIP** with a password. Use classic **ZipCrypto** (`zip -e`) — Windows
   Explorer, 7-Zip, and macOS Archive Utility all open it natively with the password. (AES-256
   is stronger but needs 7-Zip on the recipient's end → more friction for non-technical
   recipients.) This is a light access gate, not strong cryptography.
2. **Host the encrypted ZIP** wherever it fits (Workers if ≤ 25 MiB, else a large-file host).
3. **Put the password only on the gateway** you share (the gist/email), **never on the
   Workers page or in the ZIP URL.** Now whoever has the gateway has both the link and the
   password; anyone who merely stumbles onto the bare ZIP URL can't open it. The gateway is
   the choke point.

This keeps the security model honest: the page that lists the download is unlisted, the file
is unlisted, and the password lives one layer up at the gateway.

## Worked example (June 2026)

Delivering ~125 iPhone HEIC photos to car dealers whose appraisal software couldn't open
HEIC:

- `heic-to-jpeg-bundle` converted HEIC → JPEG (2048px gallery tier + thumbnails) and built a
  **24 MiB** ZipCrypto-encrypted ZIP (`--zip-cap-mib 25` downscaled the ZIP tier to ~960px to
  fit).
- The gallery + the 24 MiB ZIP deployed to Workers (`corolla-cross-trade-in.dmd0876.workers.dev`).
  A first attempt with the 109 MiB full-res ZIP failed with `Asset too large` — that's CFW-16.
- A GitHub **gist** (the gateway, already shared with dealers via a short link) was updated
  with the gallery link, the ZIP link, and the **password** — which was deliberately absent
  from the Workers page.

End-to-end orchestration of that flow: the `media-tools/photo-gallery-delivery` skill.
