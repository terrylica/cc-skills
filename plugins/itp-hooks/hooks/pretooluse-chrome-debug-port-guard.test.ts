/**
 * Tests for pretooluse-chrome-debug-port-guard.
 *
 * These SPAWN THE REAL HOOK and speak the real stdin/stdout protocol, rather than re-asserting the
 * hook's own regexes against fixture strings. A test that only re-runs the pattern it copied from
 * the implementation proves the pattern equals itself; it cannot catch a wiring mistake (wrong
 * tool_name gate, escape hatch checked in the wrong order, a throw that fails open). Precedent:
 * pretooluse-github-hard-wrap-guard.test.ts.
 *
 * The allow-cases matter more than the deny-cases here. A guard on a flag that also appears in
 * `pkill`, `ps | grep` and `curl` invocations is one false positive away from being disabled, and a
 * disabled guard is worse than no guard.
 */

import { describe, expect, it } from "bun:test";

const HOOK_PATH = new URL(
	"./pretooluse-chrome-debug-port-guard.ts",
	import.meta.url,
).pathname;

const CHROME = '"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"';

async function runHook(
	command: string,
	toolName = "Bash",
): Promise<{
	decision: string;
	reason: string;
	stderr: string;
	exitCode: number;
}> {
	const proc = Bun.spawn(["bun", HOOK_PATH], {
		stdin: "pipe",
		stdout: "pipe",
		stderr: "pipe",
	});
	proc.stdin.write(
		JSON.stringify({ tool_name: toolName, tool_input: { command } }),
	);
	await proc.stdin.end();

	const [stdout, stderr, exitCode] = await Promise.all([
		new Response(proc.stdout).text(),
		new Response(proc.stderr).text(),
		proc.exited,
	]);

	const parsed = JSON.parse(stdout);
	return {
		decision: parsed.hookSpecificOutput.permissionDecision,
		reason: parsed.hookSpecificOutput.permissionDecisionReason ?? "",
		stderr,
		exitCode,
	};
}

describe("blocks launches that provably cannot work", () => {
	it("denies a remote-debugging launch with no --user-data-dir", async () => {
		const r = await runHook(`${CHROME} --remote-debugging-port=9222 &`);
		expect(r.decision).toBe("deny");
		expect(r.reason).toContain("--user-data-dir");
	});

	it("denies --remote-debugging-pipe too, not just --remote-debugging-port", async () => {
		const r = await runHook(`${CHROME} --remote-debugging-pipe`);
		expect(r.decision).toBe("deny");
	});

	it("denies a --user-data-dir pointing at the macOS default profile root", async () => {
		const r = await runHook(
			`${CHROME} --remote-debugging-port=9222 ` +
				`--user-data-dir="$HOME/Library/Application Support/Google/Chrome"`,
		);
		expect(r.decision).toBe("deny");
		expect(r.reason).toContain("DEFAULT profile root");
	});

	it("denies the Linux default profile root as well", async () => {
		const r = await runHook(
			"chromium --remote-debugging-port=9222 --user-data-dir=$HOME/.config/chromium",
		);
		expect(r.decision).toBe("deny");
	});

	it("denies a debug address bound off loopback", async () => {
		const r = await runHook(
			`${CHROME} --remote-debugging-port=9222 --remote-debugging-address=0.0.0.0 ` +
				'--user-data-dir="$HOME/.chrome-debug"',
		);
		expect(r.decision).toBe("deny");
		expect(r.reason).toContain("not loopback");
	});
});

describe("allows everything that is not a broken launch", () => {
	it("allows the correct launch shape", async () => {
		const r = await runHook(
			`${CHROME} --remote-debugging-port=9222 --user-data-dir="$HOME/.chrome-debug" &`,
		);
		expect(r.decision).toBe("allow");
	});

	it("allows an explicit loopback debug address", async () => {
		const r = await runHook(
			`${CHROME} --remote-debugging-port=9222 --remote-debugging-address=127.0.0.1 ` +
				'--user-data-dir="$HOME/.chrome-debug"',
		);
		expect(r.decision).toBe("allow");
	});

	// The regression that would get this guard switched off.
	it("allows pkill against an existing debug browser", async () => {
		const r = await runHook('pkill -f "remote-debugging-port=9222"');
		expect(r.decision).toBe("allow");
	});

	it("allows ps|grep inspection of the flag", async () => {
		const r = await runHook(
			"ps aux | grep -i 'remote-debugging-port' | grep -v grep",
		);
		expect(r.decision).toBe("allow");
	});

	it("allows curling the CDP endpoint", async () => {
		const r = await runHook("curl -s http://127.0.0.1:9222/json/version");
		expect(r.decision).toBe("allow");
	});

	it("allows a command with no browser launch signal at all", async () => {
		const r = await runHook("echo --remote-debugging-port=9222 >> notes.txt");
		expect(r.decision).toBe("allow");
	});

	it("allows unrelated commands", async () => {
		const r = await runHook("git status --short");
		expect(r.decision).toBe("allow");
	});

	it("allows non-Bash tools outright", async () => {
		const r = await runHook(`${CHROME} --remote-debugging-port=9222`, "Write");
		expect(r.decision).toBe("allow");
	});
});

describe("escape hatch", () => {
	it("honours the marker when a >=10-character reason is given", async () => {
		const r = await runHook(
			`${CHROME} --remote-debugging-port=9222 ` +
				"# CHROME-DEBUG-PORT-OK: reproducing the Chrome 135 behaviour deliberately",
		);
		expect(r.decision).toBe("allow");
	});

	it("still denies when the reason is too short to be a reason", async () => {
		const r = await runHook(
			`${CHROME} --remote-debugging-port=9222 # CHROME-DEBUG-PORT-OK: no`,
		);
		expect(r.decision).toBe("deny");
	});

	it("still denies a bare marker with no reason at all", async () => {
		const r = await runHook(
			`${CHROME} --remote-debugging-port=9222 # CHROME-DEBUG-PORT-OK`,
		);
		expect(r.decision).toBe("deny");
	});
});

describe("hook protocol hygiene", () => {
	it("exits 0 and writes nothing to stderr even when denying", async () => {
		// This repo's contract: hooks must NEVER write to stderr on exit 0, and a Bash-matching guard
		// uses the ordinary single-signal deny (stdout JSON only). The belt-and-suspenders
		// stdout+stderr+exit-2 form exists solely for Write|Edit, where deny was reported ignored.
		const r = await runHook(`${CHROME} --remote-debugging-port=9222`);
		expect(r.decision).toBe("deny");
		expect(r.exitCode).toBe(0);
		expect(r.stderr).toBe("");
	});
});
