/**
 * Keep references to non-public repositories out of published release notes.
 *
 * WHY. A commit message in this public repository can mention an issue or pull request in
 * another repository, as `owner/repo#123` or as a github.com URL. semantic-release then
 * publishes it twice: the parser lifts every `owner/repo#N` into the commit's `references`,
 * which the commit template renders as ", closes owner/repo#N" next to the bullet, and the
 * body is printed below it. When the other repository is private, that is a private
 * identifier on the CHANGELOG and the GitHub release page. It happened on 2026-10-18: one
 * reference in the prose of a fix commit stopped `release-full` at the privacy gate.
 *
 * WHAT. Every cross-repository reference is checked against the repository's visibility on
 * GitHub. A reference to this repository, or to a repository GitHub reports as public, is
 * kept unchanged (upstream bug reports stay cited). Anything else is replaced by generic
 * wording, and dropped from `references`.
 *
 * FAIL CLOSED. "Public" means GitHub said so. A lookup that fails (no gh, no network, a
 * 404 because the token cannot see the repository) counts as not public, so the worst case
 * offline is that a public upstream reference is generalised, never that a private one is
 * published.
 *
 * NEVER PRINT A SLUG. Logging which repository was redacted would move the identifier from
 * the notes into release logs and agent transcripts, so only a count is reported.
 */

import { spawnSync } from "node:child_process";

export type IsPublic = (slug: string) => boolean;

export type Reference = {
  owner?: string | null;
  repository?: string | null;
  issue?: string;
  [key: string]: unknown;
};

const GH_LOOKUP_TIMEOUT_MS = 15_000;

/** Wording that replaces a redacted reference. No number: GitHub would autolink a bare
 *  `#N` in a release body to THIS repository's issue N, which would be a wrong link. */
export const REDACTED_ISSUE = "an issue in a private repository";
export const REDACTED_URL = "a link to a private repository";

/** `owner/repo#123`, not preceded by a character that would make it part of a path or URL. */
const SLUG_ISSUE = /(?<![\w./-])([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))\/([A-Za-z0-9._-]+)#(\d+)\b/g;

/** `https://github.com/owner/repo` plus any path, query or fragment. */
const GITHUB_URL = /https?:\/\/(?:www\.)?github\.com\/([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))\/([A-Za-z0-9._-]+?)(?:\.git)?(?=[/?#\s)\]>"'`,;]|$)[^\s)\]>"'`]*/g;

/** One `gh api` call per distinct repository per process, killed if it hangs. */
export function githubVisibilityLookup(): IsPublic {
  const cache = new Map<string, boolean>();
  return (slug) => {
    const key = slug.toLowerCase();
    const known = cache.get(key);
    if (known !== undefined) return known;
    const r = spawnSync("gh", ["api", `repos/${slug}`, "--jq", ".visibility"], {
      encoding: "utf8",
      timeout: GH_LOOKUP_TIMEOUT_MS,
      killSignal: "SIGKILL",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const isPublic = r.status === 0 && r.stdout.trim() === "public";
    cache.set(key, isPublic);
    return isPublic;
  };
}

export class ForeignReferenceRedactor {
  readonly own: string | null;
  readonly ownOwner: string | null;
  readonly isPublic: IsPublic;
  redactedCount = 0;

  constructor(owner: string | null | undefined, repository: string | null | undefined, isPublic: IsPublic) {
    this.own = owner && repository ? `${owner}/${repository}`.toLowerCase() : null;
    this.ownOwner = owner || null;
    this.isPublic = isPublic;
  }

  /** True when a reference to `owner/repo` may be published. */
  allowed(owner: string, repository: string): boolean {
    const slug = `${owner}/${repository}`;
    if (this.own !== null && slug.toLowerCase() === this.own) return true;
    return this.isPublic(slug);
  }

  /** Generalise `owner/repo#N` and github.com URLs that point at non-public repositories. */
  text(value: string | null | undefined): string | null | undefined {
    if (!value) return value;
    const issues = value.replace(SLUG_ISSUE, (whole, owner: string, repo: string) => {
      if (this.allowed(owner, repo)) return whole;
      this.redactedCount++;
      return REDACTED_ISSUE;
    });
    return issues.replace(GITHUB_URL, (whole, owner: string, repo: string) => {
      if (this.allowed(owner, repo)) return whole;
      this.redactedCount++;
      return REDACTED_URL;
    });
  }

  /** Drop parsed references to non-public repositories; same-repository `#N` stays.
   *  The parser reads `repo#N` as repository "repo" with no owner, which GitHub resolves
   *  under this repository's owner, so that is the owner checked. */
  references<T extends Reference>(refs: T[]): T[] {
    return refs.filter((ref) => {
      if (!ref.repository) return true;
      const owner = ref.owner || this.ownOwner;
      if (owner && this.allowed(owner, ref.repository)) return true;
      this.redactedCount++;
      return false;
    });
  }
}
