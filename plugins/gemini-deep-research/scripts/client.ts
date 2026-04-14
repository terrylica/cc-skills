/**
 * Gemini Deep Research Browser Client (Standalone)
 *
 * Automates the Gemini Deep Research UI flow via Playwright CDP:
 *   1. Connect to Chrome on debug port 9222
 *   2. Navigate to gemini.google.com/app
 *   3. Activate Deep Research mode (Tools → Deep research chip)
 *   4. Type query + send
 *   5. Wait for research plan (~120s)
 *   6. Confirm/start research
 *   7. Poll for completion (mic button + text stability, 30min max)
 *   8. Extract report + share link + optional Firecrawl scrape
 */

import { chromium, type BrowserContext, type Page } from "playwright-core";
import { SELECTORS } from "./selectors.js";

// ──────────────────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────────────────

export interface DeepResearchClientOptions {
  /** CDP endpoint URL. Default: http://127.0.0.1:9222 */
  cdpUrl?: string;
  /** Maximum time to wait for research completion (ms). Default: 30 min */
  maxResearchTimeMs?: number;
  /** How often to poll for completion (ms). Default: 5s */
  pollIntervalMs?: number;
  /** Whether to auto-confirm the research plan. Default: true */
  autoConfirm?: boolean;
  /** Callback for progress updates */
  onProgress?: (message: string) => void;
  /** Firecrawl endpoint for scraping share links. Default: http://localhost:3002 */
  firecrawlUrl?: string;
  /** Whether to extract share link and scrape via Firecrawl. Default: false */
  enableFirecrawl?: boolean;
}

export interface DeepResearchResult {
  /** The final research report text (markdown) */
  report: string;
  /** The research plan that was generated */
  plan?: string;
  /** Whether the research completed successfully */
  completed: boolean;
  /** Duration in ms */
  durationMs: number;
  /** Error message if failed */
  error?: string;
  /** Shareable link (gemini.google.com/share/{id}) */
  shareLink?: string;
  /** Full markdown from Firecrawl scrape of share link */
  firecrawlMarkdown?: string;
}

// ──────────────────────────────────────────────────────────────────────
// Client
// ──────────────────────────────────────────────────────────────────────

export class GeminiDeepResearchClient {
  private context: BrowserContext | null = null;
  private page: Page | null = null;
  private initialized = false;

  private readonly cdpUrl: string;
  private readonly maxResearchTimeMs: number;
  private readonly pollIntervalMs: number;
  private readonly autoConfirm: boolean;
  private readonly log: (msg: string) => void;
  private readonly firecrawlUrl: string;
  private readonly enableFirecrawl: boolean;

  constructor(options: DeepResearchClientOptions = {}) {
    this.cdpUrl = options.cdpUrl ?? process.env.CHROME_CDP_URL ?? "http://127.0.0.1:9222";
    this.maxResearchTimeMs = options.maxResearchTimeMs ?? 30 * 60 * 1000;
    this.pollIntervalMs = options.pollIntervalMs ?? 5000;
    this.autoConfirm = options.autoConfirm ?? true;
    this.log = options.onProgress ?? ((msg: string) => console.log(`[DeepResearch] ${msg}`));
    this.firecrawlUrl = options.firecrawlUrl ?? process.env.FIRECRAWL_URL ?? "http://localhost:3002";
    this.enableFirecrawl = options.enableFirecrawl ?? false;
  }

  // ── Browser connection via CDP ──

  private async getChromeWsUrl(): Promise<string> {
    for (let attempt = 0; attempt < 10; attempt++) {
      try {
        const resp = await fetch(`${this.cdpUrl}/json/version`);
        const data = (await resp.json()) as { webSocketDebuggerUrl?: string };
        if (data.webSocketDebuggerUrl) return data.webSocketDebuggerUrl;
      } catch {
        // Chrome not ready yet
      }
      await new Promise((r) => setTimeout(r, 500));
    }
    throw new Error(
      `Failed to connect to Chrome at ${this.cdpUrl}. ` +
        `Make sure Chrome is running with: /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222`,
    );
  }

