#!/usr/bin/env bun
/**
 * Tests for posttooluse-sigpipe-pipefail-reminder.ts
 *
 * The detector has its own suite; these pin the HOOK layer — net-new counting,
 * fragment scanning, tool-name gating and the message.
 *
 * The net-new tests matter most. A reminder that fires whenever an edit happens
 * to touch a file containing a pre-existing site would fire on almost every edit
 * to the source repo's 26 site-bearing scripts, which is the noise profile that
 * gets a hook turned off.
 */

import { describe, it, expect } from "bun:test";
import {
  detectNetNewSigpipeSites,
  buildReminder,
} from "./posttooluse-sigpipe-pipefail-reminder.ts";

const SH = "/repo/scripts/thing.sh";

describe("tool gating", () => {
  it("ignores tools that are not Write/Edit/MultiEdit", () => {
    expect(
      detectNetNewSigpipeSites({
        tool_name: "Bash",
        tool_input: { file_path: SH, content: "set -euo pipefail\na | grep -q b\n" },
      }),
    ).toHaveLength(0);
  });

  it("ignores an input with no file_path", () => {
    expect(detectNetNewSigpipeSites({ tool_name: "Write", tool_input: {} })).toHaveLength(0);
  });
});

describe("Write", () => {
  it("fires on a new shell script that introduces a site", () => {
    const sites = detectNetNewSigpipeSites({
      tool_name: "Write",
      tool_input: {
        file_path: SH,
        content: "#!/usr/bin/env bash\nset -euo pipefail\nmoon query tasks | grep -q foo\n",
      },
    });
    expect(sites).toHaveLength(1);
    expect(sites[0]?.reader).toBe("grep -q");
  });

  it("stays quiet when the script does not enable pipefail", () => {
    expect(
      detectNetNewSigpipeSites({
        tool_name: "Write",
        tool_input: {
          file_path: SH,
          content: "#!/usr/bin/env bash\nset -eu\nmoon query tasks | grep -q foo\n",
        },
      }),
    ).toHaveLength(0);
  });

  it("stays quiet on a non-shell file", () => {
    expect(
      detectNetNewSigpipeSites({
        tool_name: "Write",
        tool_input: { file_path: "/repo/notes.md", content: "set -euo pipefail\na | grep -q b\n" },
      }),
    ).toHaveLength(0);
  });
});

describe("Edit — net-new only", () => {
  it("fires when the edit ADDS a site", () => {
    const sites = detectNetNewSigpipeSites({
      tool_name: "Edit",
      tool_input: { file_path: SH, old_string: "echo hi\n", new_string: "producer | head -1\n" },
    });
    expect(sites).toHaveLength(1);
  });

  it("stays quiet when the site already existed in old_string", () => {
    expect(
      detectNetNewSigpipeSites({
        tool_name: "Edit",
        tool_input: {
          file_path: SH,
          old_string: "producer | head -1\n",
          new_string: "producer | head -1  # reworded comment\n",
        },
      }),
    ).toHaveLength(0);
  });

  it("stays quiet when an edit REMOVES a site", () => {
    expect(
      detectNetNewSigpipeSites({
        tool_name: "Edit",
        tool_input: {
          file_path: SH,
          old_string: "producer | head -1\n",
          new_string: "out=$(producer)\n",
        },
      }),
    ).toHaveLength(0);
  });

  it("fires on the SECOND site when an edit goes from one to two", () => {
    const sites = detectNetNewSigpipeSites({
      tool_name: "Edit",
      tool_input: {
        file_path: SH,
        old_string: "a | head -1\n",
        new_string: "a | head -1\nb | grep -q x\n",
      },
    });
    expect(sites).toHaveLength(1);
  });

  it("honours SIGPIPE-OK inside the fragment", () => {
    expect(
      detectNetNewSigpipeSites({
        tool_name: "Edit",
        tool_input: {
          file_path: SH,
          old_string: "echo hi\n",
          new_string: "producer | head -1  # SIGPIPE-OK: status discarded\n",
        },
      }),
    ).toHaveLength(0);
  });

  it("scans an extensionless git hook", () => {
    const sites = detectNetNewSigpipeSites({
      tool_name: "Edit",
      tool_input: {
        file_path: "/repo/deploy/git-hooks/pre-push",
        old_string: "echo hi\n",
        new_string: "moon query tasks | grep -q x\n",
      },
    });
    expect(sites).toHaveLength(1);
  });
});

describe("MultiEdit", () => {
  it("accumulates net-new sites across fragments", () => {
    const sites = detectNetNewSigpipeSites({
      tool_name: "MultiEdit",
      tool_input: {
        file_path: SH,
        edits: [
          { old_string: "echo a\n", new_string: "p1 | head -1\n" },
          { old_string: "echo b\n", new_string: "p2 | grep -q x\n" },
          { old_string: "p3 | head -1\n", new_string: "p3 | head -1\n" },
        ],
      },
    });
    expect(sites).toHaveLength(2);
  });
});

describe("reminder text", () => {
  it("names the producer and the reader, and offers the drain-based fix first", () => {
    const msg = buildReminder([
      { lineNumber: 3, reader: "head", producer: "sort -rn", statement: "x | sort -rn | head -1" },
    ]);
    expect(msg).toContain("sort -rn | head");
    expect(msg).toContain("SIGPIPE-PIPEFAIL");
    expect(msg).toContain("awk 'NR<=5'");
    expect(msg).toContain("SIGPIPE-OK");
    expect(msg).not.toContain("+1 more");
  });

  it("counts the remainder when several sites are introduced at once", () => {
    const msg = buildReminder([
      { lineNumber: 3, reader: "head", producer: "a", statement: "a | head" },
      { lineNumber: 4, reader: "grep -q", producer: "b", statement: "b | grep -q x" },
    ]);
    expect(msg).toContain("+1 more");
  });
});
