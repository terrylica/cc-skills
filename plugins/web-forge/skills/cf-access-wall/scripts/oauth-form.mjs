// oauth-form.mjs — find the fields of GitHub's "New OAuth App" form by their visible label first, then by a name
// pattern that survives a rename, never by one exact `name`. GitHub renamed the callback field on 2026-11-16
// (`oauth_application[callback_url]` → a "Redirect URI" list, `oauth_application[application_callback_urls_attributes][0][url]`),
// and the exact-name selector the forge used then matched nothing. Old and new shapes: oauth-form.test.ts.
//
// Pure: no Playwright import. `readControls` is self-contained source for `page.evaluate`; `pickField` and
// `selectorFor` are unit-tested without a browser.

/** Each logical field: its label (every wording seen) and a pattern for its `name`, tried in that order. */
export const OAUTH_APP_FIELDS = {
  name: { label: /^application name\b/i, name: /^oauth_application\[name\]$/ },
  homepage: { label: /^homepage url\b/i, name: /^oauth_application\[(homepage_)?url\]$/ },
  // "Authorization callback URL" until 2026-11; "Redirect URI" (one row per URI, row 0 on a fresh form) since.
  callback: { label: /^(authorization callback url|callback url|redirect uri)\b/i, name: /^oauth_application\[[^\]]*callback[^\]]*\]/ },
};

const FILLABLE_INPUT_TYPES = new Set(["", "text", "url", "email", "search"]);

/** A control a value can be typed into: a text-like input or a textarea (never hidden, checkbox or button). */
export function isFillable(c) {
  if (c.tag === "textarea") return true;
  return c.tag === "input" && FILLABLE_INPUT_TYPES.has((c.type ?? "").toLowerCase());
}

const describeControl = (c) => `${c.name ?? "(no name)"} "${c.label ?? ""}"`;

/**
 * The one control for `key` (a key of OAUTH_APP_FIELDS): label match first, then name match. Refuses when a
 * rule matches several controls (it never guesses) or when nothing matches (the form drifted again).
 */
export function pickField(controls, key) {
  const spec = OAUTH_APP_FIELDS[key];
  if (!spec) throw new Error(`unknown OAuth app field "${key}"`);
  const fillable = controls.filter(isFillable);
  const rules = [
    ["label", (c) => spec.label.test((c.label ?? "").trim())],
    ["name", (c) => spec.name.test(c.name ?? "")],
  ];
  for (const [how, matches] of rules) {
    const hits = fillable.filter(matches);
    if (hits.length === 1) return { ...hits[0], matchedBy: how };
    if (hits.length > 1) {
      throw new Error(`${hits.length} fields match the ${key} ${how} (${hits.map(describeControl).join(", ")}); refusing to guess`);
    }
  }
  const seen = fillable.map(describeControl).join(", ") || "none";
  throw new Error(
    `no ${key} field on GitHub's OAuth app form (fillable fields: ${seen}); the form changed again: ` +
      "update OAUTH_APP_FIELDS in oauth-form.mjs and the dashboard-forge Vendor Quirks log",
  );
}

const cssString = (s) => s.replace(/["\\]/g, "\\$&");

/** A CSS selector for one picked control: its id when it has one, else tag + exact name. */
export function selectorFor(c) {
  if (c.id) return `[id="${cssString(c.id)}"]`;
  if (c.name) return `${c.tag}[name="${cssString(c.name)}"]`;
  throw new Error(`control "${c.label ?? ""}" has neither id nor name`);
}

/**
 * Runs IN THE PAGE (`await page.evaluate(readControls)`), so it references nothing outside itself. Lists every
 * control named `oauth_application[…]`: tag, type, name, id, and its label (label[for], wrapping label,
 * aria-label, aria-labelledby). Values are never read.
 */
export function readControls() {
  const text = (el) => (el?.innerText ?? el?.textContent ?? "").replace(/\s+/g, " ").trim();
  const labelOf = (e) => {
    const byFor = e.id ? document.querySelector(`label[for="${CSS.escape(e.id)}"]`) : null;
    if (byFor) return text(byFor);
    const wrapping = e.closest("label");
    if (wrapping) return text(wrapping);
    if (e.getAttribute("aria-label")) return e.getAttribute("aria-label").trim();
    const ids = (e.getAttribute("aria-labelledby") ?? "").split(/\s+/).filter(Boolean);
    return ids.map((id) => text(document.getElementById(id))).join(" ").trim();
  };
  return [...document.querySelectorAll('input[name^="oauth_application["], textarea[name^="oauth_application["], select[name^="oauth_application["]')].map((e) => ({
    tag: e.tagName.toLowerCase(),
    type: e.type,
    name: e.name || null,
    id: e.id || null,
    label: labelOf(e),
  }));
}
