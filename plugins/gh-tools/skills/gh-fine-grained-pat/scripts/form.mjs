// form.mjs — drive GitHub's fine-grained PAT UI from a declarative spec.
//
// Encodes the gotchas learned the hard way (see CLAUDE.md "Hard-won gotchas"):
//   1. The generate-confirmation overlay is NOT role=dialog — detect by heading
//      and click the LAST visible "Generate token" button (portaled to body end).
//   2. The repo picker (#repository-menu-list-dialog) intercepts pointer events —
//      close it via its X before any later click.
//   3. "No expiration" is selectable inline; its confirmation arrives at the
//      generate-time summary modal (handled by generate()).
//   4. Permission access levels: open each row's "Access:" button → pick the
//      "Read-only" / "Read and write" menuitemradio. Metadata is auto-required RO.

import { DEBUG_DIR } from "./browser.mjs";
import { SEL, sleep, clickExact, evalClick, shot } from "./selectors.mjs";

const NEW_URL = "https://github.com/settings/personal-access-tokens/new";
const LIST_URL = "https://github.com/settings/personal-access-tokens";
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const LEVEL_LABEL = { read: "Read-only", write: "Read and write" };

// ---- generic menu-option click (role-first, DOM fallback) -------------------
async function clickOption(page, re) {
  for (const role of ["menuitemradio", "menuitemcheckbox", "option", "menuitem"]) {
    const loc = page.getByRole(role, { name: re }).first();
    try {
      await loc.waitFor({ state: "visible", timeout: 1500 });
      await loc.click();
      return true;
    } catch {
      /* next role */
    }
  }
  const hit = await evalClick(page, '[role="option"],[role="menuitemradio"],[role="menuitemcheckbox"],li,button', re);
  return Boolean(hit);
}

// ---- individual steps -------------------------------------------------------
async function fillNameDesc(page, spec) {
  await page.fill(SEL.nameInput, spec.name);
  if (spec.description) {
    const d = page.locator(SEL.descTextarea);
    if (await d.count()) await d.fill(spec.description);
  }
  await sleep(250);
}

async function setOwner(page, spec) {
  if (!spec.owner) return; // default = authenticated user
  const btn = page.getByRole("button", { name: new RegExp(`${esc(spec.owner)}|owner`, "i") }).first();
  try {
    await btn.click();
    await sleep(600);
    await clickOption(page, new RegExp(`^${esc(spec.owner)}$`, "i"));
    await sleep(600);
  } catch {
    /* owner already correct */
  }
}

