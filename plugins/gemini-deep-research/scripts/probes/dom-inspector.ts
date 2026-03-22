#!/usr/bin/env npx tsx
/**
 * Interactive DOM probing script for Gemini Deep Research.
 *
 * Commands:
 *   launch     — Launch Chrome with debug port 9222
 *   status     — Check if Chrome debug port is reachable
 *   probe      — Connect and dump DOM structure of Gemini page
 *   selectors  — Test all selector groups from our registry
 *   screenshot — Take a screenshot of the current page
 */

import { chromium } from "playwright-core";

const CDP_PORT = 9222;
const CDP_URL = `http://127.0.0.1:${CDP_PORT}`;
const GEMINI_URL = "https://gemini.google.com/app";

async function getChromeWsUrl(): Promise<string | null> {
  try {
    const resp = await fetch(`${CDP_URL}/json/version`);
    const data = (await resp.json()) as { webSocketDebuggerUrl?: string };
    return data.webSocketDebuggerUrl ?? null;
  } catch {
    return null;
  }
}

async function cmdStatus() {
  const wsUrl = await getChromeWsUrl();
  if (wsUrl) {
    console.log(`Chrome debug port reachable at ${CDP_URL}`);
    console.log(`WebSocket: ${wsUrl}`);

    const browser = await chromium.connectOverCDP(wsUrl);
    const contexts = browser.contexts();
    console.log(`\nContexts: ${contexts.length}`);
    for (const ctx of contexts) {
      const pages = ctx.pages();
      for (const page of pages) {
        const url = page.url();
        const isGemini = url.includes("gemini.google.com");
        console.log(`  ${isGemini ? ">> " : "   "}${url}`);
      }
    }
    await browser.close();
  } else {
    console.log(`Chrome debug port NOT reachable at ${CDP_URL}`);
    console.log("Launch Chrome with: npx tsx dom-inspector.ts launch");
  }
}

async function cmdLaunch() {
  const wsUrl = await getChromeWsUrl();
  if (wsUrl) {
    console.log("Chrome is already running with debug port. Skipping launch.");
    return;
  }

  const { execSync } = await import("child_process");
  const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

  console.log(`Launching Chrome with --remote-debugging-port=${CDP_PORT}...`);
  console.log("A new Chrome window will open. Please:");
  console.log("  1. Navigate to https://gemini.google.com/app");
  console.log("  2. Log in with your Google account (Gemini Advanced subscription)");
  console.log("  3. Come back here and run: npx tsx dom-inspector.ts probe");

  execSync(
    `"${chromePath}" --remote-debugging-port=${CDP_PORT} --user-data-dir="/tmp/gemini-probe-profile" "${GEMINI_URL}" &`,
    { stdio: "ignore", shell: "/bin/zsh" },
  );

  await new Promise((r) => setTimeout(r, 2000));
  const check = await getChromeWsUrl();
  if (check) {
    console.log("\nChrome launched successfully. Debug port is reachable.");
  } else {
    console.log("\nChrome launched but debug port not yet reachable. Wait a moment and try 'status'.");
  }
}

async function getGeminiPage() {
  const wsUrl = await getChromeWsUrl();
  if (!wsUrl) throw new Error("Chrome debug port not reachable. Run 'launch' first.");

  const browser = await chromium.connectOverCDP(wsUrl);
  const contexts = browser.contexts();

  for (const ctx of contexts) {
    const pages = ctx.pages();
    const geminiPage = pages.find((p) => p.url().includes("gemini.google.com"));
    if (geminiPage) return { browser, page: geminiPage };
  }

  throw new Error("No Gemini page found. Navigate to gemini.google.com in the Chrome window.");
}

