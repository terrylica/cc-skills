#!/usr/bin/env bun
/**
 * download-album.ts — download the ORIGINAL files from a public Amazon Photos
 * shared album (a `https://www.amazon.ca/photos/share/<shareId>` link), using
 * Amazon Drive's own JSON API. No login required for a public share.
 *
 * It mirrors the web app's own calls, gently (one download at a time):
 *   1. GET /drive/v1/shares/<shareId>            -> root SHARED_COLLECTION node id
 *   2. GET /drive/v1/nodes/<root>/children       -> the album FOLDER node id
 *   3. GET /drive/v1/nodes/<album>/children?...  -> list image (and/or video) nodes
 *   4. per node: GET /drive/v1/nodes/<id>/contentRedirection?download=true
 *      -> original bytes, written under its real filename, size-verified.
 *
 * Requirements: bun, `playwright-core`, and Google Chrome installed.
 *   bun add playwright-core      # in the dir you run this from
 *
 * Env:
 *   ALBUM_URL            the share URL (required)
 *   ALBUM_OUT            output dir (default: ./album-originals)
 *   ALBUM_INCLUDE        "image" (default) | "image,video" | "all"
 *   ALBUM_PROFILE_DIR    Chrome profile dir (default: ~/.cache/amazon-album/chrome)
 *   ALBUM_CHROME_CHANNEL Chrome channel (default: "chrome")
 *   ALBUM_PAUSE_MS       delay between downloads (default: 800)
 *
 * Note: this drives an undocumented Amazon Drive API. It works today; if Amazon
 * changes the share endpoints it may need updating. Re-discover the calls by
 * loading the album in a headed browser and watching the /drive/v1/ requests.
 */
import { mkdir, writeFile } from "node:fs/promises";
import { chromium } from "playwright-core";

const HOME = process.env.HOME ?? "";
const SHARE_URL = process.env.ALBUM_URL ?? "";
if (!SHARE_URL.includes("/share/")) {
  console.error("ALBUM_URL must be a https://www.amazon.*/photos/share/<id> link");
  process.exit(2);
}
const SHARE_ID = SHARE_URL.split("/share/")[1]?.split(/[?#]/)[0] ?? "";
const ORIGIN = new URL(SHARE_URL).origin; // e.g. https://www.amazon.ca
const OUT_DIR = process.env.ALBUM_OUT ?? "./album-originals";
const INCLUDE = (process.env.ALBUM_INCLUDE ?? "image").toLowerCase();
const PROFILE_DIR = process.env.ALBUM_PROFILE_DIR ?? `${HOME}/.cache/amazon-album/chrome`;
const CHANNEL = process.env.ALBUM_CHROME_CHANNEL ?? "chrome";
const PAUSE_MS = Number(process.env.ALBUM_PAUSE_MS ?? 800);

const log = (m: string) => process.stderr.write(`[album] ${m}\n`);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const wanted = (ct: string) =>
  INCLUDE === "all" || INCLUDE.split(",").some((k) => ct.startsWith(k));

const ctx = await chromium.launchPersistentContext(PROFILE_DIR, {
  channel: CHANNEL,
  headless: true,
  locale: "en-CA",
  viewport: { width: 1280, height: 900 },
});
const page = ctx.pages()[0] ?? (await ctx.newPage());

// Load the album once so the context receives whatever cookies the share sets.
await page.goto(SHARE_URL, { waitUntil: "networkidle", timeout: 60_000 });
await page.waitForTimeout(3000);

// JSON calls run IN-PAGE so they carry identical auth/headers as the web app.
async function api(path: string): Promise<any> {
  const { status, body } = await page.evaluate(async (u) => {
    const r = await fetch(u, { headers: { Accept: "application/json" }, credentials: "include" });
    return { status: r.status, body: await r.text() };
  }, `${ORIGIN}${path}`);
  if (status !== 200) throw new Error(`API ${status} for ${path}: ${body.slice(0, 200)}`);
  return JSON.parse(body);
}

const common = `shareId=${SHARE_ID}&resourceVersion=V2&ContentType=JSON`;
log(`shareId=${SHARE_ID} origin=${ORIGIN}`);

const rootId = (await api(`/drive/v1/shares/${SHARE_ID}?${common}`)).nodeInfo.id;
const albumId = (
  await api(`/drive/v1/nodes/${rootId}/children?asset=ALL&limit=1&searchOnFamily=true&tempLink=true&${common}&offset=0`)
).data[0].id;
log(`root=${rootId} album=${albumId}`);

const filters = encodeURIComponent(
  "kind:(FILE* OR FOLDER*) AND contentProperties.contentType:(image* OR video*) AND status:(AVAILABLE*)",
);
const all = (
  await api(
    `/drive/v1/nodes/${albumId}/children?asset=ALL&filters=${filters}&limit=200&searchOnFamily=true&tempLink=true&${common}&offset=0`,
  )
).data as any[];
const items = all.filter((n) => wanted(String(n?.contentProperties?.contentType ?? "")));
log(`total=${all.length} selected=${items.length} (include=${INCLUDE})`);

await mkdir(OUT_DIR, { recursive: true });
const manifest: any[] = [];
let ok = 0;
let i = 0;
for (const n of items) {
  i++;
  const name: string = n.name ?? `${n.id}.bin`;
  const size = n?.contentProperties?.size ?? 0;
  try {
    const res = await ctx.request.get(
      `${ORIGIN}/drive/v1/nodes/${n.id}/contentRedirection?download=true&${common}`,
      { timeout: 60_000 },
    );
    const buf = Buffer.from(await res.body());
    await writeFile(`${OUT_DIR}/${name}`, buf);
    const good = size === 0 || Math.abs(buf.length - size) < size * 0.02;
    log(`[${i}/${items.length}] ${name} ${buf.length}B ${good ? "ok" : `WARN expected ${size}`}`);
    manifest.push({ id: n.id, name, type: n.contentProperties?.contentType, bytes: buf.length, expected: size });
    if (good) ok++;
  } catch (e) {
    log(`[${i}/${items.length}] ${name} FAILED ${e}`);
  }
  await sleep(PAUSE_MS);
}

await writeFile(
  `${OUT_DIR}/manifest.json`,
  JSON.stringify({ shareId: SHARE_ID, albumId, selected: items.length, verified: ok, files: manifest }, null, 2),
);
log(`done: ${ok}/${items.length} verified -> ${OUT_DIR}`);
await ctx.close();
