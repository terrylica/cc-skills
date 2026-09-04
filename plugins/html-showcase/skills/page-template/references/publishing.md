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
| Your rendered HTML pages             | Tailscale tailnet on myhost   | Internal-only audience; no DNS, no public exposure, no reverse proxy.                         |
| (alternatively) HTML                 | jsDelivr / GH Pages / Workers | Public reach, public-internet caching, public-search visibility.                              |

The kernel is _shared infrastructure_; rendered pages (and their
auto-generated nav assets) are _evidence_ intended for a specific
audience. Treat the two surfaces independently. A page that imports the
public kernel can still be served privately — the kernel CSS is the only
public artifact, and the nav rail's CSS/JS travel with the site dir.

## Pick a delivery surface

| Audience                                  | Recommended surface                  | Why                                                                                         |
| ----------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------- |
| Just you and the internal team            | **Tailscale on myhost**              | Tailnet ACL = no public exposure, no auth UI, no rate limit. Setup once, push forever.      |
| External (clients, the web)               | jsDelivr / GitHub Pages / CF Workers | Public addressing. Costs nothing. Add only when an external reader actually needs the page. |
| Forensic, immutable, citable from outside | jsDelivr `@<commit-sha>`             | Page becomes citable URL pinned to a git commit. Use when external reviewers need a link.   |

Default to **tailnet-only** unless the page genuinely needs public reach.
Public hosting forces you to think about secrets in the page, search
visibility, retention, and trust boundaries you don't otherwise need.

## The myhost tailnet pattern (recommended for internal pages)

A single static directory on myhost, served by `tailscale serve` to
your tailnet at a stable port. Each repo gets its own subdirectory under
that root. Rendered URL:

```
https://myhost.tailnet-name.ts.net:8448/<repo>/<page>/
```

`<repo>` is auto-derived from your git remote, so URLs don't collide
between projects sharing one myhost instance.

### Server one-time setup

```bash
ssh myhost 'mkdir -p ~/sites'
ssh myhost 'sudo tailscale serve --bg --https=8448 /home/you/sites'
```

That's the whole server. No nginx. No reverse proxy. No certs to renew —
Tailscale terminates TLS automatically using its own MagicDNS cert.

### Per-repo setup (one command)

```bash
ROOT="$(cc-plugin-root html-showcase)"
bash "$ROOT/skills/page-template/scripts/install.sh"
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
ROOT="$(cc-plugin-root html-showcase)"
cp "$ROOT/skills/page-template/scripts/build-nav.py" ./scripts/
cp "$ROOT/skills/page-template/scripts/check-orphan-pages.py" ./scripts/
cp "$ROOT/skills/page-template/scripts/site.sh" ./scripts/
echo '**/.published.json' >> .gitignore
```

In either form, the `site.sh` shipped here will fall back to the
canonical `build-nav.py` shipped with this plugin if the in-repo copy
is missing, so the very first push works even before you commit your
`scripts/` directory — but committing the three scripts keeps the repo
self-contained.

(If you also want shorthand commands like `mise run site:push`, add a
small `tasks/site.toml` that calls `scripts/site.sh`.)

### The publish workflow

```bash
scripts/site.sh nav       <local-dir>   # regenerate site-map + auto-nav (no network)
scripts/site.sh check     <local-dir>   # nav + lychee + orphan-page check
scripts/site.sh push      <local-dir>   # nav + check + rsync to myhost
scripts/site.sh url       <local-dir>   # print the URL where it lives
scripts/site.sh list                    # show every published page across projects
scripts/site.sh unpublish <local-dir>   # remove (asks for confirmation)
```

`check` always re-runs `nav` first; `push` always re-runs `check` first.
Broken links, unreachable pages, or a stale rail abort the push **before**
anything reaches myhost. This is the only gate; there's no
semantic-release step. The sitemap itself becomes part of the link graph
that lychee + the orphan detector validate, so the rail's correctness is
checked on every publish.

### The URL formula

