#!/usr/bin/env node
// campaign.mjs — empirical proof harness for the fine-grained PAT engine.
//
// In ONE CDP session (efficiency) it runs every spec through
// create → inspect/verify → delete, plus a forced-failure case, then sweeps to
// assert no test tokens leak and the real `cc-skills-release` is untouched.
//
// All test tokens are namespaced `zz-pat-selftest-*` and auto-deleted. Token
// VALUES are never printed (the harness only checks creation/metadata).
//
//   node test/campaign.mjs            # full batch
//   node test/campaign.mjs release-bot ci-status-reporter   # subset by spec basename

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { launchChrome, connect, gotoSettings, isAuthedViaRequest, DEBUG_DIR } from "../scripts/browser.mjs";
import { createToken, listTokens, inspectToken, deleteToken } from "../scripts/form.mjs";
import { shot } from "../scripts/selectors.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SPECS_DIR = join(HERE, "..", "specs");
const PREFIX = "zz-pat-selftest-";
const REAL_TOKEN = "cc-skills-release"; // must survive the campaign
const ms = () => Date.now();

// The token DETAIL page renders permissions as prose grouped by access level
// ("Read and Write access to code, issues, and pull requests") using friendly
// nouns, NOT the UI labels. Map UI label -> detail-page noun for verification.
const NOUN = {
  Contents: "code",
  Issues: "issues",
  "Pull requests": "pull requests",
  "Commit statuses": "commit statuses",
  Actions: "actions",
  Deployments: "deployments",
  Environments: "environments",
  Webhooks: "repository hooks",
  Metadata: "metadata",
  Gists: "gists",
};

/** Parse "(Read and Write|Read|No) access to <clause>" prose into noun -> level. */
function parseGrants(text) {
  const lower = ` ${text.toLowerCase().replace(/\s+/g, " ")} `;
  const hits = [...lower.matchAll(/(read and write|read|no) access to /g)];
  const grants = {};
  for (let i = 0; i < hits.length; i++) {
    const kind = hits[i][1];
    const level = kind.includes("write") ? "write" : kind === "no" ? "none" : "read";
    const start = hits[i].index + hits[i][0].length;
    const end = i + 1 < hits.length ? hits[i + 1].index : lower.length;
    const clause = lower
      .slice(start, end)
      .split(/\b(footer|repository permissions|user permissions|account permissions|terms|privacy|status|community)\b/)[0];
    for (const part of clause.split(/,| and /).map((s) => s.trim()).filter(Boolean)) {
      if (part.length < 50) grants[part] = level;
    }
  }
  return grants;
}

function verifyPerms(grants, spec) {
  const problems = [];
  for (const grp of ["repository", "account"]) {
    for (const [label, level] of Object.entries(spec.permissions?.[grp] ?? {})) {
      const noun = NOUN[label]?.toLowerCase();
      if (!noun) continue; // unknown label -> skip strict check
      const key = Object.keys(grants).find((k) => k === noun || k.includes(noun));
      if (!key) problems.push(`perm missing: ${label}`);
      else if (grants[key] !== level) problems.push(`${label}=${grants[key]} (want ${level})`);
    }
  }
  return problems;
}

function loadSpecs(filter) {
  return readdirSync(SPECS_DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => ({ base: f.replace(/\.json$/, ""), spec: JSON.parse(readFileSync(join(SPECS_DIR, f), "utf8")) }))
    .filter(({ base }) => filter.length === 0 || filter.includes(base))
    .map(({ base, spec }) => ({ base, spec: { ...spec, name: PREFIX + spec.name } }));
}

/** Verify a freshly created token against its spec by scraping the detail page. */
async function verify(page, spec) {
  const info = await inspectToken(page, spec.name);
  if (!info.found) return { ok: false, why: "not found in list after create" };
  const text = info.text;
  const problems = [];

  // expiration
  const exp = spec.expiration ?? 30;
  if (exp === "none" && !/no expiration|never expire/i.test(text)) problems.push("expiration≠none");
  if (typeof exp === "number" && !/expires on/i.test(text)) problems.push("expected an expiry date");

  // repos (only for selected mode)
  if (spec.repositoryAccess?.mode === "selected") {
    for (const r of spec.repositoryAccess.repos) {
      if (!info.repos.includes(r) && !text.includes(r)) problems.push(`repo missing: ${r}`);
    }
  }

  // permissions: parse the level-grouped prose and compare
  problems.push(...verifyPerms(parseGrants(text), spec));
  return { ok: problems.length === 0, why: problems.join("; ") };
}

