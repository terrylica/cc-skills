#!/usr/bin/env npx tsx
/**
 * Research execution monitor — click "Start research", poll completion, probe share buttons.
 *
 * Commands:
 *   confirm-and-monitor  — Click confirm button + monitor execution (default)
 *   probe-share          — Probe share/export buttons on current page
 */

import { chromium, type Page } from "playwright-core";

async function getGeminiPage() {
  const resp = await fetch("http://127.0.0.1:9222/json/version");
  const data = (await resp.json()) as { webSocketDebuggerUrl: string };
  const browser = await chromium.connectOverCDP(data.webSocketDebuggerUrl);
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find((p) => p.url().includes("gemini.google.com"));
  if (!page) throw new Error("No Gemini page");
  return { browser, page };
}

async function probeShareButtons(page: Page) {
  console.log("\n=== PROBING SHARE/EXPORT BUTTONS ===");

  const shareInfo = await page.evaluate(() => {
    const results: string[] = [];
    const allBtns = document.querySelectorAll("button, [role='button'], a[role='button']");
    for (const btn of allBtns) {
      const ariaLabel = btn.getAttribute("aria-label") ?? "";
      const text = (btn.textContent ?? "").trim();
      const testId = btn.getAttribute("data-test-id") ?? "";
      const rect = (btn as HTMLElement).getBoundingClientRect();
      if (rect.width === 0) continue;

      const lowerLabel = ariaLabel.toLowerCase();
      const lowerText = text.toLowerCase();
      if (
        lowerLabel.includes("share") || lowerLabel.includes("export") ||
        lowerLabel.includes("copy") || lowerText.includes("share") ||
        lowerText.includes("export") || lowerText.includes("copy") ||
        testId.includes("share") || testId.includes("export")
      ) {
        results.push(
          `<${btn.tagName.toLowerCase()} aria="${ariaLabel}" test-id="${testId}"> "${text.slice(0, 60)}"`,
        );
      }
    }
    return [...new Set(results)];
  });

  for (const line of shareInfo) console.log("  " + line);
}

async function main() {
  const { browser, page } = await getGeminiPage();
  const command = process.argv[2] ?? "confirm-and-monitor";

  if (command === "confirm-and-monitor") {
    const confirmBtn = await page.$('button[data-test-id="confirm-button"]');
    if (!confirmBtn) {
      console.log("No confirm button found. Is there a research plan waiting?");
      await browser.close();
      return;
    }

    console.log("Clicking 'Start research'...");
    await confirmBtn.click();
    console.log("Confirmed at", new Date().toISOString());

    const startTime = Date.now();
    const maxDurationMs = 35 * 60 * 1000;
    const pollIntervalMs = 10000;
    let lastTextLen = 0;
    let stableCount = 0;

    for (let elapsed = 0; elapsed < maxDurationMs; elapsed += pollIntervalMs) {
      await new Promise((r) => setTimeout(r, pollIntervalMs));
      const elapsedSec = Math.round((Date.now() - startTime) / 1000);
      const elapsedMin = Math.round(elapsedSec / 60);

      const snapshot = await page.evaluate(() => {
        const r: Record<string, string | number | boolean> = {};

        const mic = document.querySelector('button[data-node-type="speech_dictation_mic_button"]');
        r.micVisible = mic ? (mic as HTMLElement).offsetParent !== null : false;

        const spinner = document.querySelector('div[class*="avatar_spinner_animation"]');
        r.spinnerVisible = spinner ? (spinner as HTMLElement).offsetParent !== null : false;

        const allBtns = document.querySelectorAll("button");
        r.stopVisible = false;
        for (const btn of allBtns) {
          if ((btn.getAttribute("aria-label") ?? "").toLowerCase().includes("stop")) {
            r.stopVisible = (btn as HTMLElement).offsetParent !== null;
            break;
          }
        }

        const modelEls = document.querySelectorAll(
          '[data-message-author="model"], [class*="model-turn"], [class*="response-content"]',
        );
        let maxTextLen = 0;
        for (const el of modelEls) {
          const text = (el.textContent ?? "").trim();
          if (text.length > maxTextLen) maxTextLen = text.length;
        }
        r.responseTextLen = maxTextLen;

        return r;
      });

      const isSearching = snapshot.spinnerVisible && !snapshot.micVisible;
      const isDone = (snapshot.micVisible as boolean) && !(snapshot.spinnerVisible as boolean);
      const status = isDone ? "DONE" : isSearching ? "RESEARCHING" : "UNKNOWN";

      console.log(`\n[${elapsedMin}m${elapsedSec % 60}s] ${status}`);
      console.log(`  spinner=${snapshot.spinnerVisible} mic=${snapshot.micVisible} stop=${snapshot.stopVisible}`);
      console.log(`  response=${snapshot.responseTextLen} chars`);

      const textLen = snapshot.responseTextLen as number;
      if (textLen > 500) {
        if (textLen === lastTextLen) stableCount++;
        else { lastTextLen = textLen; stableCount = 0; }
      }

      if (isDone && stableCount >= 2 && textLen > 500) {
        console.log(`\n>>> RESEARCH COMPLETE at ${elapsedMin}m${elapsedSec % 60}s (${textLen} chars)`);
        await page.screenshot({ path: "/tmp/gemini-research-complete.png" });
        await probeShareButtons(page);
        break;
      }
    }
  } else if (command === "probe-share") {
    await probeShareButtons(page);
  }

  await browser.close();
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
