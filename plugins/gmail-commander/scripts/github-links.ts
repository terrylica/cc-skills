/**
 * github-links — GitHub issue references in a Gmail draft body, and whether every reader can open them.
 *
 * Used by gmail-draft.ts (see GITHUB LINKS in its header). Three behaviours, all before any Gmail
 * token or network call:
 *   1. `linkGithubReferences`: issue and pull request references become short named links (`#12`,
 *      `acme/handbook#12`), so the html shows the number as a link and the plain part reads `#12 (URL)`.
 *   2. `checkGithubAccess`: every repository the body links to is looked up with `gh`; for a private
 *      one, each `--github-reader` is classified can-comment / invited-pending / no-access / unknown.
 *      `githubAccessProblems` is what makes gmail-draft refuse.
 *   3. `hasGithubAccessRemark` / `insertBeforeSignature`: the email says that the links open only for
 *      people with access, because GitHub shows a 404 page (not "ask for access") to everyone else.
 *
 * Deliberately self-contained (no import from gmail-draft.ts, which imports this file, and no
 * package), so it runs with bare `bun`. The three body-syntax rules it shares with gmail-draft.ts are
 * small copies, named as such below.
 */

/** Copy of gmail-draft.ts QUOTE_LINE_PATTERN: a `>` quotation line. */
const QUOTE_LINE_PATTERN = /^\s{0,3}>\s?/;

/** Copy of gmail-draft.ts splitUrlFromTrailingProse: prose punctuation and an unbalanced `)` are not part of a URL. */
function splitUrlFromTrailingProse(raw: string): { url: string; tail: string } {
  let url = raw;
  let tail = "";
  const punctuation = /[.,;:!?]+$/.exec(url);
  if (punctuation) {
    tail = punctuation[0];
    url = url.slice(0, -punctuation[0].length);
  }
  while (url.endsWith(")") && (url.match(/\)/g) ?? []).length > (url.match(/\(/g) ?? []).length) {
    url = url.slice(0, -1);
    tail = `)${tail}`;
  }
  return { url, tail };
}

/** Blank-line-separated paragraphs, as gmail-draft.ts splits them; a quotation is one whose every line is quoted. */
const paragraphsOf = (body: string): Array<{ text: string; quote: boolean }> =>
  body
    .replaceAll("\r\n", "\n")
    .split(/\n{2,}/)
    .map((b) => b.split("\n").filter((l) => l.trim().length > 0))
    .filter((lines) => lines.length > 0)
    .map((lines) => ({ text: lines.join(" "), quote: lines.every((l) => QUOTE_LINE_PATTERN.test(l)) }));

/** A GitHub login: letters, digits and single hyphens, never starting with one, at most 39 characters. */
export const GITHUB_LOGIN = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/;
/** `OWNER/REPO` as `--github-repo` takes it. */
export const GITHUB_REPO_SLUG = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/[A-Za-z0-9._-]+$/;

