#!/usr/bin/env bun
/**
 * PreToolUse hook: Native Binary Guard
 *
 * Prevents creating bash scripts for macOS launchd automation.
 * All launchd services MUST use compiled native binaries (Swift preferred)
 * so they show with proper names in System Settings > Login Items.
 *
 * Using /bin/bash in launchd plists shows a generic "bash" entry in Login Items,
 * which is confusing and looks like malware. Compiled Swift binaries show their
 * actual executable name (e.g., "calendar-announce").
 *
 * PERFORMANCE: This hook uses a raw-stdin fast path. It reads stdin once as a
 * string and checks for launchd-related keywords BEFORE JSON parsing. For 99%+
 * of Write/Edit calls (non-launchd), it exits in <1ms without parsing JSON.
 *
 * Detections (only when file_path matches launchd patterns):
 * 1. Write: .sh/.bash files under ~/.claude/automation/ or ~/Library/LaunchAgents/
 * 2. Write: .plist files with /bin/bash or /bin/sh in ProgramArguments
 * 3. Write: .plist files with .sh script paths in ProgramArguments
 *
 * Escape hatch: # BASH-LAUNCHD-OK comment in content
 */

const HOOK_NAME = "NATIVE-BINARY-GUARD";

// Fast-path keywords — if stdin doesn't contain ANY of these, skip entirely.
// This avoids JSON parsing for 99%+ of Write/Edit calls.
const FAST_PATH_KEYWORDS = [
  ".plist",
  ".sh",
  ".bash",
  "LaunchAgent",
  "LaunchDaemon",
  "automation/",
];

const ESCAPE_HATCH = /[#/]\s*BASH-LAUNCHD-OK/i;

// Launchd-related directories
const LAUNCHD_DIRS = [
  "/.claude/automation/",
  "/Library/LaunchAgents/",
  "/Library/LaunchDaemons/",
];

function isLaunchdPath(filePath: string): boolean {
  return LAUNCHD_DIRS.some((dir) => filePath.includes(dir));
}

function outputAllow(): void {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
      },
    })
  );
}

function outputDeny(reason: string): void {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    })
  );
}

async function main() {
  // Read stdin as raw string ONCE
  let raw: string;
  try {
    raw = await Bun.stdin.text();
  } catch {
    outputAllow();
    return;
  }

  // FAST PATH: If stdin doesn't contain any launchd-related keywords,
  // skip JSON parsing entirely. This makes the hook effectively free
  // for normal Write/Edit operations (~0ms overhead).
  const hasKeyword = FAST_PATH_KEYWORDS.some((kw) => raw.includes(kw));
  if (!hasKeyword) {
    outputAllow();
    return;
  }

  // Slow path: parse JSON only for launchd-related files
  let input: {
    tool_name: string;
    tool_input: { file_path?: string; content?: string; new_string?: string };
  };
  try {
    input = JSON.parse(raw);
  } catch {
    outputAllow(); // Fail-open
    return;
  }

  const { tool_name, tool_input = {} } = input;

  if (tool_name !== "Write" && tool_name !== "Edit") {
    outputAllow();
    return;
  }

  const filePath = (tool_input.file_path as string) || "";

  // Only check files in launchd-related directories
  if (!isLaunchdPath(filePath)) {
    outputAllow();
    return;
  }

  const content =
    (tool_input.content as string) || (tool_input.new_string as string) || "";

  // Escape hatch
  if (ESCAPE_HATCH.test(content)) {
    outputAllow();
    return;
  }

  // Detection 1: Shell scripts in launchd directories
  const isShell =
    filePath.endsWith(".sh") ||
    filePath.endsWith(".bash") ||
    /^#!\s*\/(?:usr\/)?bin\/(?:ba)?sh/m.test(content);

  if (isShell) {
    outputDeny(
      `[${HOOK_NAME}] Shell scripts are not allowed for macOS launchd automation.\n\n` +
        `File: ${filePath}\n\n` +
        `macOS launchd services MUST use compiled native binaries (Swift preferred) ` +
        `so they show with proper names in System Settings > Login Items.\n` +
        `Using /bin/bash shows a generic "bash" entry which looks like malware.\n\n` +
        `FIX: Write the logic in Swift and compile with:\n` +
        `  swiftc -O -framework EventKit -o binary-name Source.swift\n\n` +
        `Reference: ~/.claude/automation/calendar-alarm-sweep/swift-cli/ for examples.\n` +
        `Escape hatch: Add "# BASH-LAUNCHD-OK" comment if bash is truly required.`
    );
    return;
  }

  // Detection 2: Plist files referencing bash
  if (filePath.endsWith(".plist")) {
    const hasBashRef =
      /<string>\/(?:usr\/)?bin\/(?:ba)?sh<\/string>/i.test(content) ||
      /<string>[^<]*\.sh<\/string>/i.test(content);

    if (hasBashRef) {
      outputDeny(
        `[${HOOK_NAME}] Launchd plist must not reference /bin/bash or .sh scripts.\n\n` +
          `File: ${filePath}\n\n` +
          `ProgramArguments must point to a compiled native binary, not a shell script.\n` +
          `Using /bin/bash in ProgramArguments shows "bash" in Login Items.\n\n` +
          `FIX: Compile your script as a Swift binary and reference it directly:\n` +
          `  <string>/path/to/compiled-binary</string>\n\n` +
          `Reference: ~/.claude/automation/calendar-alarm-sweep/swift-cli/ for examples.\n` +
          `Escape hatch: Add "<!-- BASH-LAUNCHD-OK -->" comment in plist.`
      );
      return;
    }
  }

  outputAllow();
}

main().catch((err) => {
  console.error(`[${HOOK_NAME}] Unhandled error: ${err}`);
  outputAllow(); // Fail-open
});
