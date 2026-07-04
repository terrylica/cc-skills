#!/usr/bin/env bun
/**
 * PreToolUse hook: WebFetch Fallback Guard
 *
 * Unconditionally blocks the built-in `WebFetch` tool, which is broken
 * upstream: before fetching any URL it makes a domain-safety verification
 * request to `claude.ai`, which sits behind Cloudflare bot protection and
 * returns 403 + a JS challenge to any CLI/headless client. The pre-check
 * fails, so WebFetch aborts with "Claude Code is unable to fetch from
 * <domain>" — even when the target site serves 200 to a normal client. The
 * error misleadingly names the target domain; the target is never contacted.
 *
 * Diagnosis proven 2026-06-22 by data-flow isolation: curl→target = 200,
 * curl→claude.ai = 403 (both direct and through the local proxy), so the
 * failure is upstream in Claude Code, NOT the ccmax proxy or the network.
 *
 * Policy (operator directive 2026-06-22): never use WebFetch. Fall back to
 * curl → agent-reach (browser-grade) → WebSearch. This hook enforces that
 * deterministically (deny + reason is the Claude-visible PreToolUse channel
 * that survives the #55889 context-drop bug; matcher is WebFetch, not Bash).
 *
 * No escape hatch by design: WebFetch's claude.ai pre-check 403s on EVERY
 * call in a CLI environment, so the tool never succeeds here — an override
 * would only reproduce the failure. If Anthropic fixes the upstream bug,
 * disable this hook (or migrate to the iter-107 shared helper to add a
 * properly-registered marker) rather than adding a hand-rolled escape hatch.
 *
 * SSoT: ~/.claude/webfetch-fallback-CLAUDE.md
 * Upstream: anthropics/claude-code#8331, #22846, #39896, #13718, #17929
 */

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

const HOOK_NAME = "pretooluse-webfetch-fallback-guard";

const DENY_MESSAGE = `[WEBFETCH-FALLBACK] Built-in WebFetch is broken upstream — use a fallback.

WHY: WebFetch first verifies the domain against claude.ai, which is behind
Cloudflare bot protection and returns 403 to any CLI client. The fetch aborts
before the target site is ever contacted (the "unable to fetch from <domain>"
error names the target misleadingly). This is an upstream Claude Code bug, not
your network or proxy (proven: curl→target = 200, curl→claude.ai = 403).

USE INSTEAD (in order):
  1. curl -sL --max-time 20 <url>        # known URL; pipe through a parser
  2. agent-reach skill (browser-grade)   # JS-heavy / anti-bot / TLS-fingerprint sites
  3. WebSearch                           # when the exact URL is unknown

Emit a one-line heads-up when you switch (e.g. "built-in fetch broken → used curl").
SSoT: ~/.claude/webfetch-fallback-CLAUDE.md`;

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;

  // Only guard the built-in WebFetch tool; everything else passes through.
  if (input.tool_name !== "WebFetch") {
    allow();
    return;
  }

  deny(DENY_MESSAGE);
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
