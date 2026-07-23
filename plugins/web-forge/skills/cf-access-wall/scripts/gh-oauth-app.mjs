// gh-oauth-app.mjs — forge a GitHub OAuth App (no creation API exists) with identity preflight.
//
// Generalized 2026-07-23 from the curve-dental Access run. The preflight is the lesson: an OAuth
// app was created under the WRONG GitHub account mid-forge (the human had switched logins) — now
// the signed-in login is asserted against --expect-account BEFORE anything is created.
//
//   node gh-oauth-app.mjs --name <app> --callback <url> --expect-account <login> \
//        --vault-scope <scope> [--homepage <url>] [--site <profile-site>]
//
// Secrets: client_secret → vault <scope>/github_oauth.client_secret via stdin sink (never printed,
// never screenshotted — the reveal is DOM-extracted). client_id is public and logged.
import { homedir } from "node:os";
import { join } from "node:path";

const FORGE = await import(join(homedir(), "eon/cc-skills/plugins/web-forge/lib/browser-forge.mjs"));
const { launchChrome, connect, assertIdentity, shot, purgeShots, sleep, vaultSet } = FORGE;

const arg = (n) => {
  const i = process.argv.indexOf(`--${n}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
};
const NAME = arg("name");
const CALLBACK = arg("callback");
const EXPECT = arg("expect-account");
const SCOPE = arg("vault-scope");
const HOMEPAGE = arg("homepage") ?? CALLBACK;
const SITE = arg("site") ?? "github";
if (!NAME || !CALLBACK || !EXPECT || !SCOPE) {
  console.error("usage: gh-oauth-app.mjs --name <app> --callback <url> --expect-account <login> --vault-scope <scope> [--homepage <url>] [--site <s>]");
  process.exit(1);
}

await launchChrome(SITE, "https://github.com/settings/developers");
const { browser, ctx } = await connect(SITE);
try {
  const page = ctx.pages().find((p) => p.url().includes("github.com")) ?? (await ctx.newPage());
  await page.goto("https://github.com/settings/developers", { waitUntil: "domcontentloaded" });
  await sleep(1500);
  if (page.url().includes("/login")) throw new Error(`GitHub session expired — sign in (as ${EXPECT}) in the automation Chrome, then re-run`);

  // Identity preflight — BEFORE creating anything account-owned.
  const login = (await page.content()).match(/<meta name="user-login" content="([^"]+)"/)?.[1] ?? null;
  assertIdentity(login, EXPECT, `OAuth app ${NAME}`);
  console.log(`✓ identity preflight: signed in as ${login}`);

  const existing = page.getByRole("link", { name: NAME });
  if ((await existing.count()) > 0) {
    console.log(`app ${NAME} already exists — opening it`);
    await existing.first().click();
    await sleep(1500);
  } else {
    await page.goto("https://github.com/settings/applications/new", { waitUntil: "domcontentloaded" });
    await sleep(1200);
    await page.locator('input[name="oauth_application[name]"]').fill(NAME);
    await page.locator('input[name="oauth_application[url]"]').fill(HOMEPAGE);
    await page.locator('input[name="oauth_application[callback_url]"]').fill(CALLBACK);
    await shot(page, "oauth-form-filled");
    await page.getByRole("button", { name: /register application/i }).click();
    await sleep(2000);
  }

  // Precise, version-aware Client ID formats (2026-07: Ov23li… current, Iv1.… GitHub-App-era, 20-hex legacy).
  const clientId = (await page.locator("body").innerText()).match(/Client ID\s*\n?\s*(Ov23li[A-Za-z0-9]+|Iv1\.[a-f0-9]+|\b[a-f0-9]{20}\b)/)?.[1];
  if (!clientId) throw new Error("could not read Client ID — check /tmp/web-forge shots");

  // Secret generation may hit sudo mode; a fresh login usually has a grace window. If the sudo
  // wall appears, the supervising human clears it (passkey/2FA) and we keep polling.
  await page.getByRole("button", { name: /generate a new client secret/i }).click();
  await sleep(2500);
  if (/sudo|confirm/i.test(page.url())) {
    console.log("⚠ GitHub sudo wall — clear it in the Chrome window (passkey/2FA); waiting up to 5min…");
    for (let i = 0; i < 100 && /sudo|confirm/i.test(page.url()); i++) await sleep(3000);
    await page.getByRole("button", { name: /generate a new client secret/i }).click().catch(() => {});
    await sleep(2500);
  }
  // DOM-extract ONLY — never screenshot a reveal page (secrets must not enter agent context).
  const secret = await page.evaluate(() => document.body.innerText.match(/\b([a-f0-9]{40})\b/)?.[1] ?? null);
  if (!secret) throw new Error("could not extract the client secret — sudo not cleared, or GitHub changed the reveal format (update the Vendor Quirks log)");

  await vaultSet(SCOPE, "github_oauth.client_id", clientId);
  await vaultSet(SCOPE, "github_oauth.client_secret", secret);
  console.log(`✓ OAuth app ${NAME} ready under ${login} (client_id ${clientId}); secret vaulted to ${SCOPE} github_oauth.client_secret`);
  console.log("  (Chrome stays running for the next supervised step — teardown(site) when the whole run is done)");
} finally {
  purgeShots();
  await browser.close().catch(() => {});
}