  async init(): Promise<void> {
    if (this.initialized) return;

    this.log(`Connecting to Chrome at ${this.cdpUrl}...`);
    const wsUrl = await this.getChromeWsUrl();

    const connectedBrowser = await chromium.connectOverCDP(wsUrl);
    const contexts = connectedBrowser.contexts();
    this.context = contexts.length > 0 ? contexts[0] : await connectedBrowser.newContext();

    const pages = this.context.pages();
    const geminiPage = pages.find((p: Page) => p.url().includes("gemini.google.com"));
    if (geminiPage) {
      this.log("Found existing Gemini page");
      this.page = geminiPage;
    } else {
      this.page = await this.context.newPage();
      await this.page.goto("https://gemini.google.com/app", { waitUntil: "domcontentloaded" });
    }

    this.initialized = true;
    this.log("Initialized");
  }

  // ── Selector helpers ──

  /** Try each selector in the fallback chain, return the first visible match */
  private async findElement(
    selectorGroup: readonly string[],
    options?: { timeout?: number; label?: string },
  ) {
    const timeout = options?.timeout ?? 5000;
    const label = options?.label ?? "element";

    for (const selector of selectorGroup) {
      try {
        const el = this.page!.locator(selector).first();
        await el.waitFor({ state: "visible", timeout: Math.min(timeout, 2000) });
        this.log(`Found ${label} via: ${selector}`);
        return el;
      } catch {
        // Try next selector
      }
    }
    return null;
  }

  // ── Deep Research flow ──

