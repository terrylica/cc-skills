// extension-token-from-profile.test.ts — the token reader against synthetic LevelDB fixtures written by real
// LevelDB (fixtures/extension-token/make-fixtures.mjs). No real profile, no real token, no browser.
import { afterEach, describe, expect, test } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  appendFileSync, chmodSync, cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { crc32c, snappyDecompress, snapshot } from "./extension-token-from-profile.ts";

const HERE = import.meta.dir;
const READER = join(HERE, "extension-token-from-profile.ts");
const FIX = join(HERE, "fixtures", "extension-token");
// Mirrors TOKENS in make-fixtures.mjs.
const T = {
  log: "fixtureLogTokenV2-AAAAAAAAAAAAAAAAAAAAAAAA",
  logOld: "fixtureLogTokenV1-BBBBBBBBBBBBBBBBBBBBBBBB",
  table: "fixtureTableTok_".repeat(4),
  utf16: "fixtureUtf16Token-CCCCCCCCCCCCCCCCCCCCCCC",
  decoy: "decoyOtherOriginToken-DDDDDDDDDDDDDDDDDDDD",
};
const ALL = Object.values(T);

const scratch: string[] = [];
const tmp = (p: string) => { const d = mkdtempSync(join(tmpdir(), p)); scratch.push(d); return d; };
afterEach(() => { for (const d of scratch.splice(0)) { spawnSync("chmod", ["-R", "u+rwx", d]); rmSync(d, { recursive: true, force: true }); } });

// Run the CLI with fd 3, the only channel the token may use, pointed at a file in a private dir (Bun's spawnSync
// does not collect extra pipes).
function run(args: string[], env: Record<string, string> = {}) {
  const f = join(tmp("fd3-"), "fd3");
  const r = spawnSync("/usr/bin/env", ["bash", "-c", 'f="$1"; shift; exec "$@" 3>"$f"', "_", f,
    "bun", "--no-env-file", "--no-install", "--config=/dev/null", READER, ...args], {
    stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, ...env }, encoding: "utf8",
  });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr, fd3: existsSync(f) ? readFileSync(f, "utf8") : "" };
}
const noSecret = (r: { stdout: string; stderr: string }) => {
  for (const t of ALL) {
    expect(r.stdout).not.toContain(t);
    expect(r.stderr).not.toContain(t);
  }
};

describe("format primitives", () => {
  test("crc32c check value", () => expect(crc32c(new TextEncoder().encode("123456789"))).toBe(0xe3069283));
  test("snappy literal + overlapping copy", () => {
    // len 12 | literal "abc" (tag (3-1)<<2) | copy-1 len 9 off 3: tag ((9-4)<<2)|1, offset byte 3
    const s = snappyDecompress(new Uint8Array([12, 0x08, 97, 98, 99, (5 << 2) | 1, 3]));
    expect(new TextDecoder().decode(s)).toBe("abcabcabcabc");
  });
  test("snappy rejects a copy before the start", () => {
    expect(() => snappyDecompress(new Uint8Array([4, (0 << 2) | 1, 5]))).toThrow();
  });
});

