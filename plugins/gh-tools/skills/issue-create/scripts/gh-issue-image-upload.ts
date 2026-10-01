#!/usr/bin/env bun
/**
 * Upload images to GitHub Issues via Playwright browser automation.
 *
 * GitHub has no API for image uploads — the web UI uses an internal S3 policy
 * flow. This script automates the browser's native file-attachment flow to get
 * permanent `user-attachments` CDN URLs.
 *
 * Auth: a persistent Chromium profile (default ~/.local/share/gh-issue-image-upload/profile; override with
 * GH_ISSUE_IMAGE_PROFILE). Rung 2 of the chrome-profiles plugin's ladder: Playwright's own Chromium, signed in once.
 * The profile holds a GitHub session cookie: treat it as sensitive.
 * First run: Log into GitHub once (Google SSO, passkey, password — anything).
 * Subsequent runs: Already authenticated (cookies persist in profile).
 *
 * Usage:
 *   bun "$(cc-plugin-root gh-tools)/skills/issue-create/scripts/gh-issue-image-upload.ts" <issue-url> <image-path> [image-path...]
 *
 * To reset auth: move the profile folder to the Trash.
 */

import { chromium, type Page, type BrowserContext } from "playwright-core";
import { existsSync } from "node:fs";
import { resolve, basename } from "node:path";

const PROFILE_DIR =
  process.env.GH_ISSUE_IMAGE_PROFILE ?? resolve(process.env.HOME!, ".local/share/gh-issue-image-upload/profile");

interface UploadResult {
  file: string;
  imgTag: string | null;
  cdnUrl: string | null;
  error?: string;
}

