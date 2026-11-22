/**
 * Where the OAuth client (client_id, client_secret) comes from, and how the consent page is opened.
 *
 * The 1Password item named by GMAIL_OP_UUID stays the default. Two explicit sources come first, so a machine
 * without 1Password (a Linux host has no 1Password desktop app; `op` there needs a service-account token) can supply
 * the client from whatever secret store it has, for example `vault run <scope> -- gmail list`:
 *
 *   1. GMAIL_OAUTH_CLIENT_ID and GMAIL_OAUTH_CLIENT_SECRET, both set.
 *   2. GMAIL_OAUTH_CLIENT_FILE: the client JSON Google Cloud Console downloads ({"installed": {...}} or
 *      {"web": {...}}), or a bare {"client_id": ..., "client_secret": ...}.
 *
 * Neither is written to disk. Pure functions only; auth.ts does the I/O.
 */

export interface OAuthClient {
  client_id: string;
  client_secret: string;
}

export type ClientSource =
  | { kind: "client"; client: OAuthClient; source: "env" | "file" }
  | { kind: "none" }
  | { kind: "error"; reason: string };

type Env = Record<string, string | undefined>;

export const ENV_CLIENT_ID = "GMAIL_OAUTH_CLIENT_ID";
export const ENV_CLIENT_SECRET = "GMAIL_OAUTH_CLIENT_SECRET";
export const ENV_CLIENT_FILE = "GMAIL_OAUTH_CLIENT_FILE";

/** The client from the environment: both variables, one of them (an error), or neither. */
export function clientFromEnv(env: Env): ClientSource {
  const id = env[ENV_CLIENT_ID]?.trim();
  const secret = env[ENV_CLIENT_SECRET]?.trim();
  if (id && secret) return { kind: "client", client: { client_id: id, client_secret: secret }, source: "env" };
  if (id || secret) {
    return { kind: "error", reason: `${ENV_CLIENT_ID} and ${ENV_CLIENT_SECRET} must be set together` };
  }
  return { kind: "none" };
}

/** The client from the text of a client JSON file. */
export function clientFromJsonText(text: string, path: string): ClientSource {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return { kind: "error", reason: `${ENV_CLIENT_FILE} ${path} is not JSON` };
  }
  const root = (data ?? {}) as Record<string, unknown>;
  const inner = (root.installed ?? root.web ?? root) as Record<string, unknown>;
  const id = typeof inner.client_id === "string" ? inner.client_id.trim() : "";
  const secret = typeof inner.client_secret === "string" ? inner.client_secret.trim() : "";
  if (!id || !secret) {
    return { kind: "error", reason: `${ENV_CLIENT_FILE} ${path} has no client_id and client_secret` };
  }
  return { kind: "client", client: { client_id: id, client_secret: secret }, source: "file" };
}

/** What to tell someone whose 1Password lookup could not run, naming every other source. */
export function noOnePasswordHint(platform: NodeJS.Platform = process.platform): string {
  const op =
    platform === "darwin"
      ? "install the 1Password CLI (brew install 1password-cli) and sign in, or export OP_SERVICE_ACCOUNT_TOKEN"
      : "install the 1Password CLI and export OP_SERVICE_ACCOUNT_TOKEN (there is no 1Password desktop app here to sign it in)";
  return (
    `Supply the OAuth client one of three ways: set ${ENV_CLIENT_ID} and ${ENV_CLIENT_SECRET} ` +
    `(e.g. from your own secret store: vault run <scope> -- gmail ...), set ${ENV_CLIENT_FILE} to the client JSON ` +
    `Google Cloud Console downloads, or ${op}.`
  );
}

/**
 * The command that opens a URL in this machine's browser, or undefined when there is none to open it in
 * (Linux without a graphical session, or without xdg-open). macOS keeps `open`.
 */
export function browserOpenCommand(
  url: string,
  platform: NodeJS.Platform,
  env: Env,
  which: (cmd: string) => string | null | undefined,
): string[] | undefined {
  if (platform === "darwin") return ["open", url];
  // Not Windows: `cmd /c start` would cut a consent URL at its first `&`.
  if (platform !== "linux" && !platform.endsWith("bsd")) return undefined;
  if (!env.DISPLAY && !env.WAYLAND_DISPLAY) return undefined;
  const opener = which("xdg-open");
  return opener ? [opener, url] : undefined;
}

/** How to finish consent from another machine when this one cannot show a browser (an SSH session). */
export function remoteConsentHint(port: number): string {
  return (
    `If no browser opened here (an SSH session), open the URL above on your own computer after forwarding the callback port: ` +
    `ssh -L ${port}:localhost:${port} <this-host>, then keep that session open until the CLI says the token is saved.`
  );
}
