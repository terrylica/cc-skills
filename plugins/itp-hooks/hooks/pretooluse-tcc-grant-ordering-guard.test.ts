import { describe, expect, test } from "bun:test";
import {
  findTccOrderingViolations,
  explainTccOrderingViolations,
} from "./pretooluse-tcc-grant-ordering-guard.ts";

const kinds = (cmd: string) =>
  findTccOrderingViolations(cmd).map((v) => v.kind);

describe("app deletion before a TCC reset", () => {
  test("blocks rm -rf of an .app bundle", () => {
    expect(kinds('rm -rf "/Applications/RustDesk.app"')).toContain(
      "app-delete-before-tcc-reset",
    );
  });

  test("blocks brew uninstall --cask", () => {
    expect(kinds("brew uninstall --cask teamviewer")).toContain(
      "app-delete-before-tcc-reset",
    );
  });

  test("blocks a trash helper aimed at an .app", () => {
    expect(kinds("trash /Applications/Zoom.app")).toContain(
      "app-delete-before-tcc-reset",
    );
  });

  // The whole point of the guard is the ORDER, so a command that already does
  // the reset must pass. Blocking the correct sequence would teach people to
  // reach for the escape hatch reflexively, which is worse than no guard.
  test("allows the correct order in one command", () => {
    const cmd =
      '/usr/bin/tccutil reset All com.carriez.rustdesk && rm -rf /Applications/RustDesk.app';
    expect(kinds(cmd)).toEqual([]);
  });

  test("allows deleting something that is not an app bundle", () => {
    expect(kinds("rm -rf ~/Library/Caches/com.example.thing")).toEqual([]);
  });

  test("allows read-only inspection of an app bundle", () => {
    expect(kinds("ls -la /Applications/RustDesk.app/Contents/MacOS")).toEqual(
      [],
    );
    expect(
      kinds("codesign -dv --verbose=2 /Applications/RustDesk.app"),
    ).toEqual([]);
  });
});

describe("launchd target addressed by filename", () => {
  test("blocks a target carrying .plist", () => {
    expect(
      kinds("launchctl bootout system/com.teamviewer.teamviewer_service.plist"),
    ).toContain("launchd-target-is-filename");
  });

  test("blocks a target built from basename", () => {
    expect(
      kinds('launchctl bootout "system/$(basename "$f" .plist)"'),
    ).toContain("launchd-target-is-filename");
  });

  // A bare label is indistinguishable from a correct Label in a command string.
  // Guessing here would produce false positives on every correct invocation.
  test("allows a plain label target", () => {
    expect(kinds("launchctl bootout system/com.teamviewer.service")).toEqual(
      [],
    );
  });

  test("allows read-only launchctl verbs", () => {
    expect(kinds("launchctl list | grep teamviewer")).toEqual([]);
    expect(kinds("launchctl print system/com.example.job")).toEqual([]);
  });
});

describe("explanations", () => {
  test("name the escape hatch and the fix", () => {
    const text = explainTccOrderingViolations(
      findTccOrderingViolations("rm -rf /Applications/Foo.app"),
    );
    expect(text).toContain("TCC-ORDERING-OK");
    expect(text).toContain("tccutil reset All");
    // The guard must also warn that tccutil's exit code is not evidence,
    // otherwise someone follows the advice and still strands the grant.
    expect(text).toContain("exits 0");
  });

  test("launchd explanation shows the PlistBuddy resolution", () => {
    const text = explainTccOrderingViolations(
      findTccOrderingViolations(
        "launchctl bootout system/com.vendor.vendor_service.plist",
      ),
    );
    expect(text).toContain("Print :Label");
    expect(text).toContain("refusing to guess");
  });
});

describe("empty and irrelevant input", () => {
  test("empty command yields nothing", () => {
    expect(findTccOrderingViolations("")).toEqual([]);
    expect(findTccOrderingViolations("   ")).toEqual([]);
  });

  test("an unrelated command yields nothing", () => {
    expect(kinds("git status --short")).toEqual([]);
  });
});
