// autosudo.mjs — satisfy GitHub's sudo/login challenge autonomously.
//
// One Touch-ID tap per session: the gated github-web-<account> blob is unlocked
// once (foreground `vault get --gated`, correct GUI context) and cached in the
// memory-only webauth-agent; later commands reuse it with zero prompts. The
// blob holds { passkey, password, totpSeed }. Primary path = virtual-authenticator
// passkey; fallback = password + TOTP. Token/secret values never reach chat.

import { execFileSync } from "node:child_process";
import { SEL, sleep, clickExact, evalClick, shot } from "./selectors.mjs";
import { DEBUG_DIR } from "./browser.mjs";
import { vaultItemName } from "./identity.mjs";
import { agentGet, agentPut, agentRunning } from "./webauth-agent.mjs";
import { armStoredPasskey, removeAuthenticator } from "./webauthn.mjs";

const hasForm = async (page) => (await page.locator(SEL.nameInput).count()) > 0;

/** Unlock the account's gated blob — one Touch ID, reused via the session agent. */
export async function getUnlockedBlob(account) {
  const cached = await agentGet(account);
  if (cached.ok) return cached.blob;
  // Foreground Touch-ID unlock (vault get --gated triggers the biometric prompt).
  let raw;
  try {
    raw = execFileSync("vault", ["get", "--gated", vaultItemName(account)], { encoding: "utf8" });
  } catch (e) {
    throw new Error(`could not unlock github-web-${account} (Touch ID denied or not provisioned)`, { cause: e });
  }
  const blob = JSON.parse(raw);
  if (agentRunning()) await agentPut(account, blob);
  return blob;
}

function totpCode(seed) {
  return execFileSync("oathtool", ["--totp", "-b", seed], { encoding: "utf8" }).trim();
}

async function tryPasskey(page, passkey) {
  if (!passkey?.credentialId) return false;
  const { client, authenticatorId } = await armStoredPasskey(page, passkey);
  try {
    // Trigger the passkey assertion — the virtual authenticator auto-satisfies it.
    if (!(await clickByText(page, /use passkey|sign in with a passkey|passkey/i))) {
      // some flows assert automatically on load
    }
    for (let i = 0; i < 12; i++) {
      await sleep(1000);
      if (await hasForm(page)) return true;
    }
    return await hasForm(page);
  } finally {
    await removeAuthenticator(client, authenticatorId);
  }
}

async function tryPasswordTotp(page, blob) {
  if (!blob.password) return false;
  await clickByText(page, /use your password|use password/i);
  await sleep(800);
  const pw = page.locator('input[type="password"]:visible').first();
  if (!(await pw.count())) return false;
  await pw.fill(blob.password);
  await page.keyboard.press("Enter");
  await sleep(1500);
  if (await hasForm(page)) return true;

  // Second factor — authenticator app TOTP.
  if (blob.totpSeed) {
    await clickByText(page, /authenticator app|use your authenticator|two-factor/i);
    await sleep(800);
    const otp = page.locator('input[autocomplete="one-time-code"]:visible, input[name*="otp" i]:visible, input[inputmode="numeric"]:visible').first();
    if (await otp.count()) {
      await otp.fill(totpCode(blob.totpSeed));
      await page.keyboard.press("Enter");
      await sleep(1500);
    }
  }
  return hasForm(page);
}

async function clickByText(page, re) {
  try {
    const loc = page.getByRole("button", { name: re }).first();
    if (await loc.count()) {
      await loc.click();
      return true;
    }
  } catch {
    /* fall through */
  }
  const hit = await evalClick(page, "button,a,summary", re);
  return Boolean(hit);
}

/**
 * Drive the sudo/login challenge to completion for `account`. Returns true on
 * success (the target form is now reachable). Throws on hard failure.
 */
export async function autonomousSudo(page, account) {
  if (!account) throw new Error("autonomousSudo needs a resolved account");
  if (await hasForm(page)) return true; // not actually gated
  const blob = await getUnlockedBlob(account);

  if (await tryPasskey(page, blob.passkey)) return true;
  if (await tryPasswordTotp(page, blob)) return true;

  await shot(page, DEBUG_DIR, `autosudo-fail-${account}`);
  throw new Error(`autonomous sudo failed for ${account} (see DEBUG_DIR screenshot)`);
}
