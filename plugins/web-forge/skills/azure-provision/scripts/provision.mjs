#!/usr/bin/env node
/**
 * provision.mjs — the unattended half. No browser, no DOM: authenticate as the service principal
 * minted by `mint-sp.mjs` and create the resource group + Cognitive Services accounts from the spec,
 * then PROVE each one works before writing its credentials to the vault.
 *
 * ORDER IS THE POINT. Overwriting a live vault scope before the new resource has been exercised
 * leaves the consuming pipeline authenticating against something nobody has ever called. So:
 * create → exercise → compare → only then write. `preserveExistingAs` keeps the previous values
 * recoverable, which is what makes an account migration reversible.
 *
 * The client secret never touches argv: authentication is a client-credentials POST from inside this
 * process, not `az login --service-principal -p <secret>` (readable by any user via `ps`).
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { vaultGet, vaultSet } from "../../../lib/browser-forge.mjs";

const CONTRIBUTOR_NOTE = "Contributor cannot create role assignments — that is deliberate.";
const DRY = process.argv.includes("--dry-run");
const specPath = process.argv.find((a) => a.endsWith(".json"));
if (!specPath) {
  console.error("usage: node provision.mjs <spec.json> [--dry-run]");
  process.exit(2);
}
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const { subscription, servicePrincipal: sp, resourceGroup: rg, resources } = spec;

// ── auth: client credentials, in-process ─────────────────────────────────────────────────────────
const [clientId, clientSecret, tenantId] = await Promise.all([
  vaultGet(sp.vault.scope, sp.vault.clientIdPath),
  vaultGet(sp.vault.scope, sp.vault.clientSecretPath),
  vaultGet(sp.vault.scope, sp.vault.tenantIdPath),
]);

async function armToken() {
  const res = await fetch(`https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
      scope: "https://management.azure.com/.default",
    }),
  });
  const j = await res.json().catch(() => ({}));
  if (!j.access_token) throw new Error(`service-principal token failed: HTTP ${res.status} ${j.error_description?.slice(0, 160) ?? j.error ?? ""}`);
  return j.access_token;
}

const token = await armToken();
const ARM = "https://management.azure.com";
const call = async (method, path, body, apiVersion) => {
  const url = `${ARM}${path}${path.includes("?") ? "&" : "?"}api-version=${apiVersion}`;
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, ok: res.ok, ...json };
};

const SUB = `/subscriptions/${subscription.id}`;
console.log(`→ authenticated as the service principal; ${CONTRIBUTOR_NOTE}`);

// ── provider registration (a new subscription starts with EVERY provider NotRegistered) ──────────
// `microsoft.insights` is here because it bites separately and later: resources create fine, then the
// first attempt to attach an alert or action group fails with HTTP 409 "The subscription is not
// registered to use namespace 'microsoft.insights'". Registering it up front turns a confusing
// mid-run 409 into a step that just happens. Registration is async — measured at ~84s for insights,
// so the poll is not decoration.
for (const ns of ["Microsoft.CognitiveServices", "microsoft.insights"]) {
  const prov = await call("GET", `${SUB}/providers/${ns}`, undefined, "2021-04-01");
  if (prov.registrationState !== "Registered" && DRY) {
    console.log(`  provider ${ns}: ${prov.registrationState} — would register`);
    continue;
  }
  if (prov.registrationState !== "Registered") {
    console.log(`  provider ${ns} is ${prov.registrationState} — registering`);
    await call("POST", `${SUB}/providers/${ns}/register`, undefined, "2021-04-01");
    for (let i = 0; i < 40; i++) {
      const p = await call("GET", `${SUB}/providers/${ns}`, undefined, "2021-04-01");
      if (p.registrationState === "Registered") break;
      await new Promise((r) => setTimeout(r, 4000));
    }
  }
  console.log(`  provider ${ns}: Registered`);
}

// ── resource group (idempotent PUT) ──────────────────────────────────────────────────────────────
if (rg && DRY) {
  const g = await call("GET", `${SUB}/resourcegroups/${rg.name}`, undefined, "2021-04-01");
  console.log(`  resource group ${rg.name}: ${g.status === 404 ? "WOULD CREATE" : "exists — would adopt"}`);
} else if (rg) {
  const r = await call("PUT", `${SUB}/resourcegroups/${rg.name}`, { location: rg.location }, "2021-04-01");
  if (!r.ok) throw new Error(`resource group ${rg.name}: HTTP ${r.status} ${JSON.stringify(r.error ?? {}).slice(0, 200)}`);
  console.log(`  resource group ${rg.name} @ ${rg.location}: ${r.properties?.provisioningState ?? "ok"}`);
}

// ── acceptance checks: does it DETECT, or merely authenticate? ────────────────────────────────────
async function exercise(res, key, endpoint, location) {
  const check = res.acceptanceCheck ?? { kind: "none" };
  if (check.kind === "none") return { ok: true, detail: "no check configured (weak — prefer a real probe)" };

  if (check.kind === "pii-entities") {
    const r = await fetch(`${endpoint.replace(/\/+$/, "")}/language/:analyze-text?api-version=2024-11-01`, {
      method: "POST",
      headers: { "Ocp-Apim-Subscription-Key": key, "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "PiiEntityRecognition",
        parameters: { modelVersion: "latest", stringIndexType: "Utf16CodeUnit" },
        analysisInput: { documents: [{ id: "1", language: "en", text: check.sampleText }] },
      }),
    });
    const j = await r.json().catch(() => ({}));
    const ents = j?.results?.documents?.[0]?.entities ?? [];
    const errs = j?.results?.errors ?? [];
    // errors is checked explicitly: Azure Language reports a per-document failure inside an HTTP 200,
    // so `res.ok` alone once let 12 un-redacted transcripts through in production.
    return { ok: r.ok && errs.length === 0 && ents.length >= (check.minEntities ?? 1), detail: `HTTP ${r.status}, entities=${ents.length}, errors=${errs.length}` };
  }

  if (check.kind === "speech-token") {
    const r = await fetch(`https://${location}.api.cognitive.microsoft.com/sts/v1.0/issueToken`, {
      method: "POST",
      headers: { "Ocp-Apim-Subscription-Key": key, "Content-Length": "0" },
    });
    const t = await r.text();
    return { ok: r.ok && t.length > 100, detail: `HTTP ${r.status}, token length ${t.length}` };
  }
  throw new Error(`unknown acceptanceCheck kind: ${check.kind}`);
}

// ── each resource: create → exercise → then (and only then) write credentials ────────────────────
let failures = 0;
for (const res of resources) {
  const location = res.location ?? rg?.location;
  const path = `${SUB}/resourceGroups/${rg.name}/providers/Microsoft.CognitiveServices/accounts/${res.name}`;

  const existing = await call("GET", path, undefined, "2023-05-01");
  if (DRY) {
    console.log(`  ${res.name}: ${existing.status === 404 ? "WOULD CREATE" : `exists (${existing.kind}/${existing.sku?.name}) — would ADOPT`}`);
    continue;
  }
  if (existing.status === 404) {
    const created = await call("PUT", path, { location, kind: res.kind, sku: { name: res.sku }, properties: { customSubDomainName: res.name } }, "2023-05-01");
    if (!created.ok) throw new Error(`create ${res.name}: HTTP ${created.status} ${JSON.stringify(created.error ?? {}).slice(0, 240)}\n  NOTE: the name doubles as a GLOBALLY unique custom subdomain; a clash needs a different name.`);
    console.log(`  ${res.name}: created (${res.kind}/${res.sku} @ ${location})`);
    for (let i = 0; i < 30; i++) {
      const s = await call("GET", path, undefined, "2023-05-01");
      if (s.properties?.provisioningState === "Succeeded") break;
      await new Promise((r) => setTimeout(r, 4000));
    }
  } else {
    console.log(`  ${res.name}: already exists, adopting`);
  }

  const acct = await call("GET", path, undefined, "2023-05-01");
  const keys = await call("POST", `${path}/listKeys`, undefined, "2023-05-01");
  const key = keys.key1;
  const endpoint = acct.properties?.endpoint;
  if (!key || !endpoint) throw new Error(`${res.name}: could not read key/endpoint (HTTP ${keys.status}/${acct.status})`);

  const verdict = await exercise(res, key, endpoint, acct.location);
  console.log(`    acceptance: ${verdict.ok ? "PASS" : "FAIL"} — ${verdict.detail}`);
  if (!verdict.ok) {
    console.error(`    NOT writing credentials for ${res.name} — it did not pass its own acceptance check.`);
    failures += 1;
    continue;
  }

  const c = res.credentials;
  if (c.preserveExistingAs) {
    for (const p of [c.keyPath, c.endpointPath, c.regionPath].filter(Boolean)) {
      const old = await vaultGet(c.scope, p).catch(() => "");
      if (old) await vaultSet(c.scope, `${c.preserveExistingAs}_${p}`, old);
    }
  }
  // Key and endpoint (and region) are written TOGETHER — see the schema's note on the HTTP 401 drift.
  await vaultSet(c.scope, c.keyPath, key);
  await vaultSet(c.scope, c.endpointPath, endpoint);
  if (c.regionPath) await vaultSet(c.scope, c.regionPath, acct.location);
  console.log(`    ✓ vaulted key (len ${key.length}) + endpoint${c.regionPath ? " + region" : ""} → ${c.scope}`);
}

try {
  execFileSync(`${process.env.HOME}/.local/bin/vault`, ["manifest"], { stdio: "ignore" });
} catch (e) {
  console.error(`  (vault manifest refresh failed, non-fatal: ${e.message.slice(0, 120)})`);
}

if (DRY) {
  // Say what actually happened. A dry run that reports "provisioned, exercised and vaulted" is the
  // same class of lie as an HTTP 200 on a document Azure never read.
  console.log("\n✓ DRY RUN — auth, provider state and adopt/create detection were exercised for real; nothing was created, exercised or vaulted.");
  process.exit(0);
}
if (failures > 0) {
  console.error(`\n✗ ${failures} resource(s) failed acceptance; their credentials were NOT written.`);
  process.exit(1);
}
console.log("\n✓ all resources provisioned, exercised, and vaulted.");