  async research(query: string): Promise<DeepResearchResult> {
    if (!this.page) throw new Error("Client not initialized — call init() first");

    const startTime = Date.now();

    try {
      // Step 1: Navigate to Gemini — skip if already on the page to avoid Angular re-init delay.
      // Navigating to the same URL triggers a full reload; Angular components (incl. Tools button)
      // may take 8+ seconds to re-appear, causing findElement to fail.
      const currentUrl = this.page.url();
      if (!currentUrl.includes("gemini.google.com")) {
        this.log("Navigating to Gemini...");
        await this.page.goto("https://gemini.google.com/app", {
          waitUntil: "domcontentloaded",
          timeout: 30000,
        });
        await new Promise((r) => setTimeout(r, 5000)); // longer wait for fresh page
      } else {
        this.log("Already on Gemini — skipping navigation");
        await new Promise((r) => setTimeout(r, 1000)); // brief settle
      }

      // Step 2: Activate Deep Research mode via Tools button
      this.log("Activating Deep Research mode...");

      const alreadyActive = await this.findElement(SELECTORS.DEEP_RESEARCH_ACTIVE, {
        timeout: 2000,
        label: "Deep Research active chip",
      });

      if (!alreadyActive) {
        const toolsBtn = await this.findElement(SELECTORS.TOOLS_BUTTON, {
          timeout: 10000,
          label: "Tools button",
        });
        if (!toolsBtn) {
          throw new Error(
            "Could not find Tools button. Selectors tried:\n" +
              SELECTORS.TOOLS_BUTTON.join("\n"),
          );
        }
        await toolsBtn.click();
        this.log("Clicked Tools button, waiting for drawer...");
        await new Promise((r) => setTimeout(r, 1500));

        const deepResearchBtn = await this.findElement(SELECTORS.DEEP_RESEARCH_TRIGGER, {
          timeout: 5000,
          label: "Deep Research item",
        });

        if (!deepResearchBtn) {
          // Fallback: text-based DOM search in overlay
          this.log("Selector-based search failed, trying text-based search in overlay...");
          const found = await this.page!.evaluate(() => {
            const items = document.querySelectorAll("toolbox-drawer-item button");
            for (const item of items) {
              if ((item.textContent ?? "").trim() === "Deep research") {
                (item as HTMLElement).click();
                return true;
              }
            }
            return false;
          });
          if (!found) {
            throw new Error(
              "Could not find Deep Research in Tools drawer.\n" +
                "Update SELECTORS.DEEP_RESEARCH_TRIGGER in selectors.ts",
            );
          }
          this.log("Found Deep Research via text-based search");
        } else {
          await deepResearchBtn.click();
          this.log("Clicked Deep Research item");
        }
        await new Promise((r) => setTimeout(r, 1500));

        const activeCheck = await this.findElement(SELECTORS.DEEP_RESEARCH_ACTIVE, {
          timeout: 5000,
          label: "Deep Research active verification",
        });
        if (!activeCheck) {
          this.log("Warning: Could not verify Deep Research mode activation");
        } else {
          this.log("Deep Research mode confirmed active");
        }
      } else {
        this.log("Deep Research mode already active");
      }

      // Step 3: Type query into input
      this.log("Typing query...");
      const input = await this.findElement(SELECTORS.INPUT, { timeout: 10000, label: "input" });
      if (!input) {
        throw new Error(
          "Could not find input element. Selectors tried:\n" + SELECTORS.INPUT.join("\n"),
        );
      }
      await input.click();
      await input.fill("");
      await this.page.keyboard.type(query, { delay: 30 });
      await new Promise((r) => setTimeout(r, 1000));

      // Step 4: Click send
      this.log("Clicking send...");
      const sendBtn = await this.findElement(SELECTORS.SEND, { timeout: 5000, label: "send" });
      if (sendBtn) {
        const isDisabled = await sendBtn.isDisabled();
        if (!isDisabled) {
          await sendBtn.click();
          this.log("Clicked send button");
        } else {
          this.log("Send button is disabled — trying Enter key");
          await this.page.keyboard.press("Enter");
        }
      } else {
        this.log("Send button not found — trying Enter key");
        await this.page.keyboard.press("Enter");
      }

      // Step 5: Wait for research plan
      this.log("Waiting for research plan (up to 2 min)...");
      await new Promise((r) => setTimeout(r, 5000));

      const confirmBtn = await this.findElement(SELECTORS.CONFIRM_RESEARCH, {
        timeout: 120000,
        label: "confirm research button",
      });

      let planText = "";
      try {
        planText = await this.page.evaluate((selectors: readonly string[]) => {
          const parts: string[] = [];
          for (const sel of selectors) {
            const els = document.querySelectorAll(sel);
            for (const el of els) {
              const text = (el as HTMLElement).textContent?.trim() ?? "";
              if (text.length > 5) parts.push(text);
            }
          }
          return parts.join("\n");
        }, SELECTORS.RESEARCH_PLAN);
        if (planText) this.log(`Research plan found (${planText.length} chars)`);
      } catch {
        this.log("Could not extract research plan text");
      }

      // Step 6: Confirm/start research.
      // The button may be disabled while Gemini streams the plan, or may stay disabled if research
      // started automatically (Gemini sometimes skips confirmation). Poll for enabled, then click.
      if (this.autoConfirm) {
        if (confirmBtn) {
          this.log("Waiting for confirm button to become enabled (up to 60s)...");
          let buttonEnabled = false;
          for (let i = 0; i < 60; i++) {
            const disabled = await confirmBtn.isDisabled().catch(() => true);
            if (!disabled) { buttonEnabled = true; break; }
            await new Promise((r) => setTimeout(r, 1000));
          }
          if (buttonEnabled) {
            await confirmBtn.click();
            this.log("Confirmed research plan — research starting...");
          } else {
            // Button stayed disabled — research likely auto-started. Check for research steps.
            const hasSteps = await this.page!.evaluate(() =>
              document.querySelectorAll('[class*="research-step"]').length > 0
            ).catch(() => false);
            if (hasSteps) {
              this.log("Confirm button disabled but research steps detected — research auto-started");
            } else {
              this.log("Confirm button remained disabled — proceeding to poll anyway");
            }
          }
        } else {
          this.log("No confirm button found — research may have started automatically");
        }
      } else {
        this.log("Auto-confirm disabled — waiting for manual confirmation...");
      }

      // Step 7: Poll for completion
      this.log(
        `Polling for completion (max ${Math.round(this.maxResearchTimeMs / 60000)} min)...`,
      );
      const report = await this.pollForCompletion();

      const durationMs = Date.now() - startTime;
      this.log(`Research completed in ${Math.round(durationMs / 1000)}s (${report.length} chars)`);

      const result: DeepResearchResult = {
        report,
        plan: planText || undefined,
        completed: true,
        durationMs,
      };

      // Step 8: Extract share link and scrape via Firecrawl
      if (this.enableFirecrawl) {
        const shareLink = await this.extractShareLink();
        if (shareLink) {
          result.shareLink = shareLink;
          const firecrawlMd = await this.scrapeWithFirecrawl(shareLink);
          if (firecrawlMd) {
            result.firecrawlMarkdown = firecrawlMd;
            this.log(`Firecrawl scraped ${firecrawlMd.length} chars from share link`);
          }
        }
      }

      return result;
    } catch (err) {
      const durationMs = Date.now() - startTime;
      const errorMessage = err instanceof Error ? err.message : String(err);
      this.log(`Research failed after ${Math.round(durationMs / 1000)}s: ${errorMessage}`);
      return { report: "", completed: false, durationMs, error: errorMessage };
    }
  }

