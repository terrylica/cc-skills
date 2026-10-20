// The recipe registry. A recipe is: a recipe family (one vendor console, with its login classifier), a console URL,
// verbs, flags (data), and a run() that turns flags into FormOps and drives them. Add a recipe by writing one module
// under recipes/<family>/ like google-admin/gmail-default-routing.ts and listing it here.
import type { FlagSpec, Flags } from "../lib/args.ts";
import type { Family } from "../lib/gate.ts";
import type { Driver } from "../lib/page.ts";
import { GOOGLE_ADMIN } from "./google-admin/family.ts";
import * as gmailDefaultRouting from "./google-admin/gmail-default-routing.ts";

export interface Recipe {
  name: string;
  family: Family;
  summary: string;
  url: string;
  verbs: Record<string, string>;
  flags: FlagSpec[];
  /** Optional pure validation, run before any browser is opened. */
  validate?: (f: Flags) => void;
  run: (verb: string, f: Flags, d: Driver, gate: () => Promise<void>) => Promise<{ code: number; result: Record<string, unknown> }>;
}

export const RECIPES: Record<string, Recipe> = {
  "gmail-default-routing": {
    name: "gmail-default-routing",
    family: GOOGLE_ADMIN,
    summary: "Gmail › Default routing: ensure one rule (match envelope recipients, then modify the message), idempotently, with read-back",
    url: gmailDefaultRouting.URL,
    verbs: { ensure: "create the rule if missing; no-op when identical; report (or --update) when it differs; --verify reads back only; --dry-run fills then cancels" },
    flags: gmailDefaultRouting.FLAGS,
    validate: (f) => void gmailDefaultRouting.specFromFlags(f),
    run: gmailDefaultRouting.run,
  },
};
