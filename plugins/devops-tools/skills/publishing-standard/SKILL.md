---
name: publishing-standard
description: The must-haves for every HTML page an agent creates or publishes, on any host (Cloudflare Pages or Workers, an Orca artifact, GitHub Pages, any static host) - a live "changed N ago" marker with a heat dot, the exact build time, version and commit, the source path, a link to the site's index, one record in exactly one registry, and a place on the sitemap that links every site together. Principle-based; styling is free. TRIGGERS - create an HTML page, publish a page, deploy a static site, wrangler pages deploy, wrangler deploy, orca artifacts share, page provenance, last updated, changed ago, published registry, sitemap of all pages.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Publishing standard

> **Self-Evolving Skill**: This skill improves through use. If a rule here is wrong, a host behaves differently, or a workaround was needed, fix this file immediately, don't defer. Only update for real, reproducible issues.

Every page a reader opens should answer three questions without anyone asking: **how fresh is this, where does it come from, and where are its siblings?** This skill states what every published HTML page carries and how a published link is recorded. It says nothing about looks: use any stylesheet, framework or host. The host-specific skills (deploying, styling, artifacts) do the work; this one is the checklist they all meet.

## On every page

| Must-have              | What it is                                                                                                                                                                                                                                                                    | Why                                                                                                                                                          |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Live age**           | "changed 3 hours ago", worked out in the reader's browser from the Unix time of the last change to the page's inputs (the commit that last touched its source or builder), refreshed every minute, with a small dot coloured by age on a heat scale and a legend on the index | A page goes stale while it stays open, and "3 days ago" written at build time is wrong the next day. Colour lets a reader scan a whole index for what is new |
| **Exact moment**       | That change's date and time, written at build time, in the time zones the readers use, each zone named                                                                                                                                                                        | A fixed past moment does not need the browser, and a browser whose time-zone database predates a rule change prints the wrong offset                         |
| **Version and commit** | The release version and the commit the page was built from                                                                                                                                                                                                                    | Lets anyone rebuild the page or find the change that produced it                                                                                             |
| **Source**             | The repository path of the page's file or of the script that builds it                                                                                                                                                                                                        | Answers "where do I change this"                                                                                                                             |
| **Way back**           | A bar on the page linking to its site's index; every index appears on the sitemap                                                                                                                                                                                             | A single page link passed around still leads to everything else                                                                                              |

The live age marker needs no library: the browser's own `Intl.RelativeTimeFormat` words it in any language (Baseline 2020: Chrome 71, Firefox 65, Safari 14), and nine pre-computed heat colours carry the age. Copy the snippet in [references/age-marker.md](references/age-marker.md); it is about 40 lines of inline CSS and script, so it works on hosts and in regions where a CDN is blocked.

Rules for the marker:

- **Text in ordinary ink.** The dot carries the colour; the words carry the same information, so nothing depends on colour alone.
- **Sequential heat, never a rainbow.** Hot (just changed) through amber to neutral grey (a month or more), lightness rising monotonically. A rainbow reads as unrelated categories and fails colour-blind readers.
- **Log scale of age.** Minutes and hours need finer steps than weeks.
- **A legend wherever markers appear in a list** (the index).
- **No-script fallback.** The page still shows the exact moment; the marker shows a neutral word until the script runs.

## One source of truth for what is published

Each published link is recorded in **exactly one registry**:

- **A repository that builds pages keeps the registry of its own links**, written by its deploy step (the step that has just verified the URLs), never by hand and never copied elsewhere.
- **A link with no repository** (a one-off upload) goes in the sitemap's own registry.
- **The sitemap reads every registry and copies none of them.** It is a view, rebuilt after each deploy is recorded.
- **The sitemap also lists what the host itself reports** (its API's inventory of projects and Workers) and flags anything recorded nowhere, until the repository that builds it records it.

Every registry uses one schema, `published.v1`: [references/registry-schema.md](references/registry-schema.md). A registry in another shape gets a reader in the sitemap until it is converted, never a second copy of its entries.

## Audiences

A sitemap shows every link it knows. Link it only from pages whose every possible reader may see every link on it: a page given to a client, a collaborator or the public links to its own site's index, and at most to a sitemap built for that audience (one view per account or audience, read from the same registries). Unlisted pages stay unlisted: no search-engine indexing (robots.txt, `X-Robots-Tag`, `<meta name="robots">`), reachable only by their URL.

## Sequence for a publish

1. Build the pages from committed sources (refuse, or mark the page, when the working tree differs).
2. Check the must-haves above on every page, and the index's legend.
3. Deploy.
4. Verify every page URL answers 200 (and, for pages behind a secret path, that the root and other paths answer 404). To check how a page looks, take a screenshot with chrome-headless-shell (tier 2 of `Skill(chrome-profiles:browser-automation)`), not Lightpanda, which draws no CSS layout.
5. Record the deployed links in the repository's registry (`published.v1`), commit and merge.
6. Regenerate the sitemap.

## Anti-patterns

- "Updated 3 days ago" written into the HTML at build time.
- One colour for every age, or the age shown only by colour.
- Converting a fixed past moment to local time in the browser.
- A link recorded in two registries, or a sitemap that keeps its own copy of another registry's entries.
- A page with no way back to its index.
- Loading a date or colour library from a CDN for this.

## Related skills

- `devops-tools:cloudflare-workers-publish`: deploying static pages to Cloudflare Workers.
- `html-showcase:page-template`: a site's own navigation and provenance footer.
- `doc-tools:static-page-stack`: the styling stack.
- `orca-tools:full-width-artifact`: pages shared as Orca artifacts.
- `dataviz`: charts inside a page, and the colour rules the heat scale follows.

## Post-Execution Reflection

After this skill completes, reflect before closing the task:

0. **Locate yourself.** — Find this SKILL.md's canonical path (Glob for this skill's name) before editing. All corrections target THIS file and its sibling references/ — never other documentation.
1. **What failed?** — Fix the instruction that caused it. If it could recur, add it as an anti-pattern.
2. **What worked better than expected?** — Promote it to recommended practice. Document why.
3. **What drifted?** — Any script, reference, or external dependency that no longer matches reality gets fixed now.
4. **Log it.** — Every change gets an evolution-log entry with trigger, fix, and evidence.

## Do NOT defer. The next invocation inherits whatever you leave behind
