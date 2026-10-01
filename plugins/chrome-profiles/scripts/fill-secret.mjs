#!/usr/bin/env node
// fill-secret — type a secret from the macOS Keychain (or a `vault` CLI) into one field of an open page, so the
// AI driving the browser never sees it. Works on any Chrome started with a debug port (chrome-debug-port-control.sh,
// agent-chrome, a per-tool harness). No dependencies: Node's built-in fetch + WebSocket speak CDP directly.
//
//   node fill-secret.mjs --port 9222 --page <url-substring> --selector '<css>' --keychain <service>:<account>
//   node fill-secret.mjs --port 9222 --page <url-substring> --selector '<css>' --vault <scope>:<key>
//   add --submit to press Enter in the field afterwards
//
// Prints only what happened ("filled 1 field, 24 characters"), never the value. Refuses if zero or several tabs
// match, or if the selector matches nothing, a non-input, or more than one element.
import { execFileSync } from "node:child_process";

const die = (msg) => {
  console.error(`✗ ${msg}`);
  process.exit(1);
};

const args = process.argv.slice(2);
const opt = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const port = Number(opt("--port") ?? 9222);
const pageMatch = opt("--page");
const selector = opt("--selector");
const keychain = opt("--keychain");
const vaultRef = opt("--vault");
const submit = args.includes("--submit");
if (!pageMatch || !selector || (!keychain && !vaultRef) || (keychain && vaultRef)) {
  console.error(
    "usage: fill-secret.mjs --port <n> --page <url-substring> --selector <css> (--keychain service:account | --vault scope:key) [--submit]",
  );
  process.exit(2);
}

function readSecret() {
  const ref = keychain ?? vaultRef;
  const cut = ref.indexOf(":");
  if (cut < 1) die(`expected <a>:<b>, got '${ref}'`);
  const [a, b] = [ref.slice(0, cut), ref.slice(cut + 1)];
  try {
    const out = keychain
      ? execFileSync("security", ["find-generic-password", "-s", a, "-a", b, "-w"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })
      : execFileSync("vault", ["get", a, b], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    const v = out.replace(/\r?\n$/, "");
    if (!v) die("the stored value is empty");
    return v;
  } catch {
    return die(`could not read ${keychain ? "Keychain item" : "vault entry"} '${ref}'`);
  }
}

let targets;
try {
  targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
} catch {
  die(`no Chrome debug port on 127.0.0.1:${port} (start one with chrome-debug-port-control.sh up)`);
}
const pages = targets.filter((t) => t.type === "page" && t.url.includes(pageMatch));
if (pages.length !== 1) die(`${pages.length} open tabs match '${pageMatch}' (need exactly 1)`);

const ws = new WebSocket(pages[0].webSocketDebuggerUrl);
await new Promise((ok, bad) => {
  ws.addEventListener("open", ok, { once: true });
  ws.addEventListener("error", () => bad(new Error("websocket failed")), { once: true });
});
let nextId = 0;
const pending = new Map();
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) {
    pending.get(m.id)(m);
    pending.delete(m.id);
  }
});
const send = (method, params) =>
  new Promise((resolve) => {
    const id = ++nextId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
const evaluate = async (expression) => {
  const r = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
  if (r.error || r.result?.exceptionDetails) die("the page rejected the script");
  return r.result.result.value;
};

const sel = JSON.stringify(selector);
const check = await evaluate(`(() => {
  const els = document.querySelectorAll(${sel});
  if (els.length !== 1) return "matches:" + els.length;
  const el = els[0];
  if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement)) return "not-an-input";
  return "ok:" + (el.maxLength > 0 ? el.maxLength : 0);
})()`);
if (!String(check).startsWith("ok:")) die(`selector problem: ${check}`);

const secret = readSecret();
const maxLength = Number(String(check).slice(3));
if (maxLength && secret.length > maxLength) die(`the field accepts ${maxLength} characters, the secret has ${secret.length} — refusing to submit a truncated value`);

// Set the value the way a framework-controlled input notices (native setter + input/change events).
const filled = await evaluate(`(() => {
  const el = document.querySelector(${sel});
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, "value").set.call(el, ${JSON.stringify(secret)});
  el.dispatchEvent(new Event("input", { bubbles: true }));
  el.dispatchEvent(new Event("change", { bubbles: true }));
  return el.value.length;
})()`);
if (filled !== secret.length) die("the field did not keep the full value");

if (submit) {
  await evaluate(`(() => {
    const el = document.querySelector(${sel});
    if (el.form && typeof el.form.requestSubmit === "function") { el.form.requestSubmit(); return "form"; }
    el.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", keyCode: 13, bubbles: true }));
    return "enter";
  })()`);
}
ws.close();
console.log(`filled 1 field, ${filled} characters${submit ? ", submitted" : ""}`);
