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
  // GOTCHA #15 — click the node that CARRIES THE BEHAVIOUR, not the first node
  // whose text matches. GitHub's ActionList renders every menu row as
  //   <li class="ActionListItem" role="none"><button role="menuitemradio|option"
  //      data-value="…"> <span class="ActionListItem-label">…</span> </button>
  // The <li>, the <button> and the <span> all carry the same textContent, and
  // the <li> comes FIRST in document order — so a plain text walk clicks a
  // role="none" wrapper. That does nothing AND throws nothing, so the fallback
  // returned "clicked" and the caller believed the selection had taken.
  // Measured 2026-09-04 this silently defeated BOTH the resource-owner picker
  // and the expiration menu: the form kept its defaults (user owner, 30 days)
  // while every step reported success. Descend to the interactive child first.
  const hit = await page.evaluate(
    ({ src, flags }) => {
      const rx = new RegExp(src, flags);
      const INTERACTIVE =
        'button,[role="option"],[role="menuitemradio"],[role="menuitemcheckbox"],[role="menuitem"],a[href],input';
      const rows = document.querySelectorAll(
        '[role="option"],[role="menuitemradio"],[role="menuitemcheckbox"],[role="menuitem"],li,button,a',
      );
      for (const el of rows) {
        const t = (el.textContent || "").trim();
        if (!rx.test(t) || el.offsetParent === null) continue;
        const role = el.getAttribute("role");
        const inert = role === "none" || role === "presentation" || el.tagName === "LI";
        const target = (inert && el.querySelector(INTERACTIVE)) || el;
        if (target.getAttribute("role") === "none" || target.getAttribute("role") === "presentation") continue;
        target.click();
        return `${target.tagName}[role=${target.getAttribute("role") ?? "-"}]`;
      }
      return null;
    },
    { src: re.source, flags: re.flags },
  );
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

// Locate the "Resource owner" control by its LABEL, not by its value.
//
// GOTCHA #14 — the owner button is labelled with the CURRENT owner, so a
// selector naming the DESIRED owner can never match it before the switch. The
// original locator was getByRole("button", {name: /<spec.owner>|owner/i}): the
// button's accessible name is the signed-in login (`terrylica`), which matches
// neither alternative, so `.click()` timed out into a catch-all and the form
// silently stayed on the authenticated user. Anchor on the one string that does
// NOT change — the "Resource owner" field label — and take the first control
// inside its container.
//
// `mode` is a STRING, not a callback: github.com serves a strict CSP with no
// `unsafe-eval`, so any page-context `new Function(...)`/eval to rehydrate a
// serialised callback throws EvalError there — while passing cleanly against a
// local fixture, which is precisely the shape of test that would certify it.
// Both branches therefore live inside the one evaluated function.
export async function ownerControl(page, mode /* "read" | "open" */) {
  return page.evaluate(
    (m) => {
      const labels = [...document.querySelectorAll("label,legend,h2,h3,span,div,p")];
      const lbl = labels.find(
        (el) => /^Resource owner$/i.test((el.textContent || "").trim()) && el.offsetParent !== null,
      );
      if (!lbl) return null;
      let scope = lbl.closest("fieldset,section,div") || lbl.parentElement;
      for (let i = 0; i < 4 && scope; i++) {
        const btns = [...scope.querySelectorAll('button,[role="button"],summary')].filter(
          (b) => b.offsetParent !== null,
        );
        if (btns.length) {
          if (m === "open") btns[0].click();
          return btns
            .map((b) => (b.textContent || "").trim().replace(/\s+/g, " "))
            .filter((t) => t && t.length <= 60);
        }
        scope = scope.parentElement;
      }
      return null;
    },
    mode,
  );
}

const ownerLabels = (page) => ownerControl(page, "read");

