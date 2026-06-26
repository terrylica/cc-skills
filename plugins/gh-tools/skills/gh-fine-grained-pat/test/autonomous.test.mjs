#!/usr/bin/env node
// autonomous.test.mjs — deterministic unit tests for the autonomous web-auth
// building blocks (no browser, no network). Run: node test/autonomous.test.mjs
import assert from "node:assert/strict";
import net from "node:net";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { accountFromOriginUrl, vaultItemName } from "../scripts/identity.mjs";
import { serializeCredential } from "../scripts/webauthn.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let pass = 0;
const ok = (name, fn) => {
  try {
    fn();
    pass++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    console.error(`  ✗ ${name}: ${e.message}`);
    process.exitCode = 1;
  }
};

// --- identity: host-alias parsing ---
ok("host-alias → account", () =>
  assert.equal(accountFromOriginUrl("git@github.com-terrylica:terrylica/cc-skills.git"), "terrylica"));
ok("plain github → null", () => assert.equal(accountFromOriginUrl("git@github.com:foo/bar.git"), null));
ok("https remote → null", () => assert.equal(accountFromOriginUrl("https://github.com/foo/bar.git"), null));
ok("empty → null", () => assert.equal(accountFromOriginUrl(""), null));
ok("vaultItemName", () => assert.equal(vaultItemName("acme"), "github-web-acme"));

// --- webauthn: credential serialization shape ---
ok("serializeCredential keeps required fields + defaults", () => {
  const s = serializeCredential({ credentialId: "id", rpId: "github.com", privateKey: "pk" });
  assert.deepEqual(s, { credentialId: "id", rpId: "github.com", privateKey: "pk", userHandle: "", signCount: 0 });
});

// --- agent: put/get/expiry round-trip over the unix socket ---
function rpc(sock, payload) {
  return new Promise((resolve) => {
    const c = net.connect(sock);
    let b = "";
    c.on("connect", () => c.end(JSON.stringify(payload)));
    c.on("data", (d) => (b += d));
    c.on("end", () => {
      try {
        resolve(JSON.parse(b));
      } catch {
        resolve({ ok: false });
      }
    });
    c.on("error", () => resolve({ ok: false }));
  });
}

async function agentRoundTrip() {
  const sock = join(tmpdir(), `gh-pat-test-agent-${process.pid}.sock`);
  const srv = spawn(process.execPath, [join(HERE, "..", "scripts", "webauth-agent.mjs"), "serve"], {
    env: { ...process.env, GH_PAT_AGENT_SOCK: sock },
    stdio: "ignore",
  });
  await sleep(700);
  try {
    assert.equal((await rpc(sock, { op: "get", account: "x" })).ok, false);
    pass++;
    console.log("  ✓ agent miss before put");
    assert.equal((await rpc(sock, { op: "put", account: "x", blob: { hi: 1 }, ttlMs: 5000 })).ok, true);
    assert.deepEqual((await rpc(sock, { op: "get", account: "x" })).blob, { hi: 1 });
    pass++;
    console.log("  ✓ agent put/get hit");
    await rpc(sock, { op: "put", account: "y", blob: { z: 2 }, ttlMs: 1 });
    await sleep(40);
    assert.equal((await rpc(sock, { op: "get", account: "y" })).ok, false);
    pass++;
    console.log("  ✓ agent TTL expiry");
  } finally {
    srv.kill("SIGTERM");
  }
}

await agentRoundTrip();
console.log(`\n${process.exitCode ? "FAIL" : "PASS"} — ${pass} assertions`);
process.exit(process.exitCode ?? 0);
