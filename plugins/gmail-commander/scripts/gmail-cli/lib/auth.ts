/**
 * OAuth2 authentication for Gmail API
 *
 * Retrieves the OAuth client from GMAIL_OAUTH_CLIENT_ID/SECRET or GMAIL_OAUTH_CLIENT_FILE when set, else from the
 * 1Password item named by GMAIL_OP_UUID (see credential-source.ts).
 * Tokens stored at ~/.claude/tools/gmail-tokens/<uuid>.json
 */

import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { auth } from "../vendor/googleapis-gmail.js";
import type { OAuthCredentials, SavedToken } from "./types.ts";
import {
  browserOpenCommand,
  clientFromEnv,
  clientFromJsonText,
  ENV_CLIENT_FILE,
  noOnePasswordHint,
  type OAuthClient,
  remoteConsentHint,
} from "./credential-source.ts";
import {
  getOpUuid,
  getOpVault,
  getTokenPath,
  getTokensDir,
  SCOPES,
  AUTH_TIMEOUT_MS,
  EPHEMERAL_PORT_START,
  EPHEMERAL_PORT_RANGE,
} from "./config.ts";

// Use OAuth2 client from @googleapis/gmail for type compatibility
type OAuth2Client = InstanceType<typeof auth.OAuth2>;

/**
 * Auto-bypass HTTP/HTTPS proxy for Google API hosts.
 *
 * The googleapis library uses gaxios → https-proxy-agent under the hood,
 * which honors the NO_PROXY env var for host exclusion. Corporate proxies
 * (Cloudflare WARP, mitmproxy, ITP local interceptors) often can't tunnel
 * CONNECT to googleapis.com — Google's response surface returns a silent
 * 502 with no message body, which the CLI used to render as a useless
 * empty "Error:". To avoid that failure mode, we inject the Google API
 * hosts into NO_PROXY at module load so Gmail traffic skips the proxy.
 *
 * Idempotent: only adds entries that aren't already present.
 *
 * Added 2026-05-22 in response to silent failures in client project
 * where HTTPS_PROXY=http://127.0.0.1:58124 (local interceptor) caused
 * `gmail list` to print empty "Error:" and exit 1.
 */
function ensureGoogleApiProxyBypass(): void {
  const httpsProxy = process.env.HTTPS_PROXY ?? process.env.https_proxy;
  const httpProxy = process.env.HTTP_PROXY ?? process.env.http_proxy;
  if (!httpsProxy && !httpProxy) return;

  const current = process.env.NO_PROXY ?? process.env.no_proxy ?? "";
  const currentLower = current.toLowerCase();
  // The leading-dot form (".googleapis.com") tells https-proxy-agent to
  // match the host AND all subdomains. Listing common Google auth hosts
  // explicitly is belt-and-braces — both forms are honored.
  const required = [".googleapis.com", ".google.com", "accounts.google.com", "oauth2.googleapis.com"];
  const toAdd = required.filter(h => !currentLower.includes(h.toLowerCase()));
  if (toAdd.length === 0) return;

  const updated = current ? `${current},${toAdd.join(",")}` : toAdd.join(",");
  process.env.NO_PROXY = updated;
  process.env.no_proxy = updated;
}

// Run at module load — before any auth or API request.
ensureGoogleApiProxyBypass();

/**
 * Get path for cached app credentials
 */
function getAppCredentialsPath(uuid?: string): string {
  const actualUuid = uuid ?? getOpUuid();
  return join(getTokensDir(), `${actualUuid}.app-credentials.json`);
}

/**
 * Load cached app credentials from disk
 */
async function loadAppCredentials(): Promise<{ client_id: string; client_secret: string } | null> {
  try {
    const file = Bun.file(getAppCredentialsPath());
    if (await file.exists()) {
      return await file.json();
    }
  } catch {
    // Cache miss
  }
  return null;
}

/**
 * Save app credentials to disk for future use
 */
async function saveAppCredentials(clientId: string, clientSecret: string): Promise<void> {
  const tokensDir = getTokensDir();
  await mkdir(tokensDir, { recursive: true, mode: 0o700 });
  const path = getAppCredentialsPath();
  await Bun.write(path, JSON.stringify({ client_id: clientId, client_secret: clientSecret }));
  Bun.spawn(["chmod", "600", path]);
}

function installedCredentials(client: OAuthClient): OAuthCredentials {
  return {
    installed: {
      client_id: client.client_id,
      client_secret: client.client_secret,
      redirect_uris: ["http://localhost"],
      auth_uri: "https://accounts.google.com/o/oauth2/auth",
      token_uri: "https://oauth2.googleapis.com/token",
    },
  };
}

/** The client named explicitly in the environment (variables, then file), or null when neither is set. */
async function explicitClient(): Promise<OAuthClient | null> {
  const fromEnv = clientFromEnv(process.env);
  if (fromEnv.kind === "error") throw new Error(fromEnv.reason);
  if (fromEnv.kind === "client") return fromEnv.client;
  const path = process.env[ENV_CLIENT_FILE]?.trim();
  if (!path) return null;
  const file = Bun.file(path);
  if (!(await file.exists())) throw new Error(`${ENV_CLIENT_FILE} ${path} does not exist`);
  const fromFile = clientFromJsonText(await file.text(), path);
  if (fromFile.kind === "error") throw new Error(fromFile.reason);
  return fromFile.kind === "client" ? fromFile.client : null;
}

/**
 * Retrieve OAuth credentials: an explicitly configured client first (GMAIL_OAUTH_CLIENT_ID/SECRET, then
 * GMAIL_OAUTH_CLIENT_FILE; never cached), then the cached app credentials, then 1Password (cached for next time).
 * With none of the explicit variables set, this is exactly the earlier cache-then-1Password behaviour.
 */