async function runSpec(page, base, spec) {
  const row = { base, name: spec.name, created: "—", verified: "—", deleted: "—", ms: 0, note: "" };
  const t0 = ms();
  try {
    // idempotency: clear any leftover from a previous aborted run
    if ((await listTokens(page)).some((t) => t.name === spec.name)) await deleteToken(page, spec.name);
    await createToken(page, spec);
    row.created = "✓";
    const v = await verify(page, spec);
    row.verified = v.ok ? "✓" : "✗";
    if (!v.ok) row.note = v.why;
  } catch (e) {
    row.created = row.created === "✓" ? "✓" : "✗";
    row.note = e.message;
    await shot(page, DEBUG_DIR, `campaign-${base}-fail`);
  } finally {
    // always attempt teardown of the test token
    try {
      row.deleted = (await deleteToken(page, spec.name)) ? "✓" : "—";
    } catch {
      row.deleted = "✗";
    }
    row.ms = ms() - t0;
  }
  return row;
}

/** A spec pointed at a non-existent repo must FAIL gracefully and leave nothing. */
async function runForcedFailure(page) {
  const spec = {
    name: `${PREFIX}badrepo`,
    expiration: 30,
    repositoryAccess: { mode: "selected", repos: ["terrylica/__nonexistent-zzz-987654"] },
    permissions: { repository: { Contents: "read" } },
  };
  const t0 = ms();
  let threw = false;
  try {
    await createToken(page, spec);
  } catch {
    threw = true;
  }
  const leaked = (await listTokens(page)).some((t) => t.name === spec.name);
  if (leaked) await deleteToken(page, spec.name);
  return {
    base: "forced-failure",
    name: spec.name,
    created: threw ? "✗(expected)" : "✓(!)",
    verified: threw && !leaked ? "graceful✓" : "leak✗",
    deleted: leaked ? "cleaned" : "—",
    ms: ms() - t0,
    note: threw ? "errored as expected, no leak" : "DID NOT FAIL — investigate",
  };
}

function printTable(rows) {
  const head = ["spec", "name", "created", "verified", "deleted", "ms", "note"];
  console.log("\n" + head.map((h, i) => h.padEnd([16, 26, 12, 12, 9, 7, 0][i])).join(""));
  console.log("-".repeat(96));
  for (const r of rows) {
    console.log(
      [r.base, r.name, r.created, r.verified, r.deleted, String(r.ms)]
        .map((c, i) => String(c).padEnd([16, 26, 12, 12, 9, 7][i]))
        .join("") + (r.note ? `  ${r.note}` : ""),
    );
  }
}

async function main() {
  if (!existsSync(SPECS_DIR)) throw new Error(`specs dir missing: ${SPECS_DIR}`);
  const filter = process.argv.slice(2);
  const specs = loadSpecs(filter);
  if (!specs.length) throw new Error("no specs matched");

  await launchChrome();
  const { browser, ctx } = await connect();
  if (!(await isAuthedViaRequest(ctx))) {
    await browser.close();
    throw new Error("not logged in — run `node scripts/pat.mjs login` first");
  }
  const page = await gotoSettings(ctx);

  const rows = [];
  try {
    for (const { base, spec } of specs) rows.push(await runSpec(page, base, spec));
    rows.push(await runForcedFailure(page));

    // final sweep
    const remaining = (await listTokens(page)).map((t) => t.name);
    const leaks = remaining.filter((n) => n.startsWith(PREFIX));
    const realOk = remaining.includes(REAL_TOKEN);

    printTable(rows);
    console.log("\nSWEEP");
    console.log(`  leftover ${PREFIX}* : ${leaks.length ? leaks.join(", ") : "none ✓"}`);
    console.log(`  ${REAL_TOKEN} intact : ${realOk ? "yes ✓" : "MISSING ✗"}`);

    const created = rows.filter((r) => r.base !== "forced-failure");
    const allPass =
      created.every((r) => r.created === "✓" && r.verified === "✓" && r.deleted === "✓") &&
      rows.at(-1).verified === "graceful✓" &&
      leaks.length === 0 &&
      realOk;
    console.log(`\nRESULT: ${allPass ? "PASS ✓ — engine is correct, efficient, anti-fragile" : "FAIL ✗ — see notes above"}`);
    process.exitCode = allPass ? 0 : 1;
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  console.error(`campaign: ${e.message}`);
  process.exit(1);
});
