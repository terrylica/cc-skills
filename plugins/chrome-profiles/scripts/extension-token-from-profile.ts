#!/usr/bin/env bun
// extension-token-from-profile.ts — read the Playwright Extension's auth token out of a Chrome profile, so
// `chrome-profile.sh setup` needs no copy and paste.
//
//   bun --no-env-file --no-install --config=/dev/null extension-token-from-profile.ts <profile-dir> \
//       [--ext-id <id>] [--emit-fd <n>]
//
//   <profile-dir>   the profile folder itself, e.g. ".../Google/Chrome/Profile 7" (chrome-profile.sh resolves it
//                   from the account email); the reader looks in its "Local Storage/leveldb".
//   --ext-id <id>   the extension whose origin to read (default: Microsoft's mmlmfjhmonkocbjadbfplnigmagldckm).
//   --emit-fd <n>   write the bare token to file descriptor n (n >= 3, never a terminal). Without it the token is
//                   read, checked and discarded: a dry run that proves it is there.
//
// STDOUT carries one JSON status line and NEVER the token: {"status":"found","records":2,"length":43,...}. The
// token leaves this process only through --emit-fd, which refuses fds 0-2 and any terminal, so neither a log, a
// transcript nor a terminal receives it by accident. STDERR carries reasons and file names, never values.
//
// Exit codes: 0 found · 1 no live token record (the status page has not created one yet, or it was removed) ·
//             2 usage · 3 no readable Local Storage in that profile · 4 a record exists but is not token-shaped.
//
// WHERE THE TOKEN LIVES. The extension keeps it in its own origin's localStorage under "auth-token"
// (lib/ui/authToken.js) and creates it the first time its status page opens. Chrome stores localStorage in a
// LevelDB: user keys are "_" + origin + "\0" + key and values carry a one-byte encoding prefix (0 = UTF-16LE,
// 1 = Latin-1); recent writes sit in the write-ahead *.log, older ones in *.ldb tables whose blocks are usually
// Snappy-compressed, so a text search of the files finds the record only sometimes.
//
// WHY A HAND-WRITTEN READER, AND WHY TYPESCRIPT. The 2026-10-12 draft was Python on CCL Group's
// ccl_chromium_reader, fetched unpinned from GitHub at every run (`uv run --with git+https://...`): third-party
// code pulled fresh off the network and run against the profile directory that also holds the browser's cookies.
// The repo's default language is Bun/TypeScript (python-allowlist.toml), and the subset needed here is small and
// frozen: the LevelDB log and table layouts (google/leveldb doc/log_format.md, doc/table_format.md) and raw Snappy
// (google/snappy format_description.txt). It reads and never writes; only node: built-ins are imported.
//
// CHROME MAY BE RUNNING. Chrome holds the database's LOCK file and keeps appending to the log, so this never opens
// the live database: it copies every regular file except LOCK into a fresh private directory (0700, files 0600),
// reads the copy and deletes it on every exit path. A file that vanishes mid-copy (Chrome compacting) restarts the
// copy; a record torn by a concurrent write fails its CRC and is skipped, as LevelDB's own recovery does.
import {
  chmodSync, closeSync, copyFileSync, constants as fsc, fstatSync, lstatSync, mkdtempSync, readdirSync,
  readFileSync, rmSync, writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isatty } from "node:tty";

export const DEFAULT_EXT_ID = "mmlmfjhmonkocbjadbfplnigmagldckm";
export const TOKEN_KEY = "auth-token";
// What the extension generates (random bytes, base64 or base64url). Anything else is not stored as a token.
export const TOKEN_SHAPE = /^[A-Za-z0-9+/=_-]{16,512}$/;

