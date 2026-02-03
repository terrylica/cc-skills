/**
 * OAuth2 authentication for Gmail API
 *
 * Retrieves credentials from 1Password using UUID from environment.
 * Tokens stored at ~/.claude/tools/gmail-tokens/<uuid>.json
 */

import { mkdir } from "node:fs/promises";
import { auth } from "@googleapis/gmail";
import type { OAuthCredentials, SavedToken } from "./types.ts";
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
 * Retrieve OAuth credentials from 1Password using UUID
 */
export async function getCredentialsFrom1Password(): Promise<OAuthCredentials> {
  const uuid = getOpUuid();
  const vault = getOpVault();

  const proc = Bun.spawn(["op", "item", "get", uuid, "--vault", vault, "--format", "json"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  const output = await new Response(proc.stdout).text();
  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`1Password error: ${stderr}`);
  }

  const item = JSON.parse(output);
  const fields: Record<string, string> = {};

  for (const field of item.fields ?? []) {
    const key = field.label ?? field.id;
    if (key && field.value) {
      fields[key] = field.value;
    }
  }

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

  console.error("Opening browser for authorization...");
  console.error(`If browser doesn't open, visit: ${authUrl}\n`);

  Bun.spawn(["open", authUrl]);

  const code = await waitForAuthCode(port);

  const { tokens } = await oauth2Client.getToken(code);
  oauth2Client.setCredentials(tokens);
  await saveToken(tokens as SavedToken);

  console.error("Token saved successfully!");
  return oauth2Client;
}
