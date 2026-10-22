// make-fixtures.mjs — regenerate the synthetic Chrome "Local Storage/leveldb" fixtures that
// extension-token-from-profile.test.ts reads. Written by REAL LevelDB (classic-level, which bundles google/leveldb
// with Snappy), so the reader is tested against the on-disk format LevelDB actually produces, not against a writer
// of our own. Every token below is synthetic; no fixture holds anything from a real profile.
//
//   mkdir -p /tmp/ldbgen && (cd /tmp/ldbgen && npm init -y && npm install classic-level@3)
//   CLASSIC_LEVEL_FROM=/tmp/ldbgen node make-fixtures.mjs        # rewrites the case directories beside this file
//
// Keys and values use Chrome's localStorage encoding: "_" + origin + "\0" + (0x01 Latin-1 | 0x00 UTF-16LE) + text.
import { createRequire } from "node:module";
import { existsSync, readdirSync, readFileSync, rmSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const from = process.env.CLASSIC_LEVEL_FROM;
if (!from) throw new Error("set CLASSIC_LEVEL_FROM to a directory where classic-level is installed");
const { ClassicLevel } = createRequire(join(from, "package.json"))("classic-level");

const HERE = dirname(fileURLToPath(import.meta.url));
const EXT = "chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm";
export const TOKENS = {
  log: "fixtureLogTokenV2-AAAAAAAAAAAAAAAAAAAAAAAA",
  logOld: "fixtureLogTokenV1-BBBBBBBBBBBBBBBBBBBBBBBB",
  // Repetitive on purpose: Snappy encodes the repeats as copies, so the token's text is NOT in the .ldb bytes and
  // only a reader that decompresses can find it.
  table: "fixtureTableTok_".repeat(4),
  utf16: "fixtureUtf16Token-CCCCCCCCCCCCCCCCCCCCCCC",
  decoy: "decoyOtherOriginToken-DDDDDDDDDDDDDDDDDDDD",
};

const latin1 = (s) => Buffer.concat([Buffer.from([1]), Buffer.from(s, "latin1")]);
const utf16 = (s) => Buffer.concat([Buffer.from([0]), Buffer.from(s, "utf16le")]);
const key = (origin, k) => Buffer.concat([Buffer.from(`_${origin}\0`, "latin1"), latin1(k)]);

async function make(name, steps) {
  const dir = join(HERE, name, "Local Storage", "leveldb");
  rmSync(join(HERE, name), { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  for (const step of steps) {
    const db = new ClassicLevel(dir, { keyEncoding: "buffer", valueEncoding: "buffer" });
    await db.open();
    await step(db);
    await db.close(); // the next open converts this log into a level-0 .ldb table
  }
  rmSync(join(dir, "LOG.old"), { force: true });
  rmSync(join(dir, "LOG"), { force: true }); // LevelDB's text info log names the host path; not needed
  return dir;
}

const base = async (db) => {
  await db.put(Buffer.from("VERSION"), Buffer.from("1"));
  await db.put(Buffer.from(`META:${EXT}`), Buffer.from([0x08, 0x01]));
  await db.put(key("https://example.com", "auth-token"), latin1(TOKENS.decoy));
  await db.put(key(EXT, "other-setting"), latin1("x"));
};
const padding = async (db) => {
  for (let i = 0; i < 200; i++) await db.put(key(EXT, `pad-${i}`), latin1("padding ".repeat(16)));
};
const reopenOnly = async () => {};

await make("log-only", [async (db) => {
  await base(db);
  await db.put(key(EXT, "auth-token"), latin1(TOKENS.logOld));
  await db.put(key(EXT, "auth-token"), latin1(TOKENS.log));
}]);
const tableDir = await make("table", [async (db) => { await base(db); await padding(db); await db.put(key(EXT, "auth-token"), latin1(TOKENS.table)); }, reopenOnly]);
await make("table-then-deleted", [async (db) => { await base(db); await padding(db); await db.put(key(EXT, "auth-token"), latin1(TOKENS.table)); }, reopenOnly,
  async (db) => { await db.del(key(EXT, "auth-token")); }]);
await make("utf16", [async (db) => { await base(db); await db.put(key(EXT, "auth-token"), utf16(TOKENS.utf16)); }]);
await make("no-token", [base]);
await make("malformed", [async (db) => { await base(db); await db.put(key(EXT, "auth-token"), latin1("not a token!")); }]);

// Prove the table case exercises Snappy: a table exists and the token's text is not in any file of that case.
const files = readdirSync(tableDir);
if (!files.some((f) => f.endsWith(".ldb"))) throw new Error("table case produced no .ldb");
for (const f of files) if (readFileSync(join(tableDir, f)).includes(TOKENS.table)) throw new Error(`token text visible in ${f}`);
if (!existsSync(join(tableDir, "CURRENT"))) throw new Error("no CURRENT");
console.log("fixtures written:", readdirSync(HERE).filter((d) => !d.endsWith(".mjs")).join(", "));