async function setOwner(page, spec, opts = {}) {
  if (!spec.owner) return; // default = authenticated user
  const want = new RegExp(`^${esc(spec.owner)}$`, "i");

  // Attempt 1: the historical value-named locator (harmless when it misses).
  const btn = page.getByRole("button", { name: new RegExp(`${esc(spec.owner)}|owner`, "i") }).first();
  try {
    await btn.click({ timeout: 3000 });
    await sleep(600);
    await clickOption(page, want);
    await sleep(600);
  } catch {
    /* fall through — never conclude from a caught throw */
  }

  // Attempt 2: label-anchored open, then click the REAL interactive node.
  //
  // GOTCHA #15 — the owner menu row is a NON-interactive wrapper. Measured
  // 2026-09-04, each option is
  //   <li class="ActionListItem" role="none" data-src="…&target_name=<owner>">
  //     <button role="option" data-value="<owner>" tabindex="-1"> … </button>
  // Both the <li> and its inner <span class="ActionListItem-label"> have the
  // option's exact text, and the <li> comes FIRST in document order — so any
  // text-matching DOM walk (evalClick's `li,button` selector included) clicks
  // the li, whose role="none" means nothing happens and nothing throws. Target
  // `button[role=option][data-value=…]`: it is the element that carries the
  // behaviour, and data-value is a stable data attribute rather than a
  // generated CSS class. Confirmed: the control flips to the org within 1.5 s.
  if (!(await ownerLabels(page))?.some((t) => want.test(t))) {
    if (await ownerControl(page, "open")) {
      await sleep(900);
      const exact = page.locator(`button[role="option"][data-value="${spec.owner}"]`).first();
      try {
        await exact.click({ timeout: 4000 });
      } catch {
        if (!(await clickOption(page, want))) await clickOption(page, new RegExp(esc(spec.owner), "i"));
      }
      await sleep(1800); // the switch re-renders the panel via its data-src fetch
    }
  }

  // GOTCHA #13 — assert the RESULT, never the absence of an exception.
  // Every signal this function had was negative-only: clickOption() RETURNS
  // FALSE when no option matches (it does not throw), and the click above sits
  // in a catch-all whose comment asserted "owner already correct" — a guess
  // rendered as a fact. A missed resource-owner selection was therefore
  // completely silent, leaving the form on the authenticated USER with
  // repository access at "Public Repositories (read-only)". That mints a token
  // which looks repo-scoped in the spec and is account-scoped in reality:
  // measured 2026-09-04, sha256 0bc5d79ed5c1 saw 251 public repos, ZERO
  // private, and GET /repos/doorward-systems/ccmax-monitor returned 404 while
  // git receive-pack answered 403. Read the owner control back instead.
  //
  // POSITIVE REJECTION only (cf. HEART-168): throw when the control can be read
  // AND still names a different owner. An unreadable control is INCOMPLETE, so
  // it warns rather than blocking — the capability check on the minted token is
  // the real gate, and a UI rename must not be able to veto a correct mint.
  const shown = await ownerLabels(page);

  if (shown === null) {
    console.error(
      `  ! could not read the 'Resource owner' control back — INCOMPLETE, not a match.\n` +
        `    Proceeding, but VERIFY the minted token's capability before trusting it.`,
    );
    return;
  }
  const matches = (t, who) => new RegExp(`^${esc(who)}$`, "i").test(t);
  if (shown.some((t) => matches(t, spec.owner))) return; // confirmed
  const self = opts.account && shown.find((t) => matches(t, opts.account));
  if (self) {
    await shot(page, DEBUG_DIR, "owner-mismatch");
    throw new Error(
      `resource owner NOT set: the control still reads '${self}', not '${spec.owner}'. ` +
        `Minting now would produce an account-scoped token that silently cannot write to ` +
        `${spec.repositoryAccess?.repos?.[0] ?? "the selected repo"} (this is exactly how sha256 0bc5d79ed5c1 ` +
        `was produced). Refusing. Screenshot: ${DEBUG_DIR}/owner-mismatch.png`,
    );
  }
  console.error(
    `  ! 'Resource owner' read back as [${shown.join(" | ")}] — neither '${spec.owner}' nor ` +
      `'${opts.account ?? "the signed-in user"}'. INCOMPLETE; verify the minted token's capability.`,
  );
}

