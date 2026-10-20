// vault.mjs — the SCS vault sinks every web-forge path uses. Values ride PIPES: never argv, never stdout, never a
// transcript. Callers log lengths and vault paths, not values. Shared by the node forge scripts (browser-forge.mjs)
// and the Bun recipe runner (Driver.extractToVault).
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

export const VAULT_BIN = join(homedir(), ".local/bin/vault");
/** Read per call, so WEB_FORGE_VAULT_BIN set after import still applies. */
const vaultBin = () => process.env.WEB_FORGE_VAULT_BIN ?? VAULT_BIN;

export function vaultSet(scope, path, value) {
  return new Promise((resolve, reject) => {
    const p = spawn(vaultBin(), ["set", "--stdin", scope, path], { stdio: ["pipe", "inherit", "inherit"] });
    p.on("error", reject);
    p.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`vault set ${scope} ${path} → exit ${code}`))));
    p.stdin.write(value);
    p.stdin.end();
  });
}

export function vaultGet(scope, path) {
  return new Promise((resolve, reject) => {
    const p = spawn(vaultBin(), ["get", scope, path], { stdio: ["ignore", "pipe", "inherit"] });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.on("error", reject);
    p.on("exit", (code) => (code === 0 ? resolve(out.trim()) : reject(new Error(`vault get ${scope} ${path} → exit ${code}`))));
  });
}