/** A full issue or pull request address (anything may follow the number: `/files`, `#issuecomment-1`). */
const GITHUB_ISSUE_URL = /^https?:\/\/(?:www\.)?github\.com\/([A-Za-z0-9][A-Za-z0-9-]{0,38})\/([A-Za-z0-9._-]+)\/(?:issues|pull)\/([1-9]\d*)(?=$|[/?#])/i;

/**
 * `OWNER/REPO#N` (groups 1-3) or a bare `#N` (group 4) in prose. Neither may be part of a longer
 * token: nothing word-like, `/`, `.`, `#` or `&` directly before (so `abc#12`, `path/#12`, `&#12;`
 * and `example.com/page#12` stay text), and nothing word-like, `#`, `-` or `.digit` after (so `#12a`,
 * `#12-3` and `#1.5` stay text). The number never starts with 0 and has at most seven digits, which
 * keeps `#000` and most colour codes out; `#fff` has no digits to match at all.
 */
const GITHUB_SHORT_REF =
  /(?<![\w./@#&-])([A-Za-z0-9][A-Za-z0-9-]{0,38})\/([A-Za-z0-9._-]+)#([1-9]\d{0,6})(?![\w#-]|\.\d)|(?<![\w&#/])#([1-9]\d{0,6})(?![\w#-]|\.\d)/g;

/** Stretches of a line that are never rewritten: code spans and existing named links (text AND target). */
const GITHUB_PROTECTED_SPAN = /(`[^`\n]+`|\[[^[\]\n]+\]\((?:[^()\s]|\([^()\s]*\))+\))/g;
/** A Markdown autolink `<https://…>` or a bare URL, as one split pattern (the autolink wins at `<`). */
const GITHUB_URL_TOKEN = /(<https?:\/\/[^\s<>]+>|https?:\/\/[^\s<>"'[\]]+)/g;

/**
 * `**[#12](URL)**` → `[**#12**](URL)`. The converter renders emphasis inside a link's text but not
 * around a link, so without this an author's `**#12**` would show its asterisks once it is linked.
 * Only labels this file makes (`#N`, `OWNER/REPO#N`) are matched.
 */
const EMPHASIS_AROUND_ISSUE_LINK = /(\*\*|\*)\[(#\d+|[\w.-]+\/[\w.-]+#\d+)\]\((https:\/\/github\.com\/[^\s)]+)\)\1/g;

/** The label a reference to `owner/repo#n` gets: `#n` inside the default repo, else `owner/repo#n`. */
function issueLabel(owner: string, repo: string, n: string, defaultRepo: string | undefined): string {
  return defaultRepo !== undefined && `${owner}/${repo}`.toLowerCase() === defaultRepo.toLowerCase() ? `#${n}` : `${owner}/${repo}#${n}`;
}

/** Rewrite one prose stretch (no code span, no named link inside it). */
function linkGithubProse(raw: string, defaultRepo: string | undefined): string {
  return raw
    .split(GITHUB_URL_TOKEN)
    .map((part, index) => {
      if (index % 2 === 0) {
        return part
          .replace(GITHUB_SHORT_REF, (whole, owner?: string, repo?: string, n?: string, bare?: string) => {
            if (owner !== undefined && repo !== undefined && n !== undefined) {
              return `[${issueLabel(owner, repo, n, defaultRepo)}](https://github.com/${owner}/${repo}/issues/${n})`;
            }
            if (bare !== undefined && defaultRepo !== undefined) return `[#${bare}](https://github.com/${defaultRepo}/issues/${bare})`;
            return whole;
          })
          .replace(EMPHASIS_AROUND_ISSUE_LINK, "[$1$2$1]($3)");
      }
      const autolink = part.startsWith("<");
      const { url, tail } = autolink ? { url: part.slice(1, -1), tail: "" } : splitUrlFromTrailingProse(part);
      const m = GITHUB_ISSUE_URL.exec(url);
      if (!m) return part;
      return `[${issueLabel(m[1] ?? "", m[2] ?? "", m[3] ?? "", defaultRepo)}](${url})${tail}`;
    })
    .join("");
}

/**
 * Turn GitHub issue and pull request references into short named links, on the RAW body, before it
 * is split into the two parts, so the html (`<a>#12</a>`) and the plain text (`#12 (URL)`) agree:
 *
 * - a bare `https://github.com/OWNER/REPO/issues/N` (or `/pull/N`, or `<…>`) → `[#N](URL)` when
 *   OWNER/REPO is `defaultRepo` (case-insensitive), else `[OWNER/REPO#N](URL)`;
 * - `OWNER/REPO#N` in prose → a named link to that issue;
 * - a bare `#N` → a named link ONLY when `defaultRepo` is given (a `#` number means many things).
 *
 * Never touched: `>` quotation lines (quotes are verbatim), lines inside a ``` fence, code spans,
 * the text and target of an existing named link, and a reference that is part of a longer token
 * (see GITHUB_SHORT_REF). Pure and deterministic.
 */
export function linkGithubReferences(body: string, defaultRepo?: string): string {
  let inFence = false;
  return body
    .split("\n")
    .map((line) => {
      if (/^\s{0,3}```/.test(line)) {
        inFence = !inFence;
        return line;
      }
      if (inFence || QUOTE_LINE_PATTERN.test(line)) return line;
      return line
        .split(GITHUB_PROTECTED_SPAN)
        .map((part, index) => (index % 2 === 1 ? part : linkGithubProse(part, defaultRepo)))
        .join("");
    })
    .join("\n");
}

/** First path segments of github.com that are not an owner, so `github.com/orgs/x` is not a repository. */
const GITHUB_NON_OWNER_SEGMENTS = new Set([
  "about", "account", "apps", "blog", "codespaces", "collections", "contact", "customer-stories", "dashboard",
  "enterprise", "enterprises", "events", "explore", "features", "issues", "join", "login", "logout", "marketplace",
  "new", "notifications", "organizations", "orgs", "pricing", "pulls", "search", "security", "settings", "site",
  "sponsors", "stars", "topics", "trending", "users",
]);

/**
 * Every repository the texts link to, as `owner/repo` in order of first appearance (deduplicated
 * case-insensitively). Any `https://github.com/OWNER/REPO…` address counts, not only issues: a link to
 * a private repository's file is the same 404 for a reader without access. Quotations are included,
 * because their links are just as clickable.
 */
export function collectGithubRepos(...texts: string[]): string[] {
  const seen = new Map<string, string>();
  for (const text of texts) {
    for (const m of text.matchAll(/https?:\/\/(?:www\.)?github\.com\/([A-Za-z0-9][A-Za-z0-9-]{0,38})\/([A-Za-z0-9._-]+)/gi)) {
      const owner = m[1] ?? "";
      const repo = (m[2] ?? "").replace(/\.git$/i, "").replace(/\.+$/, "");
      if (!repo || GITHUB_NON_OWNER_SEGMENTS.has(owner.toLowerCase())) continue;
      const slug = `${owner}/${repo}`;
      if (!seen.has(slug.toLowerCase())) seen.set(slug.toLowerCase(), slug);
    }
  }
  return [...seen.values()];
}

export type GithubVisibility = "public" | "private" | "internal" | "unknown";
/** `invitation-expired`: GitHub invitations lapse after 7 days and the stale one still blocks a new one; it must be deleted, then re-sent. */
export type GithubReaderStatus = "can-comment" | "invited-pending" | "invitation-expired" | "no-access" | "unknown";
export interface GithubRepoAccess {
  visibility: GithubVisibility;
  readers: Record<string, GithubReaderStatus>;
  /** Why a status is `unknown`, or anything else a person should read. */
  notes: string[];
}
export interface GithubAccessReport {
  repos: Record<string, GithubRepoAccess>;
  /** Repositories that only some people can open (`private` or `internal`). */
  privateRepos: number;
}

/** One `gh` call's outcome. `unavailable` means gh cannot run at all (missing, signed out). */
export type GhResult = { ok: true; stdout: string } | { ok: false; code: number | null; stderr: string; unavailable?: string };
export type GhRunner = (args: string[]) => Promise<GhResult>;

/** Each `gh` call is killed (its own PID, SIGKILL) after this long. */
export const GH_TIMEOUT_MS = 15_000;

/**
 * Run `gh` with a bounded lifetime: the child is killed by PID when the timeout passes, never by
 * name. A missing `gh` and a signed-out `gh` (exit 4) come back as `unavailable`, never as a throw.
 */
export async function runGh(args: string[], timeoutMs = GH_TIMEOUT_MS): Promise<GhResult> {
  const bin = Bun.which("gh");
  if (!bin) return { ok: false, code: null, stderr: "", unavailable: "gh CLI not found on PATH" };
  const proc = Bun.spawn([bin, ...args], {
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, GH_PROMPT_DISABLED: "1", GH_NO_UPDATE_NOTIFIER: "1", NO_COLOR: "1" },
  });
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    proc.kill("SIGKILL");
  }, timeoutMs);
  try {
    const [stdout, stderr, code] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text(), proc.exited]);
    if (timedOut) return { ok: false, code, stderr: `gh ${args.slice(0, 2).join(" ")} timed out after ${timeoutMs} ms` };
    if (code === 0) return { ok: true, stdout };
    if (code === 4 || /gh auth login/.test(stderr)) return { ok: false, code, stderr, unavailable: "gh is not signed in (run gh auth login)" };
    return { ok: false, code, stderr };
  } finally {
    clearTimeout(timer);
  }
}

/** On GitHub, read access is enough to comment on issues and review pull requests. */
const COMMENT_CAPABLE = new Set(["read", "triage", "write", "maintain", "admin"]);

const ghReason = (r: Extract<GhResult, { ok: false }>): string =>
  r.unavailable ?? (r.stderr.trim().split("\n")[0] || `gh exited ${r.code}`);

/**
 * Classify each reader for each repository, using `gh` only (no Gmail call has happened yet):
 * visibility from `repos/OWNER/REPO`; for a private or internal one, each reader's permission from
 * `repos/OWNER/REPO/collaborators/LOGIN/permission` (it already reflects team and organisation
 * access), and, for a reader without access, `repos/OWNER/REPO/invitations` (read once per repo) for
 * a pending invitation. A public repository: everyone `can-comment` (any signed-in user, unless the
 * issue is locked). When `gh` cannot run, everything is `unknown` with the reason in `notes`.
 */
export async function checkGithubAccess(repos: string[], readers: string[], gh: GhRunner = runGh): Promise<GithubAccessReport> {
  const out: Record<string, GithubRepoAccess> = {};
  let unavailable: string | null = null;
  const allUnknown = (note: string): GithubRepoAccess => ({
    visibility: "unknown",
    readers: Object.fromEntries(readers.map((l) => [l, "unknown" as const])),
    notes: [note],
  });
  for (const repo of repos) {
    if (unavailable) {
      out[repo] = allUnknown(unavailable);
      continue;
    }
    const meta = await gh(["api", `repos/${repo}`]);
    if (!meta.ok) {
      if (meta.unavailable) unavailable = meta.unavailable;
      out[repo] = allUnknown(`visibility: ${ghReason(meta)}`);
      continue;
    }
    let visibility: GithubVisibility = "unknown";
    try {
      const j = JSON.parse(meta.stdout) as { visibility?: string; private?: boolean };
      const v = j.visibility ?? (j.private === true ? "private" : j.private === false ? "public" : "");
      if (v === "public" || v === "private" || v === "internal") visibility = v;
    } catch {
      // stays unknown
    }
    const entry: GithubRepoAccess = { visibility, readers: {}, notes: [] };
    out[repo] = entry;
    if (visibility === "unknown") {
      entry.notes.push("visibility: gh returned no readable visibility");
      for (const l of readers) entry.readers[l] = "unknown";
      continue;
    }
    if (visibility === "public") {
      for (const l of readers) entry.readers[l] = "can-comment";
      continue;
    }
    let invited: Map<string, { expired: boolean; id: string }> | null = null;
    for (const login of readers) {
      if (unavailable) {
        entry.readers[login] = "unknown";
        continue;
      }
      const p = await gh(["api", `repos/${repo}/collaborators/${login}/permission`]);
      if (!p.ok) {
        if (p.unavailable) unavailable = p.unavailable;
        entry.readers[login] = "unknown";
        entry.notes.push(`${login}: ${ghReason(p)}`);
        continue;
      }
      let perm = "";
      let role = "";
      try {
        const j = JSON.parse(p.stdout) as { permission?: string; role_name?: string };
        perm = j.permission ?? "";
        role = j.role_name ?? "";
      } catch {
        // falls through to unknown below
      }
      if (COMMENT_CAPABLE.has(perm) || COMMENT_CAPABLE.has(role)) {
        entry.readers[login] = "can-comment";
        continue;
      }
      if (perm !== "none") {
        entry.readers[login] = "unknown";
        entry.notes.push(`${login}: unreadable permission ${JSON.stringify(perm)}`);
        continue;
      }
      if (invited === null) {
        const inv = await gh(["api", `repos/${repo}/invitations`, "--paginate", "--jq", '.[] | select(.invitee != null) | "\\(.invitee.login)\\t\\(.expired == true)\\t\\(.id)"']);
        if (inv.ok) {
          invited = new Map();
          for (const line of inv.stdout.split("\n")) {
            const [who, exp, id] = line.trim().split("\t");
            if (!who) continue;
            const prev = invited.get(who.toLowerCase());
            // A live invitation wins over an expired one for the same person.
            if (!prev || prev.expired) invited.set(who.toLowerCase(), { expired: exp === "true", id: id ?? "" });
          }
        } else {
          if (inv.unavailable) unavailable = inv.unavailable;
          invited = new Map();
          entry.notes.push(`invitations: ${ghReason(inv)} (a pending invitation could not be seen)`);
        }
      }
      const hit = invited.get(login.toLowerCase());
      entry.readers[login] = !hit ? "no-access" : hit.expired ? "invitation-expired" : "invited-pending";
      if (hit?.expired) entry.notes.push(`${login}: invitation ${hit.id} has expired`);
    }
  }
  const privateRepos = Object.values(out).filter((r) => r.visibility === "private" || r.visibility === "internal").length;
  return { repos: out, privateRepos };
}

const isRestricted = (v: GithubVisibility): boolean => v === "private" || v === "internal";

/**
 * Why the draft must not be made: one line per restricted repository with no readers named, and per
 * reader who has no access or whose access could not be verified. Empty means it may be made. A
 * repository whose visibility is `unknown` (gh missing or signed out) does not refuse; it is warned
 * about and gets the access note.
 */
export function githubAccessProblems(report: GithubAccessReport, readers: string[]): string[] {
  const problems: string[] = [];
  for (const [repo, r] of Object.entries(report.repos)) {
    if (!isRestricted(r.visibility)) continue;
    if (readers.length === 0) {
      problems.push(`${repo} (${r.visibility}): no --github-reader given; name the GitHub login of everyone who will open the links`);
      continue;
    }
    for (const [login, status] of Object.entries(r.readers)) {
      if (status === "no-access") problems.push(`${repo} (${r.visibility}): ${login} has no access and no pending invitation`);
      if (status === "invitation-expired") problems.push(`${repo} (${r.visibility}): ${login}'s invitation has EXPIRED (GitHub invitations last 7 days), so the links show them a 404 page`);
      if (status === "unknown") problems.push(`${repo} (${r.visibility}): ${login}'s access could not be verified (${r.notes.filter((n) => n.startsWith(`${login}:`) || !/^[\w-]+:/.test(n)).join("; ") || "see notes"})`);
    }
  }
  return problems;
}

/** The refusal printed (exit 1) when githubAccessProblems is not empty and no --github-access-ok was given. */
export function formatGithubAccessRefusal(problems: string[], report: GithubAccessReport): string {
  const invites = Object.entries(report.repos).flatMap(([repo, r]) =>
    Object.entries(r.readers).flatMap(([login, s]) => {
      const put = `gh api -X PUT repos/${repo}/collaborators/${login} -f permission=pull`;
      if (s === "no-access") return [put];
      if (s !== "invitation-expired") return [];
      const id = r.notes.map((n) => n.match(new RegExp(`^${login}: invitation (\\d+) has expired$`))?.[1]).find(Boolean) ?? "<id>";
      return [`gh api -X DELETE repos/${repo}/invitations/${id} && ${put}`];
    }),
  );
  return (
    "REFUSED: the body links to a private GitHub repository that a reader may not be able to open (GitHub shows a 404 page to anyone without access):\n  " +
    problems.join("\n  ") +
    "\nFix: invite each reader (read access is enough to comment and review)" +
    (invites.length > 0 ? `:\n  ${invites.join("\n  ")}\n` : ", ") +
    "and re-run with --github-reader <login> for every person who will open the links; " +
    "or pass --github-access-ok '<reason>' to make the draft knowingly."
  );
}

/** The paragraph appended when the body links to a private repository and says nothing about access. */
export const GITHUB_ACCESS_NOTE =
  "These GitHub links are in a private repository: they open only when you are signed in to GitHub with an account that has access. If one shows a 404 page, accept your invitation first (GitHub emails it), or reply and I will send one.";

export type AccessNoteOutcome = "present" | "appended" | "suppressed" | "not-needed";

/**
 * Does the body already tell the reader about access? Deliberately simple and conservative (it would
 * rather append a second remark than miss one): some prose paragraph (not a `>` quotation), read with
 * its URLs removed, must name `access`, `invitation` or `invite(d)` AND `GitHub`, `link(s)` or
 * `issue(s)`. When a reader's invitation is still pending, the remark must mention the invitation.
 */
export function hasGithubAccessRemark(body: string, invitationPending = false): boolean {
  const remark = invitationPending ? /\b(?:invitation|invited?)\b/i : /\b(?:access|invitation|invited?)\b/i;
  return paragraphsOf(body).some((b) => {
    if (b.quote) return false;
    const text = b.text.replace(/https?:\/\/\S+/g, " ");
    return remark.test(text) && /\b(?:github|links?|issues?)\b/i.test(text);
  });
}

/** The provenance footer line some drafts end with. */
const FOOTER_BLOCK = /^\s*(?:parked by|via claude code)\b/i;
/** The first line of a sign-off block ("Best," / name). */
const SIGN_OFF_LINE = /^\s*(?:best|best regards|best wishes|regards|kind regards|warm regards|many thanks|thanks|thank you|cheers|sincerely|yours sincerely|all the best|warmly)\s*[,.!]?\s*$/i;

/**
 * Insert a paragraph where a reader expects it: before the provenance footer (a final paragraph
 * starting `Parked by` or `via Claude Code`), and before a sign-off (`Best,` / `Thanks,` …, alone or
 * followed by one short name paragraph) that precedes it; otherwise at the end.
 */
export function insertBeforeSignature(body: string, paragraph: string): string {
  const blocks = body.replaceAll("\r\n", "\n").split(/\n{2,}/).filter((b) => b.trim().length > 0);
  let at = blocks.length;
  if (at > 0 && FOOTER_BLOCK.test(blocks[at - 1] ?? "")) at--;
  const firstLine = (i: number): string => (blocks[i] ?? "").split("\n")[0] ?? "";
  if (at > 0 && SIGN_OFF_LINE.test(firstLine(at - 1))) at--;
  else if (at > 1 && SIGN_OFF_LINE.test(firstLine(at - 2)) && (blocks[at - 1] ?? "").length <= 80) at -= 2;
  blocks.splice(at, 0, paragraph);
  return `${blocks.map((b) => b.replace(/\s+$/, "")).join("\n\n")}\n`;
}

/** Everything the GitHub step decided, for main and for the JSON line. */
export interface GithubLinksResult {
  body: string;
  githubAccess: GithubAccessReport & { accessOk: string | null };
  accessNote: AccessNoteOutcome;
  /** Set when the draft must not be made; main prints it and exits 1. */
  refusal: string | null;
  /** Lines for stderr that do not stop the draft. */
  warnings: string[];
}

/**
 * The whole GitHub step, before any Gmail token or network call: link the references (skipped with
 * an authored --html part, which is verbatim), collect the repositories, check every reader, refuse
 * or warn, and add the access note when one is needed and missing.
 */
export async function prepareGithubLinks(
  rawBody: string,
  opts: { githubRepo?: string | undefined; readers: string[]; accessOk?: string | undefined; noAccessNote: boolean; authoredHtml?: string | undefined },
  gh: GhRunner = runGh,
): Promise<GithubLinksResult> {
  const body = opts.authoredHtml === undefined ? linkGithubReferences(rawBody, opts.githubRepo) : rawBody;
  const repos = collectGithubRepos(body, opts.authoredHtml ?? "");
  const report: GithubAccessReport = repos.length > 0 ? await checkGithubAccess(repos, opts.readers, gh) : { repos: {}, privateRepos: 0 };
  const githubAccess = { ...report, accessOk: opts.accessOk ?? null };
  const warnings: string[] = [];
  for (const [repo, r] of Object.entries(report.repos)) {
    if (r.visibility === "unknown") warnings.push(`GITHUB: could not tell whether ${repo} is private (${r.notes.join("; ")}); the access note is added to be safe.`);
    for (const [login, s] of Object.entries(r.readers)) {
      if (s === "invited-pending") warnings.push(`GITHUB: ${login} has a pending invitation to ${repo}; the links open for them only after they accept it.`);
    }
  }
  const problems = githubAccessProblems(report, opts.readers);
  if (problems.length > 0 && opts.accessOk === undefined) {
    return { body, githubAccess, accessNote: "not-needed", refusal: formatGithubAccessRefusal(problems, report), warnings };
  }
  if (problems.length > 0) warnings.push(`GITHUB: proceeding despite ${problems.length} access problem(s) (--github-access-ok: ${opts.accessOk}):\n  ${problems.join("\n  ")}`);

  const values = Object.values(report.repos);
  const needed = values.some((r) => isRestricted(r.visibility) || r.visibility === "unknown");
  const pending = values.some((r) => Object.values(r.readers).includes("invited-pending"));
  let accessNote: AccessNoteOutcome;
  let out = body;
  if (!needed) accessNote = "not-needed";
  else if (opts.noAccessNote) accessNote = "suppressed";
  else if (hasGithubAccessRemark(body, pending)) accessNote = "present";
  else if (opts.authoredHtml !== undefined) {
    return {
      body,
      githubAccess,
      accessNote: "not-needed",
      refusal:
        "REFUSED: the body links to a private GitHub repository but does not tell the reader that the links open only with access, " +
        "and an authored --html part cannot have the note added. Write the remark into both --body and --html " +
        `(for example: "${GITHUB_ACCESS_NOTE}"), or pass --no-github-access-note.`,
      warnings,
    };
  } else {
    out = insertBeforeSignature(body, GITHUB_ACCESS_NOTE);
    accessNote = "appended";
  }
  return { body: out, githubAccess, accessNote, refusal: null, warnings };
}

