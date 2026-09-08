#!/usr/bin/env bun

/**
 * PreToolUse hook: Chrome remote-debugging launch guard.
 *
 * Blocks ONLY browser launches that provably cannot do what their author is asking for, plus one
 * launch shape that is a genuine security hole. It does not express an opinion about whether you
 * should be driving a browser at all — that judgement is the ladder in the spoke, and it is not
 * mechanically decidable from a command string.
 *
 * WHY THIS EXISTS. Since Chrome 136, `--remote-debugging-port` and `--remote-debugging-pipe` are
 * REFUSED when the browser is using its default user-data directory. This was deliberate hardening:
 * a non-default directory gets a different encryption key, so malware that attaches over CDP cannot
 * decrypt the real profile's cookies and passwords. The reason it deserves a hard block rather than
 * a docs entry is the FAILURE MODE — it does not look like a flag error. You get either
 * "DevTools remote debugging requires a non-default data directory", or, for an automation client,
 * a browser that starts, reports healthy, and then hangs on a blank page while the client waits for
 * a port that was never opened. That is a confident wrong answer, which is this repo's standing bar
 * for blocking (cf. pretooluse-headless-claude-p-guard.ts).
 *
 * Three violations, all deterministic:
 *   1. remote-debugging launch with NO --user-data-dir            -> dead on Chrome >= 136
 *   2. remote-debugging launch whose --user-data-dir IS the        -> same failure, just harder to
 *      platform default profile root                                  see
 *   3. --remote-debugging-address bound off loopback               -> exposes full browser control
 *                                                                     (read every cookie, drive any
 *                                                                     page) to the network
 *
 * DELIBERATELY NOT BLOCKED, because these are not launches and blocking them would be infuriating:
 * inspecting or killing an existing debug browser (`pkill -f remote-debugging-port=9222`,
 * `ps aux | grep ...`), or curling the CDP endpoint. A positive browser-launch signal is required
 * before any violation is reported, and inspector/terminator verbs veto the whole check.
 *
 * Knowledge SSoT (this file duplicates none of it):
 *   ~/.claude/browser-automation-CLAUDE.md
 * Upstream announcement:
 *   https://developer.chrome.com/blog/remote-debugging-port
 */

import {
	type EscapeHatchMarkerDetectionConfiguration,
	hasFileWideEscapeHatchMarkerInContent,
} from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import {
	allow,
	deny,
	parseStdinOrAllow,
	trackHookError,
} from "./pretooluse-helpers.ts";

/** Operator escape hatch. A >=10-character justification is mandatory. */
const CHROME_DEBUG_PORT_ESCAPE_HATCH: Pick<
	EscapeHatchMarkerDetectionConfiguration,
	| "markerNameTokenIncludingSuffix"
	| "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
	markerNameTokenIncludingSuffix: "CHROME-DEBUG-PORT-OK",
	requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

/** The remote-debugging switches that Chrome >= 136 gates on a non-default profile. */
const REMOTE_DEBUG_SWITCH = /--remote-debugging-(?:port|pipe)\b/;

/** `--user-data-dir` in either `=value` or space-separated form. */
const USER_DATA_DIR = /--user-data-dir(?:[=\s]|$)/;

/**
 * Platform default profile roots. Passing one of these to --user-data-dir is exactly as dead as
 * passing nothing, but reads as compliant, so it gets its own message.
 *
 * The trailing boundary must accept a CLOSING QUOTE, not just whitespace or end-of-string: these
 * paths contain a space ("Application Support"), so in practice they are always quoted, and a naive
 * `(?!\S)` therefore never matched the very case this check exists for. Caught by the test, not by
 * reading.
 *
 * A trailing `/` is deliberately NOT a boundary. `--user-data-dir=".../Google/Chrome/Something"` is
 * a DIFFERENT directory from the default root, so Chrome accepts it and remote debugging works.
 * Matching it would be a false positive.
 */
const PATH_END = String.raw`(?=["'\s]|$)`;
const DEFAULT_PROFILE_ROOTS = [
	new RegExp(`Library/Application Support/Google/Chrome${PATH_END}`), // macOS
	new RegExp(`Library/Application Support/Chromium${PATH_END}`), // macOS Chromium
	new RegExp(String.raw`\.config/google-chrome${PATH_END}`), // Linux
	new RegExp(String.raw`\.config/chromium${PATH_END}`), // Linux Chromium
	/AppData[\\/]Local[\\/]Google[\\/]Chrome[\\/]User Data/i, // Windows
];

/** Something in the command actually starts a browser. Without this we do not report anything. */
const BROWSER_LAUNCH_SIGNAL =
	/(Google Chrome(?: Canary| Beta| Dev)?(?:\.app)?|\bchrome\b|\bchromium\b|\bmsedge\b|\bbrave\b|\bthorium\b|playwright|puppeteer|open\s+-a)/i;

/**
 * Verbs that mean "look at" or "kill", never "launch". These veto the entire check: a command that
 * greps for the flag or kills a browser already carrying it is legitimate and common.
 */
const INSPECT_OR_TERMINATE =
	/(^|[;&|]\s*)(sudo\s+)?(pkill|pgrep|killall|kill|ps|grep|rg|ag|egrep|fgrep|lsof|echo|printf|cat|awk|sed|curl|wget|jq)\b/;