async function cmdProbe() {
  const { browser, page } = await getGeminiPage();
  console.log(`Connected to: ${page.url()}\n`);

  console.log("=== INTERACTIVE ELEMENTS ===");
  const interactives = await page.evaluate(() => {
    const results: Array<{
      tag: string; role: string; ariaLabel: string;
      text: string; classes: string; dataAttrs: string; visible: boolean;
    }> = [];

    const els = document.querySelectorAll(
      'button, [role="button"], [role="menuitem"], [role="option"], ' +
      '[role="textbox"], [contenteditable="true"], textarea, input, ' +
      '[role="listbox"], [role="menu"], [role="combobox"]',
    );

    for (const el of els) {
      const htmlEl = el as HTMLElement;
      const rect = htmlEl.getBoundingClientRect();
      const visible = rect.width > 0 && rect.height > 0 && htmlEl.offsetParent !== null;

      const dataAttrs = Array.from(el.attributes)
        .filter((a) => a.name.startsWith("data-"))
        .map((a) => `${a.name}="${a.value}"`)
        .join(" ");

      const text = (htmlEl.textContent ?? "").trim().slice(0, 80);
      const ariaLabel = el.getAttribute("aria-label") ?? "";

      if (text || ariaLabel || dataAttrs) {
        results.push({
          tag: el.tagName.toLowerCase(),
          role: el.getAttribute("role") ?? "",
          ariaLabel,
          text: text.replace(/\n/g, " "),
          classes: (el.className ?? "").toString().slice(0, 100),
          dataAttrs,
          visible,
        });
      }
    }
    return results;
  });

  for (const el of interactives) {
    if (!el.visible) continue;
    const parts = [`[${el.tag}]`];
    if (el.role) parts.push(`role="${el.role}"`);
    if (el.ariaLabel) parts.push(`aria-label="${el.ariaLabel}"`);
    if (el.dataAttrs) parts.push(el.dataAttrs);
    if (el.text) parts.push(`text: "${el.text}"`);
    console.log(`  ${parts.join(" | ")}`);
  }

  console.log("\n=== INPUT AREA ===");
  const inputInfo = await page.evaluate(() => {
    const selectors = [
      'div[contenteditable="true"]',
      '[placeholder*="Gemini"]',
      'div[role="textbox"]',
      "textarea",
      '[aria-label*="prompt"]',
    ];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el) {
        return {
          found: true, selector: sel, tag: el.tagName,
          classes: (el.className ?? "").toString().slice(0, 200),
          ariaLabel: el.getAttribute("aria-label") ?? "",
          placeholder: el.getAttribute("placeholder") ?? el.getAttribute("data-placeholder") ?? "",
        };
      }
    }
    return { found: false };
  });
  console.log(JSON.stringify(inputInfo, null, 2));

  console.log("\n=== DEEP RESEARCH ELEMENTS ===");
  const drElements = await page.evaluate(() => {
    const results: string[] = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const el = node as HTMLElement;
      const text = (el.textContent ?? "").toLowerCase();
      const ariaLabel = (el.getAttribute("aria-label") ?? "").toLowerCase();
      if (
        (text.includes("deep research") || ariaLabel.includes("deep research")) &&
        (el.textContent ?? "").length < 200
      ) {
        const rect = el.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          results.push(
            `<${el.tagName.toLowerCase()} class="${(el.className ?? "").toString().slice(0, 80)}" ` +
            `aria-label="${el.getAttribute("aria-label") ?? ""}"> ${(el.textContent ?? "").trim().slice(0, 80)}`,
          );
        }
      }
    }
    return [...new Set(results)].slice(0, 20);
  });
  for (const el of drElements) console.log(`  ${el}`);

  await browser.close();
}

async function cmdSelectors() {
  const { browser, page } = await getGeminiPage();
  console.log(`Connected to: ${page.url()}\n`);

  const { SELECTORS } = await import("../selectors.js");

  console.log("=== TESTING SELECTOR REGISTRY ===\n");

  for (const [groupName, selectors] of Object.entries(SELECTORS)) {
    console.log(`--- ${groupName} ---`);
    for (const selector of selectors as readonly string[]) {
      try {
        const count = await page.locator(selector).count();
        const visible =
          count > 0 ? await page.locator(selector).first().isVisible().catch(() => false) : false;
        const status = count === 0 ? "  MISS" : visible ? ">> HIT" : "  hidden";
        console.log(`  ${status}  ${selector}  (${count} match${count !== 1 ? "es" : ""})`);
      } catch (e) {
        console.log(`  ERROR  ${selector}  (${(e as Error).message.slice(0, 60)})`);
      }
    }
    console.log();
  }

  await browser.close();
}

async function cmdScreenshot() {
  const { browser, page } = await getGeminiPage();
  const path = `/tmp/gemini-probe-${Date.now()}.png`;
  await page.screenshot({ path, fullPage: true });
  console.log(`Screenshot saved: ${path}`);
  await browser.close();
}

// ── Main ──

const command = process.argv[2] ?? "status";
const commands: Record<string, () => Promise<void>> = {
  status: cmdStatus,
  launch: cmdLaunch,
  probe: cmdProbe,
  selectors: cmdSelectors,
  screenshot: cmdScreenshot,
};

const fn = commands[command];
if (!fn) {
  console.log(`Unknown command: ${command}`);
  console.log(`Available: ${Object.keys(commands).join(", ")}`);
  process.exit(1);
}

fn().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
