# Registry schema `published.v1`

One file per repository that publishes pages, listing every link that repository has ever published, one entry per link. The repository's deploy step writes it after verifying the URLs; people edit it only to add notes. The sitemap reads it (from the repository's default branch) and never keeps a copy.

## File

TOML (shown) or JSON with the same keys. The first key names the schema:

```toml
schema = "published.v1"

[[entry]]
id = "site-name:page-name"
channel = "pages"
status = "live"
title = "What the page shows"
url = "https://example.pages.dev/<secret path>/page-name"
site = "site-name"
source = "scripts/build_page.py"
built_from = "abc1234def"
changed_at = "2026-11-14T22:18:00Z"
permanent = true
```

## Fields

| Field        | Required             | Meaning                                                                                                                                                                 |
| ------------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`         | yes                  | Stable and unique within the registry: `<site>:<page>` for a page of a site, `<channel>:<slug>` otherwise. Never reused for another link                                |
| `channel`    | yes                  | How it is served: `pages`, `workers`, `artifact` (a transient share link), or the host's own short name                                                                 |
| `status`     | yes                  | `live`, `expired` (a transient link past its lifetime), or `revoked` (taken down, or removed from the site). Entries are never deleted: a revoked link stays as history |
| `title`      | yes                  | The page's title as readers see it                                                                                                                                      |
| `url`        | yes                  | The address in force                                                                                                                                                    |
| `site`       | yes                  | The project, Worker or site it belongs to (the unit a deploy publishes)                                                                                                 |
| `source`     | yes                  | Repository path of the page's file or builder; `external: <what>` for a page built elsewhere                                                                            |
| `built_from` | yes, for built pages | The commit the deployed page was built from                                                                                                                             |
| `changed_at` | recommended          | ISO 8601 UTC time of the last commit that changed the page's inputs: what the live age marker shows, and what the sitemap colours each link by                          |
| `permanent`  | no                   | `true` for a page meant to stay; transient links (`artifact`) are `false`                                                                                               |
| `account`    | no                   | A label for the hosting account (never an id that grants access, never a secret)                                                                                        |
| `replaced`   | no                   | Earlier URLs of the same page (a moved site, a re-shared artifact); the sitemap shows only `url`                                                                        |
| `expires`    | no                   | For transient links: ISO 8601 UTC expiry                                                                                                                                |
| `note`       | no                   | Why the entry is in its state, in a sentence                                                                                                                            |

A registry may carry extra keys of its own (a renewal host, a file path); readers ignore keys they do not know.

## Rules

- **One link, one entry, one registry.** A page moved to a new address keeps its `id` and lists the old address in `replaced`.
- **Written by the deploy step, after the checks pass.** A failed check records nothing.
- **Revoke, never delete.** The registry is the history of what was ever public.
- **No secrets.** A secret path in a URL is not a credential (rotating it revokes every link), but tokens, account ids that grant access and personal data never go here.