/** `--remote-debugging-address=<host>`, capturing the host. */
const REMOTE_DEBUG_ADDRESS =
	/--remote-debugging-address[=\s]+(["']?)([^\s"']+)\1/;
const LOOPBACK = /^(127\.0\.0\.1|localhost|::1|\[::1\])$/i;

export interface ChromeDebugViolation {
	readonly code:
		| "MISSING_USER_DATA_DIR"
		| "DEFAULT_USER_DATA_DIR"
		| "NON_LOOPBACK_DEBUG_ADDRESS";
	readonly detail: string;
}

export function findChromeDebugViolations(
	command: string,
): ChromeDebugViolation[] {
	const violations: ChromeDebugViolation[] = [];
	if (!command) return violations;

	// An inspect/kill pipeline is never a launch. Veto before anything else.
	if (INSPECT_OR_TERMINATE.test(command)) return violations;
	if (!BROWSER_LAUNCH_SIGNAL.test(command)) return violations;

	const address = command.match(REMOTE_DEBUG_ADDRESS);
	if (address && !LOOPBACK.test(address[2])) {
		violations.push({
			code: "NON_LOOPBACK_DEBUG_ADDRESS",
			detail: address[2],
		});
	}

	if (!REMOTE_DEBUG_SWITCH.test(command)) return violations;

	if (!USER_DATA_DIR.test(command)) {
		violations.push({ code: "MISSING_USER_DATA_DIR", detail: "" });
		return violations;
	}

	const defaulted = DEFAULT_PROFILE_ROOTS.find((re) => re.test(command));
	if (defaulted) {
		violations.push({
			code: "DEFAULT_USER_DATA_DIR",
			detail: (command.match(defaulted) || [""])[0],
		});
	}

	return violations;
}

export function explainChromeDebugViolations(
	violations: ChromeDebugViolation[],
): string {
	const lines: string[] = [];

	for (const v of violations) {
		if (v.code === "MISSING_USER_DATA_DIR") {
			lines.push(
				"This launch passes a remote-debugging switch with NO --user-data-dir. On Chrome >= 136 " +
					"that switch is REFUSED on the default profile, so the port never opens. It does not " +
					"fail loudly: an automation client typically connects, reports healthy, and hangs on a " +
					"blank page.\n\n" +
					"Add a non-default profile directory, and fully quit Chrome first -- relaunching while " +
					"an instance is alive just opens a tab in it and silently drops every flag:\n\n" +
					"  osascript -e 'quit app \"Google Chrome\"'\n" +
					'  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \\\n' +
					"    --remote-debugging-port=9222 \\\n" +
					'    --user-data-dir="$HOME/.chrome-debug" &\n' +
					"  curl -s http://127.0.0.1:9222/json/version   # JSON == live\n\n" +
					"That is a FRESH profile: no cookies, no logins, no extensions. Sign in once by hand in " +
					"that window, or copy Local State plus the one profile dir you need with Chrome quit.",
			);
		} else if (v.code === "DEFAULT_USER_DATA_DIR") {
			lines.push(
				`--user-data-dir points at the platform DEFAULT profile root (matched: ${v.detail}). ` +
					"Chrome >= 136 gates remote debugging on the directory being non-default, so this fails " +
					"exactly like passing no --user-data-dir at all -- it just reads as compliant. Point it " +
					'somewhere else, e.g. --user-data-dir="$HOME/.chrome-debug".',
			);
		} else {
			lines.push(
				`--remote-debugging-address is bound to ${v.detail}, which is not loopback. That exposes ` +
					"FULL browser control to the network: anyone who can reach the port can drive any page " +
					"and read every cookie in the profile. Bind 127.0.0.1 and tunnel if you need remote " +
					"access.",
			);
		}
	}

	lines.push(
		"Rationale and the full ladder (no browser > hermetic launch > attach real Chrome): " +
			"~/.claude/browser-automation-CLAUDE.md\n" +
			"Upstream: https://developer.chrome.com/blog/remote-debugging-port\n" +
			"Override with CHROME-DEBUG-PORT-OK: <>=10-character reason>",
	);

	return lines.join("\n\n");
}

async function main(): Promise<void> {
	const input = await parseStdinOrAllow("CHROME-DEBUG-PORT-GUARD");
	if (!input) return;

	const { tool_name, tool_input = {} } = input;
	if (tool_name !== "Bash") {
		allow();
		return;
	}

	const command = tool_input.command || "";
	if (
		hasFileWideEscapeHatchMarkerInContent(
			command,
			CHROME_DEBUG_PORT_ESCAPE_HATCH,
		)
	) {
		allow();
		return;
	}

	const violations = findChromeDebugViolations(command);
	if (violations.length === 0) {
		allow();
		return;
	}

	deny(explainChromeDebugViolations(violations));
}

main().catch((err) => {
	// Fail OPEN. A guard that blocks work when its own logic throws is worse than the bug it prevents.
	trackHookError(
		"pretooluse-chrome-debug-port-guard",
		err instanceof Error ? err.message : String(err),
	);
	allow();
});
