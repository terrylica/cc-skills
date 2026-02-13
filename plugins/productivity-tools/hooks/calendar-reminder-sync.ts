#!/usr/bin/env bun
/**
 * PostToolUse hook: Calendar ↔ Reminders Sync
 *
 * HARD-LEARNED TRUTHS (2026-02-12) - referenced from:
 *   Skill: skills/calendar-event-manager/SKILL.md
 *   Sound ref: skills/calendar-event-manager/references/sound-reference.md
 *
 * RULES (NON-NEGOTIABLE):
 *   1. Calendar + Reminders ALWAYS created together (never one without the other)
 *   2. Use `sound alarm` with `sound name`, NOT `display alarm` (display = silent banner)
 *   3. ONLY long sounds >= 1.4s: Funk(2.16), Glass(1.65), Pop(1.63), Sosumi(1.54),
 *      Ping(1.50), Submarine(1.49), Blow(1.40)
 *      BANNED: Hero, Basso, Bottle, Purr, Frog, Morse, Tink (all < 1.4s)
 *   4. Multiple tiered alarms mandatory (6 tiers with escalating sounds)
 *   5. Each tier uses a DIFFERENT sound so user knows urgency by sound alone
 *
 * DETECTION:
 *   - Fires on PostToolUse for Bash commands containing osascript + "make new event"
 *   - Checks if sound alarms are present; if missing, warns Claude to fix
 *   - Auto-creates 3 paired Reminders (TOMORROW, TODAY morning, due-time)
 *
 * WHAT THIS HOOK DOES:
 *   A) If Calendar event was created WITHOUT sound alarms → warn Claude to recreate with sound alarms
 *   B) If Calendar event was created WITH sound alarms → auto-create paired Reminders
 *   C) If Calendar event used BANNED short sounds → warn Claude to use only approved sounds
 */

// ============================================================================
// CONSTANTS - Sound Policy
// ============================================================================

const APPROVED_SOUNDS = new Set([
  "Funk",      // 2.16s - At event time (loudest)
  "Glass",     // 1.65s - 1 hour before
  "Pop",       // 1.63s - Morning-of / 3 hrs before
  "Sosumi",    // 1.54s - Day-before
  "Ping",      // 1.50s - 30 min before
  "Submarine", // 1.49s - Alternative
  "Blow",      // 1.40s - Gentle early reminder
]);

const BANNED_SOUNDS = new Set([
  "Hero",   // 1.06s - too short
  "Basso",  // 0.77s - too short
  "Bottle", // 0.77s - too short
  "Purr",   // 0.76s - too short
  "Frog",   // 0.72s - too short
  "Morse",  // 0.70s - too short
  "Tink",   // 0.56s - far too short
]);

// ============================================================================
// TYPES
// ============================================================================

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    command?: string;
    [key: string]: unknown;
  };
  tool_response?: string;
  cwd?: string;
}

interface HookResult {
  exitCode: number;
  stdout?: string;
  stderr?: string;
}

interface EventDetails {
  summary: string;
  startDate: string;
  location: string;
  notes: string;
}

// ============================================================================
// EXTRACTION
// ============================================================================

function extractEventDetails(command: string): EventDetails | null {
  const summaryMatch = command.match(/summary:\s*"([^"]+)"/);
  const startDateMatch = command.match(/start date:\s*date\s*"([^"]+)"/);
  const locationMatch = command.match(/location:\s*"([^"]+)"/);
  const notesMatch = command.match(/description:\s*"([^"]+)"/);

  if (!summaryMatch || !startDateMatch) return null;

  return {
    summary: summaryMatch[1],
    startDate: startDateMatch[1],
    location: locationMatch?.[1] ?? "",
    notes: notesMatch?.[1] ?? "",
  };
}

// ============================================================================
// VALIDATION
// ============================================================================

function checkSoundAlarms(command: string): {
  hasSoundAlarms: boolean;
  hasDisplayAlarmOnly: boolean;
  usedBannedSounds: string[];
  soundCount: number;
} {
  const soundAlarmPattern = /make new sound alarm/g;
  const displayAlarmPattern = /make new display alarm/g;
  const soundNamePattern = /sound name:\s*"([^"]+)"/g;

  const soundAlarms = command.match(soundAlarmPattern) ?? [];
  const displayAlarms = command.match(displayAlarmPattern) ?? [];

  const usedBannedSounds: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = soundNamePattern.exec(command)) !== null) {
    if (BANNED_SOUNDS.has(match[1])) {
      usedBannedSounds.push(match[1]);
    }
  }

  return {
    hasSoundAlarms: soundAlarms.length > 0,
    hasDisplayAlarmOnly: displayAlarms.length > 0 && soundAlarms.length === 0,
    usedBannedSounds,
    soundCount: soundAlarms.length,
  };
}

// ============================================================================
// REMINDER CREATION
// ============================================================================

