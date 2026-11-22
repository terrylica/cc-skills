#!/usr/bin/env bun
/**
 * gmail-drafts-audit — sweep a mailbox's Drafts folder for drafts that are no longer in play.
 *
 * `gmail-draft.ts` checks each new draft against the folder as it is made. This is the sweep for the
 * moment a batch changes shape: items merged, withdrawn, re-ranked or redrafted, when the drafts in
 * play are known (a manifest of draft ids) and everything else to the same people is suspect.
 *
 * USAGE
 *   bun gmail-drafts-audit.ts --account <tokenbase>
 *     [--keep <draftId>[,<draftId>...]]...  # the drafts still in play; repeatable
 *     [--keep-file <file>]...                # any file; every draft id in it (r123… / r-123…) is kept
 *     [--prune]                              # delete what is flagged, then prove it is gone
 *
 * FINDINGS (see lingering-drafts.ts)
 *   superseded   a newer draft repeats it: same sender, a shared recipient, the same subject once
 *                Braille Tally cells, "Re:" and case are ignored
 *   outOfPlay    only with a keep list: same sender and a shared recipient as a kept draft, not kept
 *   missingKept  kept ids that are not in the folder (already sent, deleted or redrafted). --prune
 *                REFUSES while any is missing: a stale keep list would otherwise delete the very
 *                draft that replaced the missing one. Fix the list first.
 *
 * Only To addresses count: a draft whose To shares no address with a kept draft's To is never
 * flagged, even when the same person is copied on both, so unrelated drafts are left alone.
 *
 * OUTPUT: one JSON object {account, scanned, kept, superseded, outOfPlay, missingKept, pruned}.
 * EXIT: 0 nothing lingers (or everything flagged was pruned and is gone) · 1 usage or failure, or
 * --prune refused because a kept id is missing · 2 could not read the whole Drafts folder ·
 * 3 drafts linger (listed; re-run with --prune to delete them).
 */
import { accessToken, api } from "./gmail-draft.ts";
import { auditDrafts, describe, listDraftMeta, type DraftMeta } from "./lingering-drafts.ts";

export const USAGE = "usage: gmail-drafts-audit.ts --account <tokenbase> [--keep <id>[,<id>...]]... [--keep-file <file>]... [--prune]";

const DRAFT_ID = /\br-?\d{12,}\b/g;

export interface AuditArgs {
  account: string;
  keep: string[];
  keepFiles: string[];
  prune: boolean;
}

export function parseAuditArgs(argv: string[]): AuditArgs {
  const values = (flag: string): string[] =>
    argv.flatMap((a, i) => {
      if (a !== flag) return [];
      const v = argv[i + 1];
      if (!v || v.startsWith("--")) throw new Error(`${flag} needs a value\n${USAGE}`);
      return [v];
    });
  const account = values("--account")[0] ?? process.env.GMAIL_DRAFT_ACCOUNT;
  if (!account) throw new Error(USAGE);
  const keep = values("--keep").flatMap((v) => v.split(",").map((s) => s.trim()).filter(Boolean));
  return { account, keep, keepFiles: values("--keep-file"), prune: argv.includes("--prune") };
}

/** Every draft id written anywhere in a text (a manifest, a log, a note). */
export function draftIdsIn(text: string): string[] {
  return [...new Set(text.match(DRAFT_ID) ?? [])];
}

const brief = (d: DraftMeta) => ({ id: d.id, to: d.to, subject: d.subject, date: d.date ? new Date(d.date).toISOString() : null });

if (import.meta.main) {
  let args: AuditArgs;
  const keep = new Set<string>();
  try {
    args = parseAuditArgs(process.argv.slice(2));
    for (const id of args.keep) keep.add(id);
    for (const f of args.keepFiles) for (const id of draftIdsIn(await Bun.file(f).text())) keep.add(id);
  } catch (e) {
    console.error((e as Error).message);
    process.exit(1);
  }
  let drafts: DraftMeta[];
  const at = await accessToken(args.account);
  const call = (path: string) => api(at, path);
  try {
    drafts = await listDraftMeta(call);
  } catch (e) {
    console.error(`could not read the Drafts folder: ${(e as Error).message}`);
    process.exit(2);
  }
  const found = auditDrafts(drafts, keep);
  const flagged = [...found.superseded.map((s) => s.draft), ...found.outOfPlay];
  const pruned: string[] = [];
  let lingering = flagged;
  if (args.prune && found.missingKept.length > 0) {
    console.error(
      `REFUSED --prune: ${found.missingKept.length} kept id(s) are not in the Drafts folder (${found.missingKept.join(", ")}). ` +
        `If one was redrafted, its replacement is among the flagged drafts below and would be deleted. Correct the keep list, then re-run. Nothing was deleted.`,
    );
    for (const d of flagged) console.error(`flagged     ${describe(d)}`);
    process.exit(1);
  }
  if (args.prune && flagged.length > 0) {
    for (const d of flagged) {
      await api(at, `drafts/${d.id}`, "DELETE");
      pruned.push(d.id);
    }
    const left = new Set((await listDraftMeta(call)).map((d) => d.id));
    lingering = flagged.filter((d) => left.has(d.id));
  }
  for (const s of found.superseded) console.error(`superseded  ${describe(s.draft)}\n            by ${describe(s.by)}`);
  for (const d of found.outOfPlay) console.error(`out of play ${describe(d)}`);
  for (const id of found.missingKept) console.error(`kept but not in the folder: ${id}`);
  if (pruned.length > 0) console.error(`pruned ${pruned.length}: ${pruned.join(", ")}`);
  console.log(
    JSON.stringify({
      account: args.account,
      scanned: drafts.length,
      kept: [...keep],
      superseded: found.superseded.map((s) => ({ ...brief(s.draft), by: s.by.id })),
      outOfPlay: found.outOfPlay.map(brief),
      missingKept: found.missingKept,
      pruned,
    }),
  );
  process.exit(lingering.length > 0 ? 3 : 0);
}
