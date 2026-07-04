#!/usr/bin/env bun
/**
 * batch_create_pushover_apps.ts — batch-create Pushover apps from a plan JSON:
 * create-app (name + description) then optionally edit-app (upload icon).
 * Records each new app's last-6 token chars for the inventory.
 *
 * Plan path: $CREATE_PLAN (default /tmp/po_sounds/createnew.json), an array of
 *   { "new_name": string, "desc": string, "icon"?: string }.
 *
 * Ported from batch_create_pushover_apps.py — reuses the exported session +
 * create/edit helpers from pushover_headless_web_control.ts (single source).
 */

import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import process from "node:process";
import {
  blankOptions,
  createApp,
  editApp,
  login,
  resolveCredentials,
  withDashboard,
} from "./pushover_headless_web_control.ts";

interface PlanItem {
  readonly new_name: string;
  readonly desc: string;
  readonly icon?: string;
}

interface BatchResult {
  readonly name: string;
  readonly created?: boolean;
  readonly slug?: string;
  readonly token_last6?: string | null;
  readonly icon?: boolean;
  readonly error?: string;
}

const lastSegment = (value: string): string => value.split("/").at(-1) ?? "";

async function createOne(
  pg: Parameters<Parameters<typeof withDashboard>[1]>[0],
  item: PlanItem,
  userKey: string,
): Promise<BatchResult> {
  try {
    const result = await createApp(
      pg,
      blankOptions({ name: item.new_name, desc: item.desc, reveal: true }),
      userKey,
    );
    const slug = lastSegment(String(result.app_url ?? ""));
    const token = typeof result.token === "string" ? result.token : "";
    let iconed = false;
    if (slug && item.icon && existsSync(item.icon)) {
      await editApp(pg, blankOptions({ slug, icon: item.icon }));
      iconed = true;
    }
    return {
      name: item.new_name,
      created: result.created === true,
      slug,
      token_last6: token ? token.slice(-6) : null,
      icon: iconed,
    };
  } catch (error) {
    return { name: item.new_name, error: (error instanceof Error ? error.message : String(error)).slice(0, 140) };
  }
}

async function main(): Promise<void> {
  const creds = resolveCredentials();
  const planPath = process.env.CREATE_PLAN ?? "/tmp/po_sounds/createnew.json";
  const plan = JSON.parse(await readFile(planPath, "utf8")) as PlanItem[];

  const results = await withDashboard(true, async (pg) => {
    await login(pg, creds);
    const collected: BatchResult[] = [];
    for (const item of plan) {
      collected.push(await createOne(pg, item, creds.userKey));
    }
    return collected;
  });

  process.stdout.write(`${JSON.stringify(results, null, 2)}\n`);
  const created = results.filter((r) => r.created).length;
  process.stdout.write(`\ncreated ${created}/${plan.length}\n`);
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