```
https://myhost.tailnet-name.ts.net:8448/<repo>/<page>/
                                         │       │
                                         │       └── basename of the local dir you pushed
                                         └── basename of `git remote get-url origin`, .git stripped
```

Override the auto-derived repo name with `SITE_PROJECT_NAME=foo` if your git remote name doesn't match the namespace you want. Override the SSH alias with `SITE_SSH_HOST=…` if your `.ssh/config` uses a different host name.

### Configuring your own publish host

`site.sh` ships with **no default host** — `myhost` / `tailnet-name.ts.net` above are placeholders, not a real server you can reach. Point it at your own by exporting three variables, or by creating `${XDG_CONFIG_HOME:-~/.config}/html-showcase/site.env` (overridable with `SITE_CONFIG`):

```bash
SITE_SSH_HOST=myhost                                   # ssh alias or hostname
SITE_REMOTE_ROOT=/home/you/sites                       # remote root directory
SITE_BASE_URL=https://myhost.tailnet-name.ts.net:8448  # public base URL
```

Only `push`, `url`, `list` and `unpublish` need these. The local subcommands `nav`, `search` and `check` never read them and work on a machine with no configuration at all.

## Push-side gating, not pull-side

The validation gate (lychee + orphan-page check) runs **on the publisher's
machine**, before the rsync. There is no CI, no GitHub Action, no
post-receive hook on myhost.

This is intentional. Server is a delivery surface, not a quality gate.
The page reaches it only after the local validator says it's reachable
and link-clean. If you find yourself wanting myhost to refuse bad
content, that's a sign the validation should be stricter on the
publisher side (extend `check-orphan-pages.py`, tighten `lychee.toml`),
not that myhost should grow gating logic.

## Provenance: `.published.json`

Each push writes a sidecar manifest into the published directory:

```json
{
  "project": "your-repo",
  "page": "contractor-site",
  "commit": "b36acb24937b",
  "published_utc": "2026-05-02T03:46:38Z",
  "source_repo": "git@github.com:you/your-repo.git",
  "url": "https://myhost.tailnet-name.ts.net:8448/your-repo/contractor-site/"
}
```

Fetch it any time to correlate the live page back to a git revision:

```bash
curl -sk https://myhost.tailnet-name.ts.net:8448/<repo>/<page>/.published.json | jq
```

The manifest is gitignored (regenerated on every push), so it never
pollutes the source repo's history. The git history of the source repo
already records every change that produced a publishable page.

## When NOT to use myhost

- The page must be **citable from outside** the tailnet — use jsDelivr or
  GitHub Pages instead so the URL resolves on the public internet.
- The page is part of a **public marketing or docs site** — that's a
  different audience and a different lifecycle; keep it on the public
  surface end-to-end.
- The page must survive the myhost host **going away** — treat myhost
  as ephemeral; for archival, also push to a public surface or commit
  the rendered HTML into the source repo's git history.

For everything else (contractor showcases, audit reports, internal
telemetry views, weekly digests, run summaries), myhost on the tailnet
is the lowest-friction option.

## Where this pattern lives in the world

The pipeline pattern is borrowed from a sibling patterns repo's `scripts/blob.sh` (which pushes large binary files to the same host via SSH+rsync). The HTML adaptation differs in two important ways:

1. **Path-mirrored, not content-addressed.** `blob.sh` URLs are
   `/<sha[:2]>/<sha>/<filename>`, which means the URL changes whenever
   the content does. That's correct for binary data fingerprinting; it's
   wrong for HTML pages a human is going to bookmark and re-visit. The
   site pattern uses `/<repo>/<page>/` so URLs are stable across edits.

2. **Validation gate before push.** `blob.sh` doesn't validate (binary
   blobs are opaque); the site pattern does (HTML has a notion of
   "broken"). Lychee + the orphan-page detector are the gate.

The two pipelines coexist on myhost — the SWS blob server runs on port
18130 (content-addressed binaries), and `tailscale serve path` runs on
port 8448 (path-mirrored HTML). They share the same tailnet ACL but
nothing else.