describe("CLI against fixtures", () => {
  test("found in the write-ahead log: newest of two writes wins, other origin ignored", () => {
    const r = run([join(FIX, "log-only"), "--emit-fd", "3"]);
    expect(r.code).toBe(0);
    expect(r.fd3).toBe(T.log);
    expect(JSON.parse(r.stdout)).toEqual({ status: "found", records: 2, length: T.log.length, emitted: true });
    noSecret(r);
  });
  test("found in a Snappy-compressed table whose raw bytes do not contain the token", () => {
    const dir = join(FIX, "table", "Local Storage", "leveldb");
    const ldb = readdirSync(dir).filter((f) => f.endsWith(".ldb"));
    expect(ldb.length).toBeGreaterThan(0);
    for (const f of readdirSync(dir)) expect(readFileSync(join(dir, f)).includes(T.table)).toBe(false);
    const r = run([join(FIX, "table"), "--emit-fd", "3"]);
    expect(r.code).toBe(0);
    expect(r.fd3).toBe(T.table);
    noSecret(r);
  });
  test("UTF-16 encoded value", () => {
    const r = run([join(FIX, "utf16"), "--emit-fd", "3"]);
    expect([r.code, r.fd3]).toEqual([0, T.utf16]);
    noSecret(r);
  });
  test("not found: only another origin has an auth-token", () => {
    const r = run([join(FIX, "no-token"), "--emit-fd", "3"]);
    expect(r.code).toBe(1);
    expect(r.fd3).toBe("");
    expect(JSON.parse(r.stdout).status).toBe("not-found");
    noSecret(r);
  });
  test("not found: a deletion in the log overrides the value in the table", () => {
    const r = run([join(FIX, "table-then-deleted"), "--emit-fd", "3"]);
    expect([r.code, r.fd3]).toEqual([1, ""]);
    noSecret(r);
  });
  test("a value that is not token-shaped is refused, and not printed", () => {
    const r = run([join(FIX, "malformed"), "--emit-fd", "3"]);
    expect([r.code, r.fd3]).toEqual([4, ""]);
    expect(r.stdout + r.stderr).not.toContain("not a token!");
  });
  test("no Local Storage in the profile", () => {
    const r = run([tmp("empty-profile-"), "--emit-fd", "3"]);
    expect([r.code, r.fd3, JSON.parse(r.stdout).status]).toEqual([3, "", "no-local-storage"]);
  });
  test("without --emit-fd the token is read and discarded: nowhere in the output", () => {
    const r = run([join(FIX, "log-only")]);
    expect(r.code).toBe(0);
    expect(JSON.parse(r.stdout).emitted).toBe(false);
    expect(r.fd3).toBe("");
    noSecret(r);
  });
  test.each(["0", "1", "2", "-1", "x", "9"])("--emit-fd %s is refused before anything is read", (fd) => {
    const r = run([join(FIX, "log-only"), "--emit-fd", fd]);
    expect(r.code).toBe(2);
    expect(r.fd3).toBe("");
    noSecret(r);
  });
  test("a torn record at the end of the log is skipped", () => {
    const prof = tmp("torn-");
    cpSync(join(FIX, "log-only"), prof, { recursive: true });
    const log = join(prof, "Local Storage", "leveldb", "000003.log");
    appendFileSync(log, Buffer.from([0xde, 0xad, 0xbe, 0xef, 0x40, 0x00, 0x01, 0x00, 0x00])); // header claims 64 bytes
    const r = run([prof, "--emit-fd", "3"]);
    expect([r.code, r.fd3]).toEqual([0, T.log]);
  });
});

function sha(dir: string) {
  return Object.fromEntries(readdirSync(dir).filter((f) => f !== "LOCK")
    .map((f) => [f, createHash("sha256").update(readFileSync(join(dir, f))).digest("hex")]));
}

