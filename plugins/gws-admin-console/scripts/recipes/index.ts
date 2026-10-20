// The recipe registry. A recipe is: a console URL, verbs, flags (data), and a run() that turns flags into
// FormOps and drives them. Add a recipe by writing one module like gmail-default-routing.ts and listing it here.
import type { FlagSpec, Flags } from "../lib/args.ts";
import type { Driver } from "../lib/page.ts";
import * as gmailDefaultRouting from "./gmail-default-routing.ts";

export interface Recipe {
  name: string;
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
    summary: "Gmail › Default routing: ensure one rule (match envelope recipients, then modify the message), idempotently, with read-back",
    url: gmailDefaultRouting.URL,
    verbs: { ensure: "create the rule if missing; no-op when identical; report (or --update) when it differs; --verify reads back only; --dry-run fills then cancels" },
    flags: gmailDefaultRouting.FLAGS,
    validate: (f) => void gmailDefaultRouting.specFromFlags(f),
    run: gmailDefaultRouting.run,
  },
};
