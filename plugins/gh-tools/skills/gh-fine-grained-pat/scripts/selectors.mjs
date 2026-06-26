// selectors.mjs — selector registry + generic anti-fragile click/wait helpers.
//
// GitHub's settings UI changes class names but keeps stable names/roles/labels.
// Every interaction prefers role/name/label, with a DOM-text fallback. When a
// selector misses, callers screenshot to DEBUG_DIR for fast repair (the live
// map is mirrored in the skill's CLAUDE.md).

export const SEL = {
  nameInput: 'input[name="user_programmatic_access[name]"]',
  descTextarea: 'textarea[name="user_programmatic_access[description]"]',
  repoPickerDialog: "#repository-menu-list-dialog",
  // Access-level dropdown buttons each contain the literal "Access:".
  accessButtonText: "Access:",
  // The generate-confirmation overlay is NOT role=dialog; identify by this heading.
  confirmModalHeading: "New personal access token",
};

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Click the first selector (CSS) that resolves to a visible element. */
export async function clickFirstCss(page, selectors, timeout = 4000) {
  for (const sel of selectors) {
    const loc = page.locator(sel).first();
    try {
      await loc.waitFor({ state: "visible", timeout: Math.min(timeout, 2500) });
      await loc.click();
      return sel;
    } catch {
      /* next */
    }
  }
  return null;
}

/** Click an element by exact visible text (role-agnostic). */
export async function clickExact(page, text) {
  const loc = page.getByText(text, { exact: true }).first();
  await loc.waitFor({ state: "visible", timeout: 5000 });
  await loc.click();
}

/**
 * DOM fallback: click the first element matching tagPredicate(textContent).
 * Returns the clicked element's trimmed text, or null.
 */
export async function evalClick(page, selector, textTest) {
  const re = textTest instanceof RegExp ? textTest.source : String(textTest);
  const flags = textTest instanceof RegExp ? textTest.flags : "";
  return page.evaluate(
    (arg) => {
      const rx = new RegExp(arg.re, arg.flags);
      for (const el of document.querySelectorAll(arg.selector)) {
        const t = (el.textContent || "").trim();
        if (rx.test(t) && el.offsetParent !== null) {
          el.click();
          return t.replace(/\s+/g, " ").slice(0, 60);
        }
      }
      return null;
    },
    { selector, re, flags },
  );
}

/** Capture a debug screenshot; never throws. */
export async function shot(page, dir, name) {
  try {
    await page.screenshot({ path: `${dir}/${name}.png`, fullPage: true });
  } catch {
    /* ignore */
  }
}