async function setExpiration(page, spec) {
  const exp = spec.expiration ?? 30;
  const trigger = page.getByRole("button", { name: /days \(|No expiration|Custom|Expiration/i }).first();
  await trigger.click();
  await sleep(700);
  if (exp === "none") {
    // GOTCHA #16 — "No expiration" is NOT always on the menu. An ORGANISATION
    // resource owner can cap token lifetime ("Limit set by <org>"), and when it
    // does, GitHub simply omits the option. clickExact() does not throw on a
    // miss, so the menu stayed on its 30-day default and the spec's "none" was
    // silently downgraded — a release token that dies in 30 days while the spec
    // and every review of it say "never expires". Measured 2026-09-04:
    // doorward-systems offers only 7/30/60/90/366 days + "Custom between 1 and
    // 366 days". Fail CLOSED and name the cap, rather than inventing a lifetime.
    // clickExact() RESOLVES to undefined and THROWS on a miss — so the miss must
    // be caught, never tested for falsiness (testing it would fire on success).
    let picked = true;
    try {
      await clickExact(page, "No expiration");
    } catch {
      picked = false;
    }
    if (!picked) {
      const offered = await page.evaluate(() =>
        [...document.querySelectorAll('[role="option"],[role="menuitemradio"],[role="menuitem"]')]
          .filter((e) => e.offsetParent !== null)
          .map((e) => (e.textContent || "").trim().replace(/\s+/g, " ").slice(0, 60)),
      );
      throw new Error(
        `expiration 'none' is not offered for resource owner '${spec.owner ?? "(authenticated user)"}' — ` +
          `the owner caps token lifetime. Offered: ${JSON.stringify(offered)}. ` +
          `Set spec.expiration to a permitted value (e.g. the org maximum) instead of "none".`,
      );
    }
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

  // Assert the RESULT: the trigger's own label is the selected lifetime.
  const shown = (await trigger.textContent().catch(() => "") ?? "").trim().replace(/\s+/g, " ");
  const ok =
    exp === "none"
      ? /No expiration/i.test(shown)
      : typeof exp === "number"
        ? new RegExp(`\\b${exp} days\\b`, "i").test(shown)
        : shown.length > 0;
  if (!shown) {
    // An unreadable control is INCOMPLETE, never a pass. Treating "" as OK is
    // how the 30-days-instead-of-366 downgrade survived its own assertion.
    console.error(`  ! could not read the expiration control back — INCOMPLETE; verify the minted token's expiry.`);
  } else if (!ok) {
    throw new Error(
      `expiration NOT applied: the control reads '${shown}', not '${exp === "none" ? "No expiration" : exp}'. ` +
        `Refusing to mint a token whose lifetime differs from the spec.`,
    );
  }
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
  // GOTCHA #17 — "click the LAST visible Generate token button" DOUBLE-SUBMITS.
  // GOTCHA #1 is real but conditional: the confirmation overlay only appears for
  // expiration "none". For every other lifetime there is no modal, so the last
  // visible "Generate token" button IS the form button that was just clicked,
  // and clicking it again 1.6 s later re-posted the form while the first submit
  // was still in flight. GitHub answered with a freshly-rendered form and no
  // token — indistinguishable, from the caller, from "the form was wrong".
  // Measured 2026-09-04: a GH_PAT_TRACE run proved owner=doorward-systems and
  // expiration=366 days immediately before submit, while the failure screenshot
  // showed expiration back at its 30-day default — the screenshot was of the
  // SECOND, freshly-rendered form, not of the one that was submitted.
  await page.getByRole("button", { name: /^Generate token$/i }).first().click();

  let confirmed = false;
  for (let i = 0; i < 40; i++) {
    await sleep(500);
    const tok = await extractToken(page);
    if (tok) return tok;
    // Visibility via getBoundingClientRect, not offsetParent: a button inside a
    // position:fixed overlay can report offsetParent === null while being
    // perfectly visible and clickable.
    // Detect the confirmation overlay by its HEADING (SEL.confirmModalHeading);
    // do NOT click from inside page context.
    const state = await page.evaluate((heading) => {
      const RX = /^Generate token$/i;
      const btns = [...document.querySelectorAll("button")]
        .map((x) => ({ r: x.getBoundingClientRect(), t: (x.textContent || "").trim() }))
        .filter((o) => RX.test(o.t) && o.r.width > 0 && o.r.height > 0);
      const head = [...document.querySelectorAll("h1,h2,h3,h4,strong,span,div")]
        .map((el) => ({ r: el.getBoundingClientRect(), t: (el.textContent || "").trim() }))
        .find((o) => o.t === heading && o.r.width > 0 && o.r.height > 0);
      return { visible: btns.length, overlay: Boolean(head) };
    }, SEL.confirmModalHeading);

    // GOTCHA #18 — the overlay's confirm needs a REAL mouse event. An in-page
    // HTMLElement.click() on it produced an untrusted event: the overlay closed
    // and the browser landed back on the token LIST with NO token created and no
    // error anywhere (measured 2026-09-04 — list unchanged at 4 tokens, page
    // text carrying no flash). That reads exactly like "the form was rejected",
    // which sent the investigation after the form for three rounds. Drive it
    // through Playwright instead, which dispatches a genuine CDP input event.
    // The overlay is portaled to the END of body, so `.last()` is its button —
    // but only reach for it when the overlay is actually up, otherwise `.last()`
    // is the in-form button again and we are back to GOTCHA #17's double submit.
    if (state.overlay && !confirmed) {
      confirmed = true;
      if (process.env.GH_PAT_TRACE === "1") {
        const btns = await page.evaluate(() => {
          const RX = /^Generate token$/i;
          return [...document.querySelectorAll("button")]
            .map((x) => ({ x, r: x.getBoundingClientRect(), t: (x.textContent || "").trim() }))
            .filter((o) => RX.test(o.t) && o.r.width > 0 && o.r.height > 0)
            .map((o) => {
              const chain = [];
              let n = o.x;
              for (let d = 0; d < 5 && n; d++) {
                const cls = typeof n.className === "string" ? n.className.split(/\s+/).slice(0, 2).join(".") : "";
                chain.push(n.tagName + (n.id ? `#${n.id}` : "") + (cls ? `.${cls}` : ""));
                n = n.parentElement;
              }
              return { type: o.x.type, hasForm: Boolean(o.x.form), y: Math.round(o.r.y), chain: chain.join(" < ") };
            });
        });
        btns.forEach((b, n) => {
          console.error(`  [trace] modal-btn[${n}] ${JSON.stringify(b)}`);
        });
      }
      await page
        .getByRole("button", { name: /^Generate token$/i })
        .last()
        .click({ timeout: 5000 })
        .catch(() => {});
      await sleep(1500);
    }
    if (process.env.GH_PAT_TRACE === "1")
      console.error(
        `  [trace] generate i=${i} url=${page.url()} ${JSON.stringify({ ...state, confirmed })}`,
      );
  }

  const token = await extractToken(page);
  if (!token) {
    await shot(page, DEBUG_DIR, `generate-fail-${Date.now() % 1e6}`);
    const diag = await page.evaluate(() =>
      [...document.querySelectorAll('[role="alert"],.flash,.flash-error,.error,.js-flash-alert,.color-fg-danger')]
        .filter((e) => e.offsetParent !== null)
        .map((e) => (e.textContent || "").trim().replace(/\s+/g, " ").slice(0, 200))
        .filter(Boolean),
    );
    throw new Error(
      `token not found after generate (url=${page.url()})` +
        (diag.length ? `; page says: ${JSON.stringify(diag.slice(0, 4))}` : "; no visible error on the page") +
        ` (see DEBUG_DIR screenshot)`,
    );
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
// GH_PAT_TRACE=1 prints the owner + expiration controls after every phase.
// Worth keeping: these two fields are set early and read at submit time, so a
// later phase can silently revert one of them and every per-phase assertion
// still passes. Per-phase state is the only way to see WHICH phase did it.
async function trace(page, phase) {
  if (process.env.GH_PAT_TRACE !== "1") return;
  const owner = await ownerControl(page, "read").catch(() => "?");
  const exp = await page
    .getByRole("button", { name: /days \(|No expiration|Custom|Expiration/i })
    .first()
    .textContent()
    .catch(() => "?");
  console.error(`  [trace] ${phase.padEnd(18)} owner=${JSON.stringify(owner)} exp=${JSON.stringify((exp || "").trim().replace(/\s+/g, " "))}`);
}

export async function createToken(page, spec, opts = {}) {
  await page.goto(NEW_URL, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  await ensureFormReady(page, opts.account); // handle GitHub sudo-mode "Confirm access"
  await fillNameDesc(page, spec);
  await trace(page, "fillNameDesc");
  await setOwner(page, spec, opts);
  await trace(page, "setOwner");
  await setExpiration(page, spec);
  await trace(page, "setExpiration");
  await setRepoAccess(page, spec);
  await trace(page, "setRepoAccess");
  await applyPermissions(page, spec);
  await trace(page, "applyPermissions");
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
