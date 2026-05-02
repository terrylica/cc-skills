# Publishing — where pages get hosted, and how

> Read this when you're about to put a finished page somewhere a real
> reader can open it. It's not about authoring (that's `principles.md`)
> or extending the kernel (that's `contributing.md`); it's about the
> delivery surface.

## Two surfaces, two roles

The kernel CSS and the rendered HTML pages live in different places, on
purpose:

| Asset                                | Hosted at                     | Why                                                                                           |
| ------------------------------------ | ----------------------------- | --------------------------------------------------------------------------------------------- |
| `assets/showcase.css`                | jsDelivr CDN (public)         | Shared infrastructure: every page anywhere imports it via one URL.                            |
| `auto-nav.css`, `auto-nav.js`        | Generated next to your HTML   | Site-local; written by `build-nav.py` at publish time. Versioned via the `?v=N` query string. |
| `site-map.html` + per-page rail HTML | Generated into your site dir  | The sitemap is part of your published artifact; it ships alongside the pages it indexes.      |
| Your rendered HTML pages             | Tailscale tailnet on bigblack | Internal-only audience; no DNS, no public exposure, no reverse proxy.                         |
| (alternatively) HTML                 | jsDelivr / GH Pages / Workers | Public reach, public-internet caching, public-search visibility.                              |

The kernel is _shared infrastructure_; rendered pages (and their
auto-generated nav assets) are _evidence_ intended for a specific
audience. Treat the two surfaces independently. A page that imports the
public kernel can still be served privately — the kernel CSS is the only
public artifact, and the nav rail's CSS/JS travel with the site dir.

## Pick a delivery surface

| Audience                                  | Recommended surface                  | Why                                                                                         |
| ----------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------- |
| Just you and the internal team            | **Tailscale on bigblack**            | Tailnet ACL = no public exposure, no auth UI, no rate limit. Setup once, push forever.      |
| External (clients, the web)               | jsDelivr / GitHub Pages / CF Workers | Public addressing. Costs nothing. Add only when an external reader actually needs the page. |
| Forensic, immutable, citable from outside | jsDelivr `@<commit-sha>`             | Page becomes citable URL pinned to a git commit. Use when external reviewers need a link.   |

Default to **tailnet-only** unless the page genuinely needs public reach.
Public hosting forces you to think about secrets in the page, search
visibility, retention, and trust boundaries you don't otherwise need.

## The bigblack tailnet pattern (recommended for internal pages)

A single static directory on bigblack, served by `tailscale serve` to
your tailnet at a stable port. Each repo gets its own subdirectory under
that root. Rendered URL:

```
https://bigblack.tail0f299b.ts.net:8448/<repo>/<page>/
```

`<repo>` is auto-derived from your git remote, so URLs don't collide
between projects sharing one bigblack instance.

### Bigblack one-time setup

```bash
ssh bigblack 'mkdir -p ~/sites'
ssh bigblack 'sudo tailscale serve --bg --https=8448 /home/tca/sites'
```

That's the whole server. No nginx. No reverse proxy. No certs to renew —
Tailscale terminates TLS automatically using its own MagicDNS cert.

### Per-repo setup (one command)

```bash
PLUGIN=${CLAUDE_PLUGIN_ROOT:-~/.claude/plugins/marketplaces/cc-skills/plugins/html-showcase}
bash "$PLUGIN/skills/page-template/scripts/install.sh"
```

That's it. `install.sh` is the one-shot bootstrap: it copies the three
pipeline scripts (`build-nav.py`, `check-orphan-pages.py`, `site.sh`)
into `<repo>/scripts/` and appends `**/.published.json` to your
`.gitignore`. It auto-detects the repo root via `git rev-parse
--show-toplevel`, or falls back to `$PWD`.

The installer is **idempotent** (re-running with no changes prints `=
unchanged` for every file) and **non-destructive** (refuses to
overwrite an existing differing file unless you pass `--force`).

To also seed a starter site directory in one go:

```bash
bash "$PLUGIN/skills/page-template/scripts/install.sh" --site contractor-site
```

That additionally copies `templates/index.html`,
`templates/overrides.css.example`, and `templates/lychee.toml` into
`<repo>/contractor-site/`.

If you'd rather copy by hand, the four-line manual form still works:

```bash
cp $CLAUDE_PLUGIN_ROOT/skills/page-template/scripts/build-nav.py ./scripts/
cp $CLAUDE_PLUGIN_ROOT/skills/page-template/scripts/check-orphan-pages.py ./scripts/
cp $CLAUDE_PLUGIN_ROOT/skills/page-template/scripts/site.sh ./scripts/
echo '**/.published.json' >> .gitignore
```

In either form, the `site.sh` shipped here will fall back to the
canonical `build-nav.py` shipped with this plugin if the in-repo copy
is missing, so the very first push works even before you commit your
`scripts/` directory — but committing the three scripts keeps the repo
self-contained.

(If you also want shorthand commands like `mise run site:push`, add a
small `.mise/tasks/site.toml` that calls `scripts/site.sh`.)

### The publish workflow

```bash
scripts/site.sh nav       <local-dir>   # regenerate site-map + auto-nav (no network)
scripts/site.sh check     <local-dir>   # nav + lychee + orphan-page check
scripts/site.sh push      <local-dir>   # nav + check + rsync to bigblack
scripts/site.sh url       <local-dir>   # print the URL where it lives
scripts/site.sh list                    # show every published page across projects
scripts/site.sh unpublish <local-dir>   # remove (asks for confirmation)
```

`check` always re-runs `nav` first; `push` always re-runs `check` first.
Broken links, unreachable pages, or a stale rail abort the push **before**
anything reaches bigblack. This is the only gate; there's no
semantic-release step. The sitemap itself becomes part of the link graph
that lychee + the orphan detector validate, so the rail's correctness is
checked on every publish.

### The URL formula

```
https://bigblack.tail0f299b.ts.net:8448/<repo>/<page>/
                                         │       │
                                         │       └── basename of the local dir you pushed
                                         └── basename of `git remote get-url origin`, .git stripped
```

Override the auto-derived repo name with `SITE_PROJECT_NAME=foo` if your
git remote name doesn't match the namespace you want. Override the SSH
alias with `SITE_BIGBLACK_SSH=…` if your `.ssh/config` uses a different
host name.

## Push-side gating, not pull-side

The validation gate (lychee + orphan-page check) runs **on the publisher's
machine**, before the rsync. There is no CI, no GitHub Action, no
post-receive hook on bigblack.

This is intentional. Bigblack is a delivery surface, not a quality gate.
The page reaches it only after the local validator says it's reachable
and link-clean. If you find yourself wanting bigblack to refuse bad
content, that's a sign the validation should be stricter on the
publisher side (extend `check-orphan-pages.py`, tighten `lychee.toml`),
not that bigblack should grow gating logic.

## Provenance: `.published.json`

Each push writes a sidecar manifest into the published directory:

```json
{
  "project": "opendeviationbar-py",
  "page": "contractor-site",
  "commit": "b36acb24937b",
  "published_utc": "2026-05-02T03:46:38Z",
  "source_repo": "git@github.com:terrylica/opendeviationbar-py.git",
  "url": "https://bigblack.tail0f299b.ts.net:8448/opendeviationbar-py/contractor-site/"
}
```

Fetch it any time to correlate the live page back to a git revision:

```bash
curl -sk https://bigblack.tail0f299b.ts.net:8448/<repo>/<page>/.published.json | jq
```

The manifest is gitignored (regenerated on every push), so it never
pollutes the source repo's history. The git history of the source repo
already records every change that produced a publishable page.

## When NOT to use bigblack

- The page must be **citable from outside** the tailnet — use jsDelivr or
  GitHub Pages instead so the URL resolves on the public internet.
- The page is part of a **public marketing or docs site** — that's a
  different audience and a different lifecycle; keep it on the public
  surface end-to-end.
- The page must survive the bigblack host **going away** — treat bigblack
  as ephemeral; for archival, also push to a public surface or commit
  the rendered HTML into the source repo's git history.

For everything else (contractor showcases, audit reports, internal
telemetry views, weekly digests, run summaries), bigblack on the tailnet
is the lowest-friction option.

## Where this pattern lives in the world

The pipeline pattern is borrowed from `opendeviationbar-patterns`'s
`scripts/blob.sh` (which pushes large binary files to bigblack via SSH+rsync).
The HTML adaptation differs in two important ways:

1. **Path-mirrored, not content-addressed.** `blob.sh` URLs are
   `/<sha[:2]>/<sha>/<filename>`, which means the URL changes whenever
   the content does. That's correct for binary data fingerprinting; it's
   wrong for HTML pages a human is going to bookmark and re-visit. The
   site pattern uses `/<repo>/<page>/` so URLs are stable across edits.

2. **Validation gate before push.** `blob.sh` doesn't validate (binary
   blobs are opaque); the site pattern does (HTML has a notion of
   "broken"). Lychee + the orphan-page detector are the gate.

The two pipelines coexist on bigblack — the SWS blob server runs on port
18130 (content-addressed binaries), and `tailscale serve path` runs on
port 8448 (path-mirrored HTML). They share the same tailnet ACL but
nothing else.