  private async pollForCompletion(): Promise<string> {
    let lastTextLen = 0;
    let stableCount = 0;
    const stableThreshold = 3;

    for (let elapsed = 0; elapsed < this.maxResearchTimeMs; elapsed += this.pollIntervalMs) {
      await new Promise((r) => setTimeout(r, this.pollIntervalMs));

      const micVisible = await this.findElement(SELECTORS.MIC_BUTTON, {
        timeout: 1000,
        label: "mic",
      });

      const reportText = await this.extractReportText();
      const textLen = reportText?.length ?? 0;

      if (textLen > 500) {
        if (textLen === lastTextLen) {
          stableCount++;
        } else {
          lastTextLen = textLen;
          stableCount = 0;
        }
      }

      // Completion: mic visible + report text > 500 chars + stable for 2+ polls
      if (micVisible && textLen > 500 && stableCount >= 2) {
        this.log(`Report complete: ${textLen} chars, stable for ${stableCount} polls`);
        return reportText!;
      }

      if (elapsed % 30000 === 0) {
        const elapsedMin = Math.round(elapsed / 60000);
        const status = micVisible ? "mic-visible" : "researching";
        this.log(
          `[${elapsedMin}min] ${status}, text: ${textLen} chars, stable: ${stableCount}/${stableThreshold}`,
        );
      }
    }

    // Timeout fallback
    const finalText = await this.extractReportText();
    if (finalText && finalText.length > 500) {
      this.log("Timeout reached but have report — returning it");
      return finalText;
    }
    throw new Error(
      `Research timed out after ${Math.round(this.maxResearchTimeMs / 60000)} minutes with no report text`,
    );
  }

  private async extractReportText(): Promise<string | null> {
    if (!this.page) return null;

    return this.page.evaluate((selectors: readonly string[]) => {
      // Strategy: find the LONGEST matching element (the report is always the largest)
      let longestText = "";

      for (const selector of selectors) {
        try {
          const els = document.querySelectorAll(selector);
          for (const el of els) {
            // Inline clean: strip zero-width chars, trim
            const text = ((el as HTMLElement).innerText ?? "")
              .replace(/[\u200B-\u200D\uFEFF]/g, "")
              .trim();
            if (text.length > longestText.length) {
              longestText = text;
            }
          }
        } catch {
          // Selector might not be valid for querySelectorAll
        }
      }

      return longestText.length > 200 ? longestText : null;
    }, SELECTORS.REPORT);
  }

  // ── Share link extraction ──

  async extractShareLink(): Promise<string | null> {
    if (!this.page) return null;

    this.log("Extracting share link...");
    const shareBtn = await this.findElement(SELECTORS.SHARE_BUTTON, {
      timeout: 5000,
      label: "share button",
    });
    if (!shareBtn) {
      this.log("No share button found");
      return null;
    }
    await shareBtn.click();

    for (let i = 0; i < 20; i++) {
      await new Promise((r) => setTimeout(r, 1000));
      const link = await this.page.evaluate(() => {
        const dialog = document.querySelector("create-social-media-dialog");
        if (!dialog) return null;
        const text = (dialog.textContent ?? "").trim();
        const match = text.match(/(https?:\/\/)?gemini\.google\.com\/share\/[a-z0-9]+/i);
        return match ? match[0] : null;
      });
      if (link) {
        const fullLink = link.startsWith("http") ? link : `https://${link}`;
        this.log(`Share link: ${fullLink}`);
        await this.page.keyboard.press("Escape");
        return fullLink;
      }
    }

    this.log("Timed out waiting for share link");
    await this.page.keyboard.press("Escape");
    return null;
  }

  async scrapeWithFirecrawl(shareUrl: string): Promise<string | null> {
    this.log(`Scraping ${shareUrl} via Firecrawl...`);
    try {
      const resp = await fetch(`${this.firecrawlUrl}/v1/scrape`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          url: shareUrl,
          formats: ["markdown"],
          waitFor: 10000,
        }),
      });
      if (!resp.ok) {
        this.log(`Firecrawl HTTP ${resp.status}`);
        return null;
      }
      const data = (await resp.json()) as { success: boolean; data?: { markdown?: string } };
      if (!data.success || !data.data?.markdown) {
        this.log("Firecrawl returned no markdown");
        return null;
      }
      return data.data.markdown;
    } catch (err) {
      this.log(`Firecrawl error: ${err instanceof Error ? err.message : String(err)}`);
      return null;
    }
  }

  async close(): Promise<void> {
    this.page = null;
    this.context = null;
    this.initialized = false;
  }
}