export async function getCredentialsFrom1Password(): Promise<OAuthCredentials> {
  const explicit = await explicitClient();
  if (explicit) return installedCredentials(explicit);

  // Try cached app credentials first (avoids 1Password call at runtime)
  const cached = await loadAppCredentials();
  if (cached) return installedCredentials(cached);

  // Fallback: fetch from 1Password and cache
  const uuid = getOpUuid();
  const vault = getOpVault();

  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(["op", "item", "get", uuid, "--vault", vault, "--format", "json"], {
      stdout: "pipe",
      stderr: "pipe",
    });
  } catch {
    // Bun.spawn throws when `op` is not on PATH.
    throw new Error(`the 1Password CLI (op) is not installed. ${noOnePasswordHint()}`);
  }

  const output = await new Response(proc.stdout as ReadableStream).text();
  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr as ReadableStream).text();
    throw new Error(`1Password error: ${stderr.trim()}\n  ${noOnePasswordHint()}`);
  }

  const item = JSON.parse(output);
  const fields: Record<string, string> = {};

  for (const field of item.fields ?? []) {
    const key = field.label ?? field.id;
    if (key && field.value) {
      fields[key] = field.value;
    }
  }

  // Cache for next time
  await saveAppCredentials(fields.client_id!, fields.client_secret!);

  return {
    installed: {
      client_id: fields.client_id!,
      client_secret: fields.client_secret!,
      redirect_uris: [fields.redirect_uris ?? "http://localhost"],
      auth_uri: fields.auth_uri ?? "https://accounts.google.com/o/oauth2/auth",
      token_uri: fields.token_uri ?? "https://oauth2.googleapis.com/token",
    },
  };
}

/**
 * Load saved token from disk
 */
export async function loadToken(): Promise<SavedToken | null> {
  try {
    const tokenPath = getTokenPath();
    const file = Bun.file(tokenPath);
    if (await file.exists()) {
      return await file.json();
    }
  } catch {
    // Token doesn't exist or is invalid
  }
  return null;
}

/**
 * Save token to disk with secure permissions
 */
export async function saveToken(token: SavedToken): Promise<void> {
  const tokensDir = getTokensDir();
  const tokenPath = getTokenPath();

  // Ensure tokens directory exists
  await mkdir(tokensDir, { recursive: true, mode: 0o700 });

  await Bun.write(tokenPath, JSON.stringify(token, null, 2));
  Bun.spawn(["chmod", "600", tokenPath]);
}

/**
 * Start local server to receive OAuth callback
 */
async function waitForAuthCode(port: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const server = Bun.serve({
      port,
      fetch(req) {
        const url = new URL(req.url);
        const code = url.searchParams.get("code");
        const error = url.searchParams.get("error");

        if (error) {
          server.stop();
          reject(new Error(`OAuth error: ${error}`));
          return new Response(
            `<html><body><h1>Authorization failed</h1><p>${error}</p></body></html>`,
            { headers: { "Content-Type": "text/html" } }
          );
        }

        if (code) {
          server.stop();
          resolve(code);
          return new Response(
            `<html><body><h1>Authorization successful!</h1><p>You can close this window.</p></body></html>`,
            { headers: { "Content-Type": "text/html" } }
          );
        }

        return new Response("Waiting for authorization...", { status: 400 });
      },
    });

    setTimeout(() => {
      server.stop();
      reject(new Error("Authorization timeout"));
    }, AUTH_TIMEOUT_MS);
  });
}

/**
 * Create authenticated OAuth2 client
 */
export async function getAuthClient(): Promise<OAuth2Client> {
  const credentials = await getCredentialsFrom1Password();
  const { client_id, client_secret } = credentials.installed;

  const port = EPHEMERAL_PORT_START + Math.floor(Math.random() * EPHEMERAL_PORT_RANGE);
  const redirectUri = `http://localhost:${port}`;

  const oauth2Client = new auth.OAuth2(client_id, client_secret, redirectUri);

  const savedToken = await loadToken();

  if (savedToken) {
    oauth2Client.setCredentials(savedToken);

    if (savedToken.expiry_date && savedToken.expiry_date < Date.now()) {
      console.error("Token expired, refreshing...");
      const { credentials: newCreds } = await oauth2Client.refreshAccessToken();
      await saveToken(newCreds as SavedToken);
    }

    return oauth2Client;
  }

  // No token - need to authorize via local server
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: "offline",
    scope: [...SCOPES],
  });

  const opener = browserOpenCommand(authUrl, process.platform, process.env, (c) => Bun.which(c));
  let opened = false;
  if (opener) {
    try {
      Bun.spawn(opener, { stdout: "ignore", stderr: "ignore" });
      opened = true;
    } catch {
      // No opener after all; the URL below is the way in.
    }
  }
  console.error(opened ? "Opening browser for authorization..." : "Authorize in a browser:");
  console.error(`If browser doesn't open, visit: ${authUrl}\n`);
  // Off macOS, xdg-open can start and still show nothing (no browser registered, a forwarded X display), so the way
  // to finish from another computer is always printed there.
  if (!opened || process.platform !== "darwin") console.error(`${remoteConsentHint(port)}\n`);

  const code = await waitForAuthCode(port);

  const { tokens } = await oauth2Client.getToken(code);
  oauth2Client.setCredentials(tokens);
  await saveToken(tokens as SavedToken);

  console.error("Token saved successfully!");
  return oauth2Client;
}