async function setExpiration(page, spec) {
  const exp = spec.expiration ?? 30;
  await page.getByRole("button", { name: /days \(|No expiration|Custom|Expiration/i }).first().click();
  await sleep(700);
  if (exp === "none") {
    await clickExact(page, "No expiration");
  } else if (typeof exp === "number") {
    if (!(await clickOption(page, new RegExp(`^${exp} days`, "i")))) throw new Error(`expiration option '${exp} days' not found`);
  } else {
    // custom ISO date
    await clickOption(page, /^Custom/i);
    await sleep(500);
    const dateInput = page.locator('input[type="date"]:visible, input[name*="custom" i]:visible').first();
    await dateInput.fill(exp);
  }
  await sleep(600);
}

async function setRepoAccess(page, spec) {
  const ra = spec.repositoryAccess ?? { mode: "public" };
  if (ra.mode === "all") return void (await clickExact(page, "All repositories"));
  if (ra.mode === "public") return void (await clickExact(page, "Public repositories"));

  await clickExact(page, "Only select repositories");
  await sleep(900);
  await page.getByRole("button", { name: /Select repositories/i }).first().click();
  await sleep(1000);
  const search = page.locator('input[type="search"]:visible, input[placeholder*="Search" i]:visible').first();
  for (const repo of ra.repos) {
    await search.fill(repo.split("/")[1]);
    await sleep(1400);
    await clickExact(page, repo);
    await sleep(700);
    await search.fill("");
    await sleep(300);
  }
  // GOTCHA #2: close the picker (it intercepts pointer events) via its X.
  await page.evaluate((dlgSel) => {
    const dlg = document.querySelector(dlgSel);
    const x = dlg?.querySelector('button[aria-label="Close"], button[aria-label*="close" i]');
    x?.click();
  }, SEL.repoPickerDialog);
  await sleep(700);
}

// Permissions live under TWO tabs ("Repositories" / "Account"), each with its
// OWN "Add permissions" menu. Repository perms (Contents, …) are only in the
// repo menu; account perms (Gists, …) only in the account menu.
async function switchTab(page, name) {
  try {
    await page.getByRole("tab", { name: new RegExp(name, "i") }).first().click();
  } catch {
    await evalClick(page, '[role="tab"],button,a', new RegExp(name, "i"));
  }
  await sleep(600);
}

async function applyGroup(page, pairs, tab) {
  if (pairs.length === 0) return;
  if (tab) await switchTab(page, tab); // repository tab is the default

  // add each permission via this tab's menu
  await page.getByRole("button", { name: /Add permissions/i }).first().click();
  await sleep(1000);
  const menuSearch = page.locator('input[placeholder="Search" i]:visible').first();
  for (const [label] of pairs) {
    if (await menuSearch.count()) {
      await menuSearch.fill(label);
      await sleep(650);
    }
    if (!(await clickOption(page, new RegExp(`^${esc(label)}$`, "i"))))
      throw new Error(`permission '${label}' not found in the ${tab ? "account" : "repository"} permissions menu`);
    await sleep(350);
    if (await menuSearch.count()) await menuSearch.fill("");
  }
  await page.keyboard.press("Escape");
  await sleep(800);

  // set access levels — the rows are now visible under the active tab
  for (const [label, level] of pairs) {
    const target = LEVEL_LABEL[level];
    const handle = await rowAccessHandle(page, label);
    const el = handle.asElement();
    if (!el) throw new Error(`access row for '${label}' not found`);
    const current = (await el.evaluate((b) => b.textContent || "")).replace(/\s+/g, " ");
    if (current.includes(target)) continue; // already at target (default RO etc.)
    await el.click();
    await sleep(550);
    if (!(await clickOption(page, new RegExp(`^${esc(target)}$`, "i"))))
      throw new Error(`level '${target}' not selectable for '${label}'`);
    await sleep(450);
  }
}

async function applyPermissions(page, spec) {
  await applyGroup(page, Object.entries(spec.permissions?.repository ?? {}), null);
  await applyGroup(page, Object.entries(spec.permissions?.account ?? {}), "Account");
}

/** Find a permission row's "Access:" button by its heading prefix. */
async function rowAccessHandle(page, label) {
  return page.evaluateHandle(
    (arg) => {
      const btns = [...document.querySelectorAll("button")].filter(
        (b) => /Access:/i.test(b.textContent || "") && b.offsetParent !== null,
      );
      for (const b of btns) {
        let row = b;
        for (let k = 0; k < 6 && row.parentElement; k++) {
          row = row.parentElement;
          if (row.querySelector("h2,h3,h4,strong,b")) break;
        }
        const head = (row.querySelector("h2,h3,h4,strong,b")?.textContent || "").trim();
        if (head.toLowerCase().startsWith(arg.label.toLowerCase())) return b;
      }
      return null;
    },
    { label },
  );
}

async function extractToken(page) {
  return page.evaluate(() => {
    for (const inp of document.querySelectorAll("input")) if ((inp.value || "").startsWith("github_pat_")) return inp.value;
    for (const el of document.querySelectorAll("code,span,div")) {
      const t = (el.textContent || "").trim();
      if (/^github_pat_[A-Za-z0-9_]+$/.test(t)) return t;
    }
    return "";
  });
}

async function generate(page) {
  await page.getByRole("button", { name: /^Generate token$/i }).first().click();
  await sleep(1600);
  // GOTCHA #1: confirmation overlay is not role=dialog. Click the LAST visible
  // "Generate token" button (the modal's, portaled to end of body) if present.
  await page.evaluate(() => {
    const btns = [...document.querySelectorAll("button")].filter(
      (b) => b.offsetParent !== null && /^Generate token$/i.test((b.textContent || "").trim()),
    );
    if (btns.length) btns[btns.length - 1].click();
  });
  await sleep(2600);
  const token = await extractToken(page);
  if (!token) {
    await shot(page, DEBUG_DIR, `generate-fail-${Date.now() % 1e6}`);
    throw new Error("token not found after generate (see DEBUG_DIR screenshot)");
  }
  return token;
}

// GitHub "sudo mode": sensitive pages (token creation) show a "Confirm access"
// challenge when the session hasn't re-authed recently. Default = wait for the
// operator. With GH_PAT_AUTONOMOUS=1 + a resolved account, satisfy it via the
// gated github-web-<account> credential (one Touch-ID unlock per session).
async function ensureFormReady(page, account) {
  const hasForm = async () => (await page.locator(SEL.nameInput).count()) > 0;
  if (await hasForm()) return;
  if (!/confirm access/i.test(await page.title())) return; // unknown state — let caller fail loudly

  if (process.env.GH_PAT_AUTONOMOUS === "1" && account) {
    try {
      const { autonomousSudo } = await import("./autosudo.mjs");
      if (await autonomousSudo(page, account)) return void console.error(`✓ autonomous sudo (${account})`);
    } catch (e) {
      console.error(`autonomous sudo failed (${e.message}); falling back to manual confirm`);
    }
  }

  console.error("⚠ GitHub sudo mode — confirm access in the Chrome window (passkey / 2FA). Waiting up to 8 min…");
  // Do NOT reload the page — that would wipe a half-typed password/2FA. After a
  // successful confirm GitHub auto-redirects back to the form; just poll for it.
  for (let i = 0; i < 96; i++) {
    await sleep(5000);
    if (await hasForm()) return void console.error("✓ sudo confirmed");
  }
  throw new Error("sudo confirmation timed out — confirm access in the browser and retry");
}

// ---- public API -------------------------------------------------------------
/** Drive the whole form from a spec; returns the github_pat_ value. */
export async function createToken(page, spec, opts = {}) {
  await page.goto(NEW_URL, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  await ensureFormReady(page, opts.account); // handle GitHub sudo-mode "Confirm access"
  await fillNameDesc(page, spec);
  await setOwner(page, spec);
  await setExpiration(page, spec);
  await setRepoAccess(page, spec);
  await applyPermissions(page, spec);
  return generate(page);
}

/** Scrape the fine-grained token list: [{ id, name }]. */
export async function listTokens(page) {
  await page.goto(LIST_URL, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(900);
  const rows = await page.evaluate(() => {
    const seen = new Map();
    for (const a of document.querySelectorAll('a[href*="/settings/personal-access-tokens/"]')) {
      const href = a.getAttribute("href") || "";
      // Capture ONLY the token-name link (.../<id>); skip .../<id>/regenerate?...
      // and .../new, whose text is metadata not a token name.
      const m = href.match(/\/personal-access-tokens\/(\d+)(?:[?#]|$)/);
      const name = (a.textContent || "").trim();
      if (m && name) seen.set(m[1], { id: m[1], name });
    }
    return [...seen.values()];
  });
  return rows;
}

/** Read back a token's detail page for verification. */
export async function inspectToken(page, name) {
  const tok = (await listTokens(page)).find((t) => t.name === name);
  if (!tok) return { found: false };
  await page.goto(`${LIST_URL}/${tok.id}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(900);
  const data = await page.evaluate(() => {
    const text = (document.body.innerText || "").replace(/\s+/g, " ");
    const repos = [];
    for (const a of document.querySelectorAll('a[href^="/"]')) {
      const t = (a.textContent || "").trim();
      if (/^[\w.-]+\/[\w.-]+$/.test(t)) repos.push(t);
    }
    return { text, repos: [...new Set(repos)] };
  });
  return { found: true, id: tok.id, ...data };
}

/** Delete a token by name (resolve id, open detail, confirm). Returns boolean. */
export async function deleteToken(page, name) {
  const tok = (await listTokens(page)).find((t) => t.name === name);
  if (!tok) return false;
  await page.goto(`${LIST_URL}/${tok.id}`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(800);
  // Danger-zone "Delete" button.
  const del = page.getByRole("button", { name: /Delete (this )?(personal access )?token/i }).first();
  try {
    await del.click();
  } catch {
    await evalClick(page, "button,summary,a", /^Delete/i);
  }
  await page.waitForTimeout(900);
  // Confirmation modal.
  await page.evaluate(() => {
    const b = [...document.querySelectorAll("button")].find(
      (x) => x.offsetParent !== null && /I understand|delete this token|confirm/i.test((x.textContent || "").trim()),
    );
    b?.click();
  });
  await page.waitForTimeout(1500);
  const still = (await listTokens(page)).some((t) => t.name === name);
  return !still;
}