function buildReminderScript(event: EventDetails): string {
  const esc = (s: string) => s.replace(/'/g, "'\\''");

  return `osascript -e '
set dueDate to date "${esc(event.startDate)}"

tell application "Reminders"
    set defaultList to default list
    make new reminder in defaultList with properties {name:"${esc(event.summary)}", due date:dueDate, body:"${esc(event.location)}${event.location && event.notes ? "\\n" : ""}${esc(event.notes)}"}
end tell

set earlyDate to date "${esc(event.startDate)}"
set earlyDate to earlyDate - 1 * days

tell application "Reminders"
    set defaultList to default list
    make new reminder in defaultList with properties {name:"TOMORROW: ${esc(event.summary)}", due date:earlyDate, body:"Event tomorrow! ${esc(event.location)}"}
end tell

set morningDate to date "${esc(event.startDate)}"
set time of morningDate to 9 * hours

tell application "Reminders"
    set defaultList to default list
    make new reminder in defaultList with properties {name:"TODAY: ${esc(event.summary)}", due date:morningDate, body:"Today at ${esc(event.startDate)}! ${esc(event.location)}"}
end tell

return "Created 3 reminders for: ${esc(event.summary)}"
'`;
}

// ============================================================================
// MAIN LOGIC
// ============================================================================

async function runHook(): Promise<HookResult> {
  const stdin = await Bun.stdin.text();
  if (!stdin.trim()) return { exitCode: 0 };

  let input: PostToolUseInput;
  try {
    input = JSON.parse(stdin);
  } catch {
    return { exitCode: 0 };
  }

  if (input.tool_name !== "Bash") return { exitCode: 0 };

  const command = input.tool_input?.command ?? "";

  // Only trigger on Calendar event creation via osascript
  if (!command.includes("osascript") || !command.includes("make new event")) {
    return { exitCode: 0 };
  }

  // Skip TEST events
  if (command.includes("TEST")) {
    return { exitCode: 0 };
  }

  const event = extractEventDetails(command);
  if (!event) return { exitCode: 0 };

  // ---- VALIDATION: Check sound alarm compliance ----

  const soundCheck = checkSoundAlarms(command);
  const warnings: string[] = [];

  // Rule 2: Must use sound alarm, not display alarm
  if (soundCheck.hasDisplayAlarmOnly) {
    warnings.push(
      "VIOLATION: Used `display alarm` instead of `sound alarm`. Display alarms are SILENT banners. " +
      "Recreate using: make new sound alarm at end of sound alarms with properties {trigger interval:-60, sound name:\"Glass\"}"
    );
  }

  // Rule 4: Must have multiple alarms (minimum 5 tiers recommended)
  if (soundCheck.hasSoundAlarms && soundCheck.soundCount < 3) {
    warnings.push(
      `WARNING: Only ${soundCheck.soundCount} sound alarm(s). Events need 5-6 tiered alarms: ` +
      "Blow(-1440min), Pop(-180min), Glass(-60min), Ping(-30min), Funk(0min). " +
      "Add more alarms so the event isn't missed."
    );
  }

  // Rule 3: No banned short sounds
  if (soundCheck.usedBannedSounds.length > 0) {
    warnings.push(
      `VIOLATION: Used BANNED short sounds: ${soundCheck.usedBannedSounds.join(", ")}. ` +
      "These are < 1.4 seconds and get ignored. ONLY use: Funk, Glass, Pop, Sosumi, Ping, Submarine, Blow."
    );
  }

  // If there are warnings, report them WITHOUT creating reminders (let Claude fix first)
  if (warnings.length > 0) {
    return {
      exitCode: 0,
      stdout: JSON.stringify({
        decision: "block",
        reason: `[CALENDAR-SYNC] Calendar event "${event.summary}" has alarm issues:\n\n` +
          warnings.map((w, i) => `  ${i + 1}. ${w}`).join("\n") +
          "\n\nFix the Calendar event alarms, then Reminders will be auto-created on the next successful creation." +
          "\n\nReference: skills/calendar-event-manager/SKILL.md (Section: CRITICAL RULES)",
      }),
    };
  }

  // ---- RULE 1: Auto-create paired Reminders ----

  const script = buildReminderScript(event);
  try {
    const proc = Bun.spawn(["bash", "-c", script], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const exitCode = await proc.exited;
    const stderr = await new Response(proc.stderr).text();

    if (exitCode === 0) {
      return {
        exitCode: 0,
        stdout: JSON.stringify({
          decision: "block",
          reason:
            `[CALENDAR-SYNC] Auto-created 3 paired Reminders for "${event.summary}":\n` +
            "  1. TOMORROW reminder (1 day before)\n" +
            "  2. TODAY reminder (morning of, 9 AM)\n" +
            "  3. Due-time reminder (at event start)\n" +
            "All sync to iPhone/iPad via iCloud.",
        }),
      };
    } else {
      return {
        exitCode: 0,
        stderr: `[CALENDAR-SYNC] Failed to create reminders: ${stderr}`,
      };
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      exitCode: 0,
      stderr: `[CALENDAR-SYNC] Error: ${msg}`,
    };
  }
}

// ============================================================================
// ENTRY POINT
// ============================================================================

async function main(): Promise<never> {
  let result: HookResult;
  try {
    result = await runHook();
  } catch (err: unknown) {
    console.error("[CALENDAR-SYNC] Unexpected error:");
    if (err instanceof Error) {
      console.error(`  ${err.message}`);
    }
    return process.exit(0);
  }

  if (result.stderr) console.error(result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