// ── CRC-32C (Castagnoli), stored masked by LevelDB ───────────────────────────────────────────────────────────────
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0x82f63b78 : c >>> 1;
    t[i] = c >>> 0;
  }
  return t;
})();
export function crc32c(data: Uint8Array): number {
  let c = 0xffffffff;
  for (const b of data) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
const unmaskCrc = (m: number) => {
  const r = (m - 0xa282ead8) >>> 0;
  return ((r >>> 17) | (r << 15)) >>> 0;
};

// ── varints (at most 10 bytes) ───────────────────────────────────────────────────────────────────────────────────
function varint(buf: Uint8Array, pos: number): [number, number] {
  let result = 0;
  for (let i = 0; i < 10; i++) {
    if (pos >= buf.length) throw new Error("truncated varint");
    const b = buf[pos++];
    result += (b & 0x7f) * 2 ** (7 * i);
    if (!(b & 0x80)) return [result, pos];
  }
  throw new Error("varint too long");
}

// ── Snappy (raw block format) ────────────────────────────────────────────────────────────────────────────────────
export function snappyDecompress(src: Uint8Array): Uint8Array {
  const [len, start] = varint(src, 0);
  const out = new Uint8Array(len);
  let pos = start, o = 0;
  while (pos < src.length) {
    const tag = src[pos++];
    if ((tag & 3) === 0) { // literal
      let n = tag >>> 2;
      if (n >= 60) {
        const extra = n - 59;
        n = 0;
        for (let i = 0; i < extra; i++) n += src[pos++] * 2 ** (8 * i);
      }
      n += 1;
      if (pos + n > src.length || o + n > len) throw new Error("snappy literal overruns");
      out.set(src.subarray(pos, pos + n), o);
      pos += n; o += n;
      continue;
    }
    let n: number, off: number;
    if ((tag & 3) === 1) { n = ((tag >>> 2) & 7) + 4; off = ((tag >>> 5) << 8) | src[pos++]; }
    else if ((tag & 3) === 2) { n = (tag >>> 2) + 1; off = src[pos] | (src[pos + 1] << 8); pos += 2; }
    else { n = (tag >>> 2) + 1; off = (src[pos] | (src[pos + 1] << 8) | (src[pos + 2] << 16) | (src[pos + 3] << 24)) >>> 0; pos += 4; }
    if (off === 0 || off > o || o + n > len) throw new Error("snappy copy out of range");
    for (let i = 0; i < n; i++, o++) out[o] = out[o - off]; // overlapping copies are legal: byte by byte
  }
  if (o !== len) throw new Error("snappy length mismatch");
  return out;
}

// ── LevelDB records ──────────────────────────────────────────────────────────────────────────────────────────────
export type Rec = { key: Uint8Array; value: Uint8Array | null; seq: bigint }; // value null = deletion

// Write-ahead log: 32 KiB blocks of [crc32c:4][len:2][type:1][data], types FULL/FIRST/MIDDLE/LAST; each assembled
// record is a write batch [seq:8][count:4] then (type, key, value) entries with consecutive sequence numbers.
export function readLog(buf: Uint8Array, out: Rec[]): void {
  const BLOCK = 32768;
  let pos = 0;
  let frag: Uint8Array[] = [];
  while (pos + 7 <= buf.length) {
    const left = BLOCK - (pos % BLOCK);
    if (left < 7) { pos += left; continue; } // block trailer padding
    const dv = new DataView(buf.buffer, buf.byteOffset + pos, 7);
    const crc = dv.getUint32(0, true), len = dv.getUint16(4, true), type = buf[pos + 6];
    if (type === 0 && len === 0) { pos += left; continue; } // preallocated zeros
    if (pos + 7 + len > buf.length) break; // torn tail: Chrome was mid-write
    const data = buf.subarray(pos + 7, pos + 7 + len);
    pos += 7 + len;
    const body = new Uint8Array(1 + len); body[0] = type; body.set(data, 1);
    if (crc32c(body) !== unmaskCrc(crc)) { frag = []; continue; } // corrupt or torn: skip, as recovery does
    if (type === 1) { parseBatch(data, out); frag = []; }
    else if (type === 2) frag = [data];
    else if (type === 3) { if (frag.length) frag.push(data); }
    else if (type === 4) { if (frag.length) { frag.push(data); parseBatch(concat(frag), out); } frag = []; }
  }
}

function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

function parseBatch(b: Uint8Array, out: Rec[]): void {
  if (b.length < 12) return;
  const dv = new DataView(b.buffer, b.byteOffset, b.length);
  let seq = dv.getBigUint64(0, true);
  const count = dv.getUint32(8, true);
  let pos = 12;
  try {
    for (let i = 0; i < count; i++, seq++) {
      const t = b[pos++];
      let kl: number; [kl, pos] = varint(b, pos);
      if (pos + kl > b.length) throw new Error("key overruns batch");
      const key = b.slice(pos, pos + kl); pos += kl;
      if (t === 1) {
        let vl: number; [vl, pos] = varint(b, pos);
        if (pos + vl > b.length) throw new Error("value overruns batch");
        out.push({ key, value: b.slice(pos, pos + vl), seq }); pos += vl;
      } else out.push({ key, value: null, seq });
    }
  } catch { /* a malformed batch contributes what parsed before the fault (its CRC passed, so this is rare) */ }
}

// Table (*.ldb / *.sst): 48-byte footer → index block → data blocks; every block is followed by a 5-byte trailer
// [compression:1][crc:4] (0 = none, 1 = Snappy). Entries are prefix-compressed; internal keys end in an 8-byte
// little-endian (seq << 8 | type) tag.
export function readTable(buf: Uint8Array, out: Rec[]): void {
  if (buf.length < 48) throw new Error("shorter than a table footer");
  const foot = buf.subarray(buf.length - 48);
  const magic = new DataView(foot.buffer, foot.byteOffset + 40, 8).getBigUint64(0, true);
  if (magic !== 0xdb4775248b80fb57n) throw new Error("not a LevelDB table (bad magic)");
  let p = 0, off: number, size: number;
  [, p] = varint(foot, p); [, p] = varint(foot, p); // metaindex handle: unused
  [off, p] = varint(foot, p); [size, p] = varint(foot, p);
  for (const [, handle] of blockEntries(readBlock(buf, off, size))) {
    let hp = 0, bo: number, bs: number;
    [bo, hp] = varint(handle, hp); [bs, hp] = varint(handle, hp);
    for (const [ik, v] of blockEntries(readBlock(buf, bo, bs))) {
      if (ik.length < 8) continue;
      const tag = new DataView(ik.buffer, ik.byteOffset + ik.length - 8, 8).getBigUint64(0, true);
      out.push({ key: ik.slice(0, ik.length - 8), value: (tag & 0xffn) === 1n ? v.slice() : null, seq: tag >> 8n });
    }
  }
}

function readBlock(buf: Uint8Array, off: number, size: number): Uint8Array {
  if (off + size + 5 > buf.length) throw new Error("block outside file");
  const raw = buf.subarray(off, off + size), type = buf[off + size];
  const crc = new DataView(buf.buffer, buf.byteOffset + off + size + 1, 4).getUint32(0, true);
  if (crc32c(buf.subarray(off, off + size + 1)) !== unmaskCrc(crc)) throw new Error("block crc mismatch");
  if (type === 0) return raw;
  if (type === 1) return snappyDecompress(raw);
  throw new Error(`unsupported block compression ${type}`);
}

function* blockEntries(block: Uint8Array): Generator<[Uint8Array, Uint8Array]> {
  if (block.length < 4) return;
  const dv = new DataView(block.buffer, block.byteOffset, block.length);
  const end = block.length - 4 - 4 * dv.getUint32(block.length - 4, true);
  let pos = 0, key = new Uint8Array(0);
  while (pos < end) {
    let shared: number, unshared: number, vlen: number;
    [shared, pos] = varint(block, pos); [unshared, pos] = varint(block, pos); [vlen, pos] = varint(block, pos);
    if (shared > key.length || pos + unshared + vlen > end) throw new Error("block entry overruns");
    const k = new Uint8Array(shared + unshared);
    k.set(key.subarray(0, shared)); k.set(block.subarray(pos, pos + unshared), shared);
    pos += unshared;
    key = k;
    yield [k, block.subarray(pos, pos + vlen)];
    pos += vlen;
  }
}

// ── Chrome localStorage layer ────────────────────────────────────────────────────────────────────────────────────
export function decodeChromeString(b: Uint8Array): string | null {
  if (b.length === 0) return null;
  if (b[0] === 1) return Buffer.from(b.subarray(1)).toString("latin1");
  if (b[0] === 0 && (b.length - 1) % 2 === 0) return Buffer.from(b.subarray(1)).toString("utf16le");
  return null;
}

export type Lookup = { status: "found"; token: string; records: number } | { status: "absent"; records: number };

// The newest record (highest sequence number) for <origin> / "auth-token" decides; a deletion means no token.
export function findToken(records: Rec[], extId: string): Lookup {
  const prefix = Buffer.from(`_chrome-extension://${extId}\0`, "latin1");
  const hits = records.filter((r) =>
    r.key.length > prefix.length && Buffer.from(r.key.subarray(0, prefix.length)).equals(prefix) &&
    decodeChromeString(r.key.subarray(prefix.length)) === TOKEN_KEY);
  const last = hits.toSorted((a, b) => (a.seq < b.seq ? -1 : a.seq > b.seq ? 1 : 0)).at(-1);
  const live = hits.length; // every auth-token record seen, deletions included: diagnostic only
  if (!last || last.value === null) return { status: "absent", records: live };
  const token = decodeChromeString(last.value);
  return token === null ? { status: "absent", records: live } : { status: "found", token, records: live };
}

export function readLevelDb(dir: string): Rec[] {
  const out: Rec[] = [];
  for (const name of readdirSync(dir).toSorted()) {
    const isLog = name.endsWith(".log"), isTable = name.endsWith(".ldb") || name.endsWith(".sst");
    if (!isLog && !isTable) continue;
    try {
      const buf = new Uint8Array(readFileSync(join(dir, name)));
      if (isLog) readLog(buf, out); else readTable(buf, out);
    } catch (e) {
      process.stderr.write(`skipped ${name}: ${(e as Error).message}\n`); // file name and reason only, never bytes
    }
  }
  return out;
}

// Copy the live database into a private directory: regular files only, LOCK excluded, symlinks never followed.
// Retries when Chrome deletes a file between listing and copying it.
export function snapshot(src: string, attempts = 3): string {
  for (let a = 1; a <= attempts; a++) {
    const dst = mkdtempSync(join(tmpdir(), "ext-token-"));
    chmodSync(dst, 0o700);
    try {
      for (const name of readdirSync(src)) {
        if (name === "LOCK") continue;
        if (!lstatSync(join(src, name)).isFile()) continue;
        copyFileSync(join(src, name), join(dst, name), fsc.COPYFILE_EXCL);
        chmodSync(join(dst, name), 0o600);
      }
      return dst;
    } catch (e) {
      rmSync(dst, { recursive: true, force: true });
      if ((e as NodeJS.ErrnoException).code !== "ENOENT" || a >= attempts) throw e;
    }
  }
  throw new Error("unreachable");
}

// ── CLI ──────────────────────────────────────────────────────────────────────────────────────────────────────────
const HELP = "usage: extension-token-from-profile.ts <profile-dir> [--ext-id <id>] [--emit-fd <n>=3+]\n";
const status = (o: Record<string, unknown>) => process.stdout.write(JSON.stringify(o) + "\n");
function usage(msg: string): number {
  process.stderr.write(`${msg}\n${HELP}`);
  return 2;
}

export function main(argv: string[]): number {
  let profile = "", extId = DEFAULT_EXT_ID, emitFd: number | null = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--ext-id") extId = argv[++i] ?? "";
    else if (a === "--emit-fd") emitFd = Number(argv[++i]);
    else if (a === "-h" || a === "--help") { process.stdout.write(HELP); return 0; }
    else if (!a.startsWith("-") && !profile) profile = a;
    else return usage(`unexpected argument: ${a}`);
  }
  if (!profile) return usage("a profile directory is required");
  if (!/^[a-p]{32}$/.test(extId)) return usage("--ext-id must be a 32-letter Chrome extension id");
  if (emitFd !== null) {
    if (!Number.isInteger(emitFd) || emitFd < 3) return usage("--emit-fd must be an integer >= 3 (never stdin, stdout or stderr)");
    try { fstatSync(emitFd); } catch { return usage(`--emit-fd ${emitFd} is not open`); }
    if (isatty(emitFd)) return usage(`--emit-fd ${emitFd} is a terminal; the token is written only to a pipe or file`);
  }

  const src = join(profile, "Local Storage", "leveldb");
  let copy: string;
  try {
    if (!lstatSync(src).isDirectory()) throw new Error("not a directory");
    copy = snapshot(src);
  } catch (e) {
    process.stderr.write(`no readable Local Storage at ${src}: ${(e as Error).message}\n`);
    status({ status: "no-local-storage" });
    return 3;
  }
  const cleanup = () => rmSync(copy, { recursive: true, force: true });
  const onSignal = (sig: NodeJS.Signals) => { cleanup(); process.exit(sig === "SIGINT" ? 130 : 143); };
  process.once("SIGINT", onSignal).once("SIGTERM", onSignal).once("SIGHUP", onSignal);
  let found: Lookup;
  try {
    found = findToken(readLevelDb(copy), extId);
  } finally {
    cleanup();
  }

  if (found.status === "absent") {
    process.stderr.write("no live auth-token record yet (open the extension's status page in this profile)\n");
    status({ status: "not-found", records: found.records });
    return 1;
  }
  if (!TOKEN_SHAPE.test(found.token)) {
    process.stderr.write(`the newest auth-token record is not token-shaped (length ${found.token.length}); not used\n`);
    status({ status: "malformed", records: found.records, length: found.token.length });
    return 4;
  }
  if (emitFd !== null) {
    writeSync(emitFd, found.token);
    closeSync(emitFd);
  }
  status({ status: "found", records: found.records, length: found.token.length, emitted: emitFd !== null });
  return 0;
}

if (import.meta.main) process.exit(main(process.argv.slice(2)));