describe("Chrome running: LOCK held, live files never touched", () => {
  test("reads a private copy while another process holds the LOCK, leaves no copy behind", async () => {
    const prof = tmp("locked-");
    cpSync(join(FIX, "table"), prof, { recursive: true });
    const db = join(prof, "Local Storage", "leveldb");
    const lock = join(db, "LOCK");
    // Hold an exclusive flock on LOCK as Chrome does, then make it unreadable: opening it at all would fail.
    const holder = spawn("perl", ["-e", 'use Fcntl ":flock"; open(F, "<", $ARGV[0]) or die; flock(F, LOCK_EX) or die; print "held\\n"; $| = 1; sleep 30', lock], { stdio: ["ignore", "pipe", "inherit"] });
    await new Promise<void>((res) => holder.stdout!.once("data", () => res()));
    chmodSync(lock, 0o000);
    const before = sha(db);
    const tdir = tmp("reader-tmp-");
    try {
      const r = run([prof, "--emit-fd", "3"], { TMPDIR: tdir });
      expect([r.code, r.fd3]).toEqual([0, T.table]);
      noSecret(r);
    } finally {
      holder.kill("SIGKILL");
    }
    expect(sha(db)).toEqual(before);
    expect(statSync(lock).mode & 0o777).toBe(0);
    expect(readdirSync(tdir)).toEqual([]); // the private copy was deleted
  });

  test("snapshot: 0700 directory, 0600 files, no LOCK, symlinks not followed", () => {
    const prof = tmp("snap-");
    cpSync(join(FIX, "log-only"), prof, { recursive: true });
    const db = join(prof, "Local Storage", "leveldb");
    const outside = join(prof, "outside-secret");
    writeFileSync(outside, "outside");
    symlinkSync(outside, join(db, "000009.log"));
    const snap = snapshot(db);
    scratch.push(snap);
    expect(statSync(snap).mode & 0o777).toBe(0o700);
    const names = readdirSync(snap);
    expect(names).not.toContain("LOCK");
    expect(names).not.toContain("000009.log");
    for (const n of names) expect(statSync(join(snap, n)).mode & 0o777).toBe(0o600);
    expect(existsSync(join(snap, "CURRENT"))).toBe(true);
  });
});

// The function under test, extracted from the script (it runs its CLI when executed), as test-token-get.sh does.
function fns(): string {
  const d = tmp("fns-");
  const m = readFileSync(join(HERE, "chrome-profile.sh"), "utf8").match(/^token_from_profile\(\) \{[\s\S]*?^\}/m);
  if (!m) throw new Error("token_from_profile not found in chrome-profile.sh");
  writeFileSync(join(d, "fns.sh"), `EXT_ID="mmlmfjhmonkocbjadbfplnigmagldckm"\nSELF="${join(HERE, "chrome-profile.sh")}"\n${m[0]}\n`);
  return join(d, "fns.sh");
}

describe("chrome-profile.sh token_from_profile", () => {
  const sh = (profile: string, path = process.env.PATH ?? "") => spawnSync("/usr/bin/env", ["bash", "-c",
    'set -euo pipefail; . "$1"; rc=0; tok=$(token_from_profile "$2") || rc=$?; ' +
    'if [ "$tok" = "$WANT" ]; then m=match; else m=differ; fi; echo "rc=$rc len=$(printf %s "$tok" | wc -c | tr -d " ") $m"', "_", fns(), profile],
  { env: { ...process.env, PATH: path, WANT: T.log }, encoding: "utf8", cwd: tmp("cwd-") });

  test("found: the captured value is the token, and the shell prints nothing of it", () => {
    const r = sh(join(FIX, "log-only"));
    expect(r.stdout.trim()).toBe(`rc=0 len=${T.log.length} match`);
    noSecret(r);
  });
  test("not found: exit 1 and an empty capture (the caller falls back to the paste dialog)", () => {
    expect(sh(join(FIX, "no-token")).stdout.trim()).toBe("rc=1 len=0 differ");
  });
  test("bun missing: exit 127", () => {
    expect(sh(join(FIX, "log-only"), "/usr/bin:/bin").stdout.trim()).toBe("rc=127 len=0 differ");
  });
  test("a .env and bunfig.toml in the caller's directory are not loaded", () => {
    const d = tmp("hostile-cwd-");
    writeFileSync(join(d, "bunfig.toml"), `preload = ["./evil.ts"]\n`);
    writeFileSync(join(d, "evil.ts"), `console.log("PRELOADED"); require("node:fs").writeFileSync("${join(d, "ran")}", "x");\n`);
    writeFileSync(join(d, ".env"), "EVIL=1\n");
    const r = spawnSync("/usr/bin/env", ["bash", "-c", '. "$1"; tok=$(token_from_profile "$2"); echo "len=$(printf %s "$tok" | wc -c | tr -d " ")"', "_", fns(), join(FIX, "log-only")],
      { env: process.env, encoding: "utf8", cwd: d });
    expect(r.stdout.trim()).toBe(`len=${T.log.length}`);
    expect(existsSync(join(d, "ran"))).toBe(false);
  });
});
