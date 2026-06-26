#!/usr/bin/env node
// webauthn-smoke.mjs — live CDP virtual-authenticator proof (GitHub-independent).
//
// Serves a tiny WebAuthn page on http://localhost (a secure context), registers
// a passkey via the virtual authenticator, captures it with getCredentials,
// then RESTORES it into a fresh authenticator and confirms the same credential
// is present — exactly the create→persist→re-inject path autosudo relies on.
import http from "node:http";
import { launchChrome, connect } from "../scripts/browser.mjs";
import { openWebAuthn, mountAuthenticator, getCredentials, serializeCredential, injectCredential, removeAuthenticator } from "../scripts/webauthn.mjs";

const PAGE = `<!doctype html><meta charset=utf8><title>wa-smoke</title><body><script>
window.waCreate = async () => {
  const cred = await navigator.credentials.create({ publicKey: {
    challenge: new Uint8Array(32),
    rp: { name: "smoke", id: "localhost" },
    user: { id: new Uint8Array([1,2,3,4]), name: "smoke", displayName: "smoke" },
    pubKeyCredParams: [{ type: "public-key", alg: -7 }],
    authenticatorSelection: { residentKey: "required", userVerification: "required", authenticatorAttachment: "platform" },
    timeout: 20000,
  }});
  return cred.id;
};
</script></body>`;

const server = http.createServer((_req, res) => res.end(PAGE)).listen(0, "127.0.0.1");
await new Promise((r) => server.on("listening", r));
const url = `http://localhost:${server.address().port}/`;
let failed = false;
function check(cond, msg) {
  if (cond) {
    console.log(`  ✓ ${msg}`);
  } else {
    failed = true;
    console.error(`  ✗ ${msg}`);
  }
}

await launchChrome(url);
const { browser, ctx } = await connect();
const page = await ctx.newPage();
await page.goto(url, { waitUntil: "domcontentloaded" });

try {
  // 1) Register a passkey via the virtual authenticator.
  const client = await openWebAuthn(page);
  const authId = await mountAuthenticator(client); // presence simulation set BEFORE create()
  const newId = await page.evaluate(() => window.waCreate());
  check(typeof newId === "string" && newId.length > 0, `navigator.credentials.create returned a credential id`);

  const creds = await getCredentials(client, authId);
  check(creds.length === 1, `getCredentials captured exactly 1 resident credential`);
  const blob = serializeCredential(creds[0]);
  check(blob.rpId === "localhost" && !!blob.privateKey && !!blob.credentialId, `serialized blob has rpId + privateKey + credentialId`);

  // 2) RESTORE into a fresh authenticator (the autosudo re-inject path).
  await removeAuthenticator(client, authId);
  const client2 = await openWebAuthn(page);
  const authId2 = await mountAuthenticator(client2);
  await injectCredential(client2, authId2, blob);
  const restored = await getCredentials(client2, authId2);
  check(restored.some((c) => c.credentialId === blob.credentialId), `restored credential present after addCredential (round-trip)`);
  await removeAuthenticator(client2, authId2);
} finally {
  await browser.close();
  server.close();
}

console.log(`\n${failed ? "FAIL" : "PASS"} — virtual-authenticator create→capture→restore`);
process.exit(failed ? 1 : 0);
