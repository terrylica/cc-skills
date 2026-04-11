#!/usr/bin/env bun
/**
 * PreToolUse:Bash — .pth contamination guard for Python deploys
 *
 * Universal hook (project-agnostic) that prevents .pth file contamination
 * across ANY Python project deployed via SSH or locally.
 *
 * Rules:
 * 1. `maturin develop` on remote hosts → BLOCK (use `maturin build` + wheel)
 * 2. `rsync ... site-packages` → ASK (warn about .pth creation)
 * 3. `pip install` from project dir on remote → ASK (install from /tmp/)
 * 4. Remote `pip install` (non-wheel) → ASK with .pth verification command
 *
 * Escape hatch: # PTH-OK
 *
 * Background: `maturin develop` and editable installs create .pth files in
 * site-packages that redirect imports to source directories. These files
 * survive venv swaps and `rm`, causing stale code to load silently.
 * The safe pattern is always: build wheel → copy to /tmp/ → install from wheel.
 */

import {
	allow,
	ask,
	deny,
	parseStdinOrAllow,
	trackHookError,
} from "./pretooluse-helpers.ts";

const FAST_PATH_KEYWORDS = ["maturin", "rsync", "pip", "site-packages"];

// SSH flags that take a mandatory argument (-p 22, -i keyfile, -o Option, etc.)
const SSH_FLAGS_WITH_ARG = new Set("bcDEeFIiJLlmOopQRSWw".split(""));

/** Extract remote host from SSH command, or null if local/no remote cmd. */
function extractRemoteHost(command: string): string | null {
	const afterSsh = command.match(/\bssh\s+(.*)/);
	if (!afterSsh) return null;
	const tokens = afterSsh[1].split(/\s+/);
	let i = 0;
	while (i < tokens.length) {
		const tok = tokens[i];
		if (tok === "--") {
			i++;
			break;
		}
		if (tok.startsWith("-") && tok.length >= 2) {
			const flagChar = tok[1];
			if (SSH_FLAGS_WITH_ARG.has(flagChar)) {
				i += tok.length === 2 ? 2 : 1; // -p 22 vs -p22
			} else {
				i += 1; // No-arg flag: -t, -v, -N
			}
		} else {
			break;
		}
	}
	if (i >= tokens.length) return null;
	const host = tokens[i];
	if (!host || host.startsWith("-")) return null;
	if (i + 1 >= tokens.length) return null; // No remote command
	return host;
}

/** Detect project-dir install: `pip install .`, `pip install -e .`, not from /tmp/.
 * Excludes flag arguments (starting with `-`) to avoid false positives like
 * `pip install --force-reinstall ... /tmp/x.whl`.
 */
function isProjectDirInstall(command: string): boolean {
	return /\bpip\s+install\s+(?:-e\s+)?(?:\.(?:\s|$|;|&&|\|)|(?!-)(?!\/tmp\/)[\w/.~][\w/.~-]*(?:\s|$|;|&&|\|))/i.test(
		command,
	);
}

/** Rule 1: maturin develop on remote → BLOCK */
function checkMaturinDevelopRemote(command: string): string | null {
	if (!/\bmaturin\s+develop\b/i.test(command)) return null;
	const host = extractRemoteHost(command);
	if (!host) return null; // Local is fine

	return `[PTH-GUARD] BLOCKED: \`maturin develop\` on remote host '${host}'

\`maturin develop\` creates an editable .pth file that shadows the real package,
survives venv rebuilds and \`rm\`, and causes import failures when source diverges.

USE INSTEAD:
  maturin build --release
  scp target/wheels/*.whl ${host}:/tmp/
  ssh ${host} 'uv pip install /tmp/*.whl --force-reinstall'

Add \`# PTH-OK\` to override (dev-only).`;
}

/** Rule 2: rsync to site-packages → ASK */
function checkRsyncSitePackages(command: string): string | null {
	if (!/\brsync\b/i.test(command) || !/site-packages/i.test(command))
		return null;

	return `[PTH-GUARD] rsync to site-packages detected

rsync into site-packages can create or preserve .pth files that shadow real
package installs. After this operation, verify:
  python -c "import site, glob; print(glob.glob(site.getsitepackages()[0] + '/*.pth'))"

If any .pth files exist for your package, remove them.
Add \`# PTH-OK\` to suppress.`;
}

/** Rule 3: pip install from project dir on remote → ASK */
function checkRemoteProjectDirInstall(command: string): string | null {
	if (!isProjectDirInstall(command)) return null;
	const host = extractRemoteHost(command);
	if (!host) return null;

	return `[PTH-GUARD] Installing from project directory on remote host '${host}'

This can create editable .pth files if pyproject.toml has [build-system].

SAFER PATTERN:
  1. Build wheel locally:  maturin build --release  (or: uv build)
  2. Copy to remote:       scp dist/*.whl ${host}:/tmp/
  3. Install from /tmp/:   ssh ${host} 'uv pip install /tmp/*.whl --force-reinstall'

Add \`# PTH-OK\` to suppress.`;
}

/** Rule 4: remote pip install (non-wheel, non-project-dir) → ASK with verify cmd */
function checkRemotePipInstall(command: string): string | null {
	if (!/\b(uv\s+pip\s+install|pip\s+install|pip3\s+install)\b/i.test(command))
		return null;
	const host = extractRemoteHost(command);
	if (!host) return null;
	if (isProjectDirInstall(command)) return null; // Caught by Rule 3
	if (/\/tmp\/.*\.whl\b/i.test(command)) return null; // Safe wheel pattern

	const verifyCmd =
		`ssh ${host} 'python3 -c "import site, glob; f=glob.glob(site.getsitepackages()[0]+` +
		"'/*.pth'); print(" +
		"'CLEAN' if not f else 'CONTAMINATED: '+str(f))" +
		`"'`;
	return `[PTH-GUARD] Remote pip install on '${host}' — verify no .pth contamination

After install, run:
  ${verifyCmd}

If contaminated: rm the .pth, rm .dist-info, reinstall from wheel.
Add \`# PTH-OK\` to suppress.`;
}

async function main() {
	const input = await parseStdinOrAllow("PTH-CONTAMINATION-GUARD");
	if (!input) return;

	const { tool_name, tool_input = {} } = input;
	if (tool_name !== "Bash") {
		allow();
		return;
	}

	const command = tool_input.command || "";
	if (!command.trim()) {
		allow();
		return;
	}

	// Fast path: skip if no relevant keywords. Checked BEFORE any isReadOnly
	// call because the shared detector treats SSH commands as read-only, but
	// we need to inspect inner commands for deploy hazards.
	const commandLower = command.toLowerCase();
	if (!FAST_PATH_KEYWORDS.some((kw) => commandLower.includes(kw))) {
		allow();
		return;
	}

	// Escape hatch
	if (/# PTH-OK/i.test(command)) {
		allow();
		return;
	}

	// Rule 1: maturin develop on remote → BLOCK
	const r1 = checkMaturinDevelopRemote(command);
	if (r1) return deny(r1);

	// Rule 2: rsync to site-packages → ASK
	const r2 = checkRsyncSitePackages(command);
	if (r2) return ask(r2);

	// Rule 3: project-dir install on remote → ASK
	const r3 = checkRemoteProjectDirInstall(command);
	if (r3) return ask(r3);

	// Rule 4: any remote pip install → ASK (softest)
	const r4 = checkRemotePipInstall(command);
	if (r4) return ask(r4);

	allow();
}

main().catch((err) => {
	trackHookError(
		"pretooluse-pth-contamination-guard",
		err instanceof Error ? err.message : String(err),
	);
	allow();
});