async function uploadImageToIssue(
  page: Page,
  imagePath: string
): Promise<UploadResult> {
  const absPath = resolve(imagePath);
  const filename = basename(absPath);

  if (!existsSync(absPath)) {
    return { file: filename, imgTag: null, cdnUrl: null, error: `File not found: ${absPath}` };
  }

  console.error(`[upload] Uploading ${filename}...`);

  // GitHub's new React comment composer uses a textarea with this placeholder
  const textarea = page.locator('textarea[placeholder="Use Markdown to format your comment"]');
  if ((await textarea.count()) === 0) {
    return { file: filename, imgTag: null, cdnUrl: null, error: "Comment textarea not found" };
  }

  // Click textarea to focus, then get current content
  await textarea.click();
  await page.waitForTimeout(300);
  const beforeText = await textarea.inputValue();

  // Click "Paste, drop, or click to add files" → intercept the file chooser
  const addFilesArea = page.getByText("Paste, drop, or click to add files");
  if ((await addFilesArea.count()) === 0) {
    return { file: filename, imgTag: null, cdnUrl: null, error: "File upload area not found" };
  }

  const [fileChooser] = await Promise.all([
    page.waitForEvent("filechooser", { timeout: 10_000 }).catch(() => null),
    addFilesArea.click(),
  ]);

  if (!fileChooser) {
    return { file: filename, imgTag: null, cdnUrl: null, error: "File chooser did not open" };
  }

  await fileChooser.setFiles(absPath);

  // Wait for GitHub to upload and insert <img> tag into textarea
  // Pattern: <img ... src="https://github.com/user-attachments/assets/UUID" />
  for (let i = 0; i < 30; i++) {
    await page.waitForTimeout(1000);
    const currentText = await textarea.inputValue();
    const newContent = currentText.slice(beforeText.length).trim();

    const match = newContent.match(
      /<img[^>]+src="(https:\/\/github\.com\/user-attachments\/assets\/[^"]+)"[^>]*\/>/
    );
    if (match) {
      const imgTag = match[0];
      const cdnUrl = match[1];
      console.error(`[upload] ✓ ${filename} → ${cdnUrl}`);

      // Clear textarea for next upload
      await textarea.fill("");
      return { file: filename, imgTag, cdnUrl };
    }

    // Also check for markdown format (older GitHub UI)
    const mdMatch = newContent.match(
      /!\[([^\]]*)\]\((https:\/\/github\.com\/user-attachments\/assets\/[^)]+)\)/
    );
    if (mdMatch) {
      const imgTag = mdMatch[0];
      const cdnUrl = mdMatch[2];
      console.error(`[upload] ✓ ${filename} → ${cdnUrl}`);
      await textarea.fill("");
      return { file: filename, imgTag, cdnUrl };
    }

    if (newContent.includes("Uploading")) continue;
  }

  return { file: filename, imgTag: null, cdnUrl: null, error: "Upload timed out (30s)" };
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length < 2) {
    console.error("Usage: bun gh-issue-image-upload.ts <issue-url> <image>...");
    console.error("");
    console.error("First run: Log into GitHub once (any method). Cookies persist.");
    console.error("Subsequent runs: Fully automatic.");
    console.error(`Reset auth: move ${PROFILE_DIR} to the Trash`);
    console.error("");
    console.error("Examples:");
    console.error("  bun gh-issue-image-upload.ts https://github.com/owner/repo/issues/1 ./screenshot.png");
    console.error("  bun gh-issue-image-upload.ts https://github.com/owner/repo/issues/1 ./img/*.png");
    process.exit(1);
  }

  const [issueUrl, ...imagePaths] = args;

  // Launch Chromium with persistent profile
  console.error(`[browser] Launching (profile: ${PROFILE_DIR})`);
  const context: BrowserContext = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless: false,
  });

  const page = context.pages()[0] || await context.newPage();

  // Check login status
  console.error("[auth] Checking login status...");
  await page.goto("https://github.com", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2000);

  const avatar = await page.locator("img.avatar, .AppHeader-user").first().count();
  if (avatar > 0) {
    console.error("[auth] Already logged in.");
  } else {
    console.error("[auth] Not logged in — opening GitHub login page...");
    console.error("[auth] Please log in (any method: Google SSO, passkey, password).");
    console.error("[auth] This is ONE-TIME — cookies persist for future runs.");
    console.error("[auth] Waiting up to 5 minutes...");
    console.error("");

    await page.goto("https://github.com/login", { waitUntil: "domcontentloaded" });

    const deadline = Date.now() + 300_000;
    let loggedIn = false;
    while (Date.now() < deadline) {
      await page.waitForTimeout(2_000);
      try {
        const url = page.url();
        if (url.startsWith("https://github.com") &&
            !url.includes("/login") && !url.includes("/session")) {
          const av = await page.locator("img.avatar, .AppHeader-user").first().count();
          if (av > 0) { loggedIn = true; break; }
        }
      } catch { /* page navigating */ }
    }

    if (!loggedIn) {
      console.error("[auth] Login timed out. Exiting.");
      await context.close();
      process.exit(1);
    }
    console.error("[auth] Login successful!");
  }

  // Navigate to issue page
  console.error(`[nav] Opening ${issueUrl}`);
  try {
    await page.goto(issueUrl, { waitUntil: "domcontentloaded", timeout: 30_000 });
  } catch {
    await page.waitForTimeout(3000);
  }
  await page.waitForTimeout(2000);

  // Scroll to bottom to ensure comment area is loaded
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(2000);

  // Verify comment textarea exists
  const commentBox = page.locator('textarea[placeholder="Use Markdown to format your comment"]');
  if ((await commentBox.count()) === 0) {
    console.error("[auth] Comment textarea not found. No write access?");
    await context.close();
    process.exit(1);
  }

  console.error("[auth] Authenticated — comment box found.");
  console.error(`[upload] ${imagePaths.length} image(s) to upload`);

  // Upload each image
  const results: UploadResult[] = [];
  for (const imgPath of imagePaths) {
    const result = await uploadImageToIssue(page, imgPath);
    results.push(result);
  }

  await context.close();

  // JSON to stdout
  console.log(JSON.stringify(results, null, 2));

  // Summary to stderr
  const ok = results.filter((r) => r.cdnUrl).length;
  const fail = results.filter((r) => !r.cdnUrl).length;
  console.error(`\n[done] ${ok} uploaded, ${fail} failed`);
}

main().catch((err) => {
  console.error("[fatal]", err);
  process.exit(1);
});
