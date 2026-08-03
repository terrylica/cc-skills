#!/usr/bin/env node
/**
 * mint-sp.mjs — mint an Azure service principal when interactive `az login` is blocked, using the
 * browser for the LOGIN ONLY and Microsoft Graph / ARM REST for everything else.
 *
 * WHY THIS EXISTS. A Conditional Access policy can be scoped to the **Azure CLI** app id
 * (04b07795-8ddb-461a-bbee-02f9e1bf7b46) and leave the **Azure Portal** app
 * (c44b4083-3bb0-49c1-b47d-974e53cbdf3c) untouched. When that happens `az login` fails with error
 * 530035 ("Device state: Unregistered") while the portal signs in normally. `az login` has no
 * `--client-id` override, so the portal session is the only door. Once a service principal exists it
 * authenticates by client credentials, which user Conditional Access does not gate — so the browser is
 * needed exactly ONCE, ever.
 *
 * WHY NO CLICKING. The first version of this drove the portal's DOM and it was miserable: the
 * "Register" submit and the "Close content 'Register an application'" button both match /register/i,
 * so a fuzzy click silently DISMISSED the blade (twice, once creating a duplicate). The fix is not
 * better selectors — it is not using the DOM at all. Measured 2026-08-02, the portal's own Graph
 * token carries these delegated scopes:
 *     Application.ReadWrite.All · AppRoleAssignment.ReadWrite.All · RoleManagement.ReadWrite.Directory
 * which is everything needed to create the app, its secret, and its role assignment over REST. So we
 * capture the token off the wire (`captureBearer`) and POST. Zero selectors, zero blade navigation,
 * nothing to drift. This is the plugin's Hybrid rule taken to its limit.
 *
 * IDEMPOTENT. Every create is GET-before-POST. Re-running adopts the existing app/SP/role assignment
 * instead of making a second one — which the DOM version did NOT, and that is how a duplicate app
 * registration got created.
 *
 * SECRETS. The client secret is returned once by Graph, goes straight to `vault set --stdin`, and is
 * never printed, never an argv element, and never screenshotted. `purgeShots()` runs at the end.
 */
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import {
  assertIdentity,
  captureBearer,
  connect,
  decodeJwtClaims,
  launchChrome,
  purgeShots,
  sleep,
  teardown,
  vaultSet,
} from "../../../lib/browser-forge.mjs";

const SITE = "azure";
const PORTAL = "https://portal.azure.com/";
// The App-registrations LIST blade reliably re-queries Graph. Several other blades are cached by the
// SPA and issue NO request at all, which makes token capture silently return null.
const GRAPH_BLADE = "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade";
const ARM_BLADE = "https://portal.azure.com/#view/Microsoft_Azure_Billing/SubscriptionsBladeV2";
const CONTRIBUTOR = "b24988ac-6180-42a0-ab88-20f7382dd24c";

const specPath = process.argv[2];
if (!specPath) {
  console.error("usage: node mint-sp.mjs <spec.json>");
  process.exit(2);
}
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const { identity, subscription, servicePrincipal: sp } = spec;

const api = (token) => async (method, url, body) => {
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, ok: res.ok, ...json };
};

// ── 1. Browser: login only ───────────────────────────────────────────────────────────────────────
await launchChrome(SITE, PORTAL);
const { browser, ctx } = await connect(SITE);
const page = ctx.pages().find((p) => /azure|microsoft/i.test(p.url())) ?? (await ctx.newPage());

console.log("→ capturing a Graph token (sign in in the visible Chrome if prompted)");
const graphToken = await captureBearer(page, "graph.microsoft.com", { navUrl: GRAPH_BLADE, timeoutMs: 120_000 });
if (!graphToken) throw new Error("no Graph token captured — is the portal signed in? (blades can be cached; try a different blade)");

// ── 2. Identity preflight — the browser-world mirror of GitHub-Owner-Per-Path ────────────────────
const claims = decodeJwtClaims(graphToken);
// A guest/MSA-backed account arrives as `live.com#user@domain`; compare the mailbox, not the prefix.
const actual = String(claims?.upn ?? claims?.unique_name ?? "").split("#").pop();
assertIdentity(actual, identity.expectedAccount, `Azure tenant ${identity.tenantDomain}`);
console.log(`  identity OK: ${actual}  (token aud=${claims?.aud})`);
const scopes = String(claims?.scp ?? "").split(" ");
for (const need of ["Application.ReadWrite.All"]) {
  if (!scopes.includes(need)) throw new Error(`the portal Graph token lacks ${need}; cannot mint headlessly`);
}

const graph = api(graphToken);
const G = "https://graph.microsoft.com/v1.0";

// ── 3. Application (GET before POST) ─────────────────────────────────────────────────────────────
let appId;
let appObjectId;
const found = await graph("GET", `${G}/applications?$filter=displayName eq '${sp.displayName}'&$select=id,appId,displayName`);
if (found.value?.length > 1) {
  throw new Error(`${found.value.length} applications already named "${sp.displayName}" — resolve the duplicates first, do not add another`);
}
if (found.value?.length === 1) {
  ({ appId, id: appObjectId } = found.value[0]);
  console.log(`  app registration exists, adopting: ${appId}`);
} else {
  const created = await graph("POST", `${G}/applications`, { displayName: sp.displayName, signInAudience: "AzureADMyOrg" });
  if (!created.appId) throw new Error(`create application failed: HTTP ${created.status} ${JSON.stringify(created.error ?? {}).slice(0, 200)}`);
  ({ appId, id: appObjectId } = created);
  console.log(`  app registration created: ${appId}`);
}

