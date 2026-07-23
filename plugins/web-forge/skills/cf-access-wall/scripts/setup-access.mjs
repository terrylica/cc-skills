// setup-access.mjs — idempotent Cloudflare Access provisioning from a declarative spec.
//
// Generalized 2026-07-23 from the curve-dental access-bootstrap run (2nd occurrence after the
// April eonfleet setup → rule of two → canonical). Every step GETs before it POSTs: re-running is
// always safe, and a pre-existing org/idp/app/policy is adopted, never overwritten.
//
//   node setup-access.mjs <spec.json>
//
// The spec (schema: ../schema/access-spec.schema.json) lives in the PROJECT repo — it may carry
// team emails. The scoped API token + minted service-token secrets ride the SCS vault; nothing
// secret is ever printed.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const FORGE = await import(join(homedir(), "eon/cc-skills/plugins/web-forge/lib/browser-forge.mjs"));
const { vaultGet, vaultSet, apiCaller } = FORGE;

const specPath = process.argv[2];
if (!specPath) {
  console.error("usage: node setup-access.mjs <spec.json>   (schema: ../schema/access-spec.schema.json)");
  process.exit(1);
}
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const ACCT = spec.account_id;
const SCOPE = spec.vault_scope;

const token = await vaultGet(SCOPE, "cf.api_token");
const api = apiCaller("https://api.cloudflare.com/client/v4", { Authorization: `Bearer ${token}` });
const fail = (step, r) => {
  throw new Error(`${step} failed: ${JSON.stringify(r.errors ?? r).slice(0, 300)}`);
};

// 1 · Zero Trust org — adopt if present; else create from candidates.
let org = (await api("GET", `/accounts/${ACCT}/access/organizations`)).result;
if (org?.auth_domain) {
  console.log(`✓ org exists: ${org.auth_domain}`);
} else if (spec.org) {
  for (const cand of spec.org.team_domain_candidates) {
    const r = await api("POST", `/accounts/${ACCT}/access/organizations`, {
      name: spec.org.name,
      auth_domain: `${cand}.cloudflareaccess.com`,
    });
    if (r.success) {
      org = r.result;
      break;
    }
    console.log(`  · ${cand} unavailable (${(r.errors ?? []).map((e) => e.message).join("; ").slice(0, 100)})`);
  }
  if (!org?.auth_domain) fail("org create", { errors: [{ message: "all team_domain_candidates taken" }] });
  console.log(`✓ org created: ${org.auth_domain}`);
} else {
  fail("org", { errors: [{ message: "no org on the account and none specified in the spec" }] });
}

// 2 · Identity providers.
{
  const idps = (await api("GET", `/accounts/${ACCT}/access/identity_providers`)).result ?? [];
  const have = (t) => idps.some((p) => p.type === t);
  if (spec.idps?.onetimepin !== false) {
    if (have("onetimepin")) console.log("✓ One-Time PIN idp exists");
    else {
      const r = await api("POST", `/accounts/${ACCT}/access/identity_providers`, {
        name: "Email code",
        type: "onetimepin",
        config: {},
      });
      if (!r.success) fail("onetimepin idp", r);
      console.log("✓ One-Time PIN idp created");
    }
  }
  if (spec.idps?.github) {
    if (have("github")) console.log("✓ GitHub idp exists");
    else {
      const cid = await vaultGet(SCOPE, spec.idps.github.client_id_vault_path);
      const csec = await vaultGet(SCOPE, spec.idps.github.client_secret_vault_path);
      const r = await api("POST", `/accounts/${ACCT}/access/identity_providers`, {
        name: "GitHub",
        type: "github",
        config: { client_id: cid, client_secret: csec },
      });
      if (!r.success) fail("github idp", r);
      console.log("✓ GitHub idp created");
    }
  }
}

// 3 · Service tokens (secret revealed only at creation → straight to the vault).
const tokenIds = {};
for (const st of spec.service_tokens ?? []) {
  const cur = (await api("GET", `/accounts/${ACCT}/access/service_tokens`)).result ?? [];
  const existing = cur.find((t) => t.name === st.name);
  if (existing) {
    tokenIds[st.name] = existing.id;
    console.log(`✓ service token ${st.name} exists`);
    continue;
  }
  const r = await api("POST", `/accounts/${ACCT}/access/service_tokens`, {
    name: st.name,
    duration: st.duration ?? "8760h",
  });
  if (!r.success) fail(`service token ${st.name}`, r);
  tokenIds[st.name] = r.result.id;
  // SCS vault paths are DOT-separated trees (never slashes) — service_token.<name>.client_id.
  await vaultSet(SCOPE, `service_token.${st.name}.client_id`, r.result.client_id);
  await vaultSet(SCOPE, `service_token.${st.name}.client_secret`, r.result.client_secret);
  console.log(`✓ service token ${st.name} created + vaulted`);
}

// 4 · Apps + policies.
for (const app of spec.apps) {
  const cur = (await api("GET", `/accounts/${ACCT}/access/apps`)).result ?? [];
  let a = cur.find((x) => x.domain === app.domain);
  if (a) console.log(`✓ app exists: ${app.name}`);
  else {
    const r = await api("POST", `/accounts/${ACCT}/access/apps`, {
      type: "self_hosted",
      name: app.name,
      domain: app.domain,
      session_duration: app.session_duration ?? "24h",
      app_launcher_visible: false,
      options_preflight_bypass: true, // CORS preflights carry no cookies — never wall them
    });
    if (!r.success) fail(`app ${app.domain}`, r);
    a = r.result;
    console.log(`✓ app created: ${app.name} (session ${app.session_duration ?? "24h"})`);
  }

  const pols = (await api("GET", `/accounts/${ACCT}/access/apps/${a.id}/policies`)).result ?? [];
  const havePol = (n) => pols.some((p) => p.name === n);
  if (!havePol("team-allow")) {
    const r = await api("POST", `/accounts/${ACCT}/access/apps/${a.id}/policies`, {
      name: "team-allow",
      decision: "allow",
      include: app.allow_emails.map((e) => ({ email: { email: e } })),
    });
    if (!r.success) fail(`policy team-allow ${app.domain}`, r);
    console.log(`  ✓ team-allow (${app.allow_emails.length} emails)`);
  } else console.log("  ✓ team-allow exists");

  for (const stName of app.service_token_names ?? []) {
    const polName = `service-auth-${stName}`;
    if (havePol(polName)) {
      console.log(`  ✓ ${polName} exists`);
      continue;
    }
    if (!tokenIds[stName]) fail(polName, { errors: [{ message: `service token ${stName} not in spec.service_tokens` }] });
    const r = await api("POST", `/accounts/${ACCT}/access/apps/${a.id}/policies`, {
      name: polName,
      decision: "non_identity",
      include: [{ service_token: { token_id: tokenIds[stName] } }],
    });
    if (!r.success) fail(`policy ${polName} ${app.domain}`, r);
    console.log(`  ✓ ${polName}`);
  }
}

console.log(`\nDONE. Login page: https://${org.auth_domain}`);
console.log("Verify enforcement now: curl -sw '%{http_code}' the protected hosts — expect 302 to the login page.");
