import { describe, expect, test } from "bun:test";
import {
  browserOpenCommand,
  clientFromEnv,
  clientFromJsonText,
  noOnePasswordHint,
  remoteConsentHint,
} from "./credential-source.ts";

describe("clientFromEnv", () => {
  test("both variables give a client; neither gives none; one alone is an error", () => {
    expect(clientFromEnv({ GMAIL_OAUTH_CLIENT_ID: "id", GMAIL_OAUTH_CLIENT_SECRET: "s" })).toEqual({
      kind: "client",
      client: { client_id: "id", client_secret: "s" },
      source: "env",
    });
    expect(clientFromEnv({})).toEqual({ kind: "none" });
    expect(clientFromEnv({ GMAIL_OAUTH_CLIENT_ID: "id" }).kind).toBe("error");
    expect(clientFromEnv({ GMAIL_OAUTH_CLIENT_SECRET: "s" }).kind).toBe("error");
  });
});

describe("clientFromJsonText", () => {
  test("reads Google's installed and web downloads and a bare pair", () => {
    for (const text of [
      JSON.stringify({ installed: { client_id: "a", client_secret: "b" } }),
      JSON.stringify({ web: { client_id: "a", client_secret: "b" } }),
      JSON.stringify({ client_id: "a", client_secret: "b" }),
    ]) {
      expect(clientFromJsonText(text, "f.json")).toMatchObject({ kind: "client", client: { client_id: "a", client_secret: "b" } });
    }
  });
  test("names the file when it is not JSON or lacks the pair", () => {
    expect(clientFromJsonText("{", "f.json")).toMatchObject({ kind: "error" });
    expect(clientFromJsonText(JSON.stringify({ installed: { client_id: "a" } }), "f.json")).toMatchObject({ kind: "error" });
  });
});

describe("browserOpenCommand", () => {
  const which = (c: string) => (c === "xdg-open" ? "/usr/bin/xdg-open" : null);
  test("macOS keeps open", () => {
    expect(browserOpenCommand("u", "darwin", {}, which)).toEqual(["open", "u"]);
  });
  test("Linux uses xdg-open only inside a graphical session", () => {
    expect(browserOpenCommand("u", "linux", { DISPLAY: ":0" }, which)).toEqual(["/usr/bin/xdg-open", "u"]);
    expect(browserOpenCommand("u", "linux", { WAYLAND_DISPLAY: "wayland-0" }, which)).toEqual(["/usr/bin/xdg-open", "u"]);
    expect(browserOpenCommand("u", "linux", {}, which)).toBeUndefined();
    expect(browserOpenCommand("u", "linux", { DISPLAY: ":0" }, () => null)).toBeUndefined();
  });
});

describe("hints", () => {
  test("the no-1Password hint names every source, and the macOS one names Homebrew", () => {
    const linux = noOnePasswordHint("linux");
    for (const v of ["GMAIL_OAUTH_CLIENT_ID", "GMAIL_OAUTH_CLIENT_SECRET", "GMAIL_OAUTH_CLIENT_FILE", "OP_SERVICE_ACCOUNT_TOKEN"]) {
      expect(linux).toContain(v);
    }
    expect(linux).not.toContain("brew");
    expect(noOnePasswordHint("darwin")).toContain("brew install 1password-cli");
  });
  test("the remote consent hint forwards the callback port", () => {
    expect(remoteConsentHint(50123)).toContain("ssh -L 50123:localhost:50123");
  });
});
