#!/usr/bin/env npx tsx
/**
 * Probe current research state + extract share link if complete.
 *
 * Commands:
 *   status   — Check research completion state (default)
 *   extract  — Click Share button and extract link
 */

import { chromium } from "playwright-core";

async function main() {
  const resp = await fetch("http://127.0.0.1:9222/json/version");
  const data = (await resp.json()) as { webSocketDebuggerUrl: string };
  const browser = await chromium.connectOverCDP(data.webSocketDebuggerUrl);
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find((p) => p.url().includes("gemini.google.com"));
  if (!page) throw new Error("No Gemini page");

  const command = process.argv[2] ?? "status";

  if (command === "status") {
    const state = await page.evaluate(() => {
      const mic = document.querySelector('button[data-node-type="speech_dictation_mic_button"]');
      const spinner = document.querySelector('div[class*="avatar_spinner_animation"]');
      const modelEls = document.querySelectorAll(
        '[data-message-author="model"], [class*="model-turn"], [class*="response-content"]',
      );
      let maxTextLen = 0;
      for (const el of modelEls) {
        const text = (el.textContent ?? "").trim();
        if (text.length > maxTextLen) maxTextLen = text.length;
      }
      return {
        micVisible: mic ? (mic as HTMLElement).offsetParent !== null : false,
        spinnerVisible: spinner ? (spinner as HTMLElement).offsetParent !== null : false,
        responseTextLen: maxTextLen,
      };
    });

    const isDone = state.micVisible && !state.spinnerVisible;
    console.log(`Status: ${isDone ? "COMPLETE" : "RESEARCHING"}`);
    console.log(`  mic=${state.micVisible} spinner=${state.spinnerVisible}`);
    console.log(`  responseLen=${state.responseTextLen}`);

    if (isDone) {
      console.log("\nResearch is COMPLETE. Run: npx tsx share-link.ts extract");
    }
  } else if (command === "extract") {
    console.log("Clicking Share button...");
    const shareBtn = await page.$('button[data-test-id="share-button"]');
    if (!shareBtn) {
      console.log("No share button found");
      await browser.close();
      return;
    }
    await shareBtn.click();
    await new Promise((r) => setTimeout(r, 2000));

    const shareLink = await page.evaluate(() => {
      const inputs = document.querySelectorAll('input[type="text"], input[readonly]');
      for (const input of inputs) {
        const val = (input as HTMLInputElement).value;
        if (val.includes("gemini.google.com/share/")) return val;
      }
      const links = document.querySelectorAll("a");
      for (const link of links) {
        if (link.href.includes("gemini.google.com/share/")) return link.href;
      }
      const allEls = document.querySelectorAll("span, div, p");
      for (const el of allEls) {
        const text = (el.textContent ?? "").trim();
        if (text.includes("gemini.google.com/share/") && text.length < 100) return text;
      }
      return null;
    });

    console.log(`Share link: ${shareLink ?? "NOT FOUND"}`);

    await page.screenshot({ path: "/tmp/gemini-share-dialog.png" });
    console.log("Screenshot: /tmp/gemini-share-dialog.png");

    await page.keyboard.press("Escape");
  }

  await browser.close();
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