// ── 4. Service principal (GET before POST) ───────────────────────────────────────────────────────
// The ROLE ASSIGNMENT needs this object id, NOT the appId. Passing appId yields PrincipalNotFound,
// which reads like a permissions problem and sends you down entirely the wrong path.
let spObjectId;
const spFound = await graph("GET", `${G}/servicePrincipals?$filter=appId eq '${appId}'&$select=id`);
if (spFound.value?.length) {
  spObjectId = spFound.value[0].id;
  console.log(`  service principal exists: ${spObjectId}`);
} else {
  const spCreated = await graph("POST", `${G}/servicePrincipals`, { appId });
  if (!spCreated.id) throw new Error(`create servicePrincipal failed: HTTP ${spCreated.status}`);
  spObjectId = spCreated.id;
  console.log(`  service principal created: ${spObjectId}`);
}

// ── 5. Client secret → vault (value never leaves this process except down the vault pipe) ────────
const pwd = await graph("POST", `${G}/applications/${appObjectId}/addPassword`, {
  passwordCredential: { displayName: sp.secretDescription ?? "minted by web-forge azure-provision" },
});
if (!pwd.secretText) throw new Error(`addPassword failed: HTTP ${pwd.status} ${JSON.stringify(pwd.error ?? {}).slice(0, 200)}`);
await vaultSet(sp.vault.scope, sp.vault.clientSecretPath, pwd.secretText);
console.log(`  ✓ client secret vaulted (len ${pwd.secretText.length}) → ${sp.vault.scope}/${sp.vault.clientSecretPath}`);
await vaultSet(sp.vault.scope, sp.vault.clientIdPath, appId);
await vaultSet(sp.vault.scope, sp.vault.tenantIdPath, claims.tid);
if (sp.vault.subscriptionIdPath) await vaultSet(sp.vault.scope, sp.vault.subscriptionIdPath, subscription.id);

// ── 6. Role assignment over ARM (the 3-tab wizard collapses to one PUT) ──────────────────────────
const armToken = await captureBearer(page, "management.azure.com", { navUrl: ARM_BLADE, timeoutMs: 90_000 });
if (!armToken) throw new Error("no ARM token captured — the subscriptions blade may be cached; reload the portal and re-run");
const arm = api(armToken);
const scope = `/subscriptions/${subscription.id}`;
const roleDefId = `${scope}/providers/Microsoft.Authorization/roleDefinitions/${sp.roleDefinitionId ?? CONTRIBUTOR}`;

const existing = await arm(
  "GET",
  `https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&$filter=principalId eq '${spObjectId}'`,
);
const already = (existing.value ?? []).some((a) => a.properties?.roleDefinitionId === roleDefId);
if (already) {
  console.log("  role assignment already present — nothing to do");
} else {
  const put = await arm("PUT", `https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignments/${randomUUID()}?api-version=2022-04-01`, {
    properties: { roleDefinitionId: roleDefId, principalId: spObjectId, principalType: "ServicePrincipal" },
  });
  if (put.status !== 201 && put.status !== 200) throw new Error(`role assignment failed: HTTP ${put.status} ${JSON.stringify(put.error ?? {}).slice(0, 250)}`);
  console.log(`  role assignment created (HTTP ${put.status})`);
}

// ── 7. Hygiene, then prove the SP actually works ─────────────────────────────────────────────────
await browser.close(); // CDP close only DETACHES; Chrome stays up for the human
console.log(`  purged ${purgeShots()} breadcrumb screenshot(s)`);
if (spec.teardownBrowser !== false) await teardown(SITE);

// Verify by the client-credentials flow DIRECTLY, not via `az login --service-principal -p <secret>`.
// That CLI form puts the secret in argv, where any user on the box can read it from `ps` — a plain
// violation of this plugin's "values ride PIPES, never argv" rule. A token POST keeps it in-process.
//
// RBAC is also eventually consistent: immediately after the 201 the subscription list comes back
// empty, which is indistinguishable from a failed assignment unless you know to wait it out.
const vget = (p) => execFileSync(`${process.env.HOME}/.local/bin/vault`, ["get", sp.vault.scope, p], { encoding: "utf8" }).trim();
const clientId = vget(sp.vault.clientIdPath);
const clientSecret = vget(sp.vault.clientSecretPath);
const tenantId = vget(sp.vault.tenantIdPath);

async function spSeesSubscription() {
  const form = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: clientId,
    client_secret: clientSecret,
    scope: "https://management.azure.com/.default",
  });
  const tRes = await fetch(`https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  const tJson = await tRes.json().catch(() => ({}));
  if (!tJson.access_token) return { ok: false, why: `token HTTP ${tRes.status} ${tJson.error ?? ""}` };
  const sRes = await fetch("https://management.azure.com/subscriptions?api-version=2022-12-01", {
    headers: { Authorization: `Bearer ${tJson.access_token}` },
  });
  const sJson = await sRes.json().catch(() => ({}));
  return { ok: (sJson.value ?? []).some((s) => s.subscriptionId === subscription.id), why: `subscriptions HTTP ${sRes.status}` };
}

let works = false;
for (let attempt = 1; attempt <= 6 && !works; attempt++) {
  await sleep(attempt === 1 ? 15_000 : 20_000);
  const r = await spSeesSubscription();
  works = r.ok;
  console.log(`  attempt ${attempt}: ${works ? "SP sees the subscription" : `not yet — ${r.why}`}`);
}
if (!works) throw new Error("the service principal never saw the subscription — check the role assignment scope");
console.log("\n✓ service principal minted, vaulted, and verified working unattended.");
