// PROCESS-STORM-OK — Scheduled digest entry point (runs every 6h via launchd)
/**
 * Gmail Digest — Automated Email Triage
 *
 * Runs every 6 hours via launchd. Fetches recent emails,
 * triages via Claude Agent SDK (Haiku), sends significant
 * findings to Telegram. Silent when nothing noteworthy.
 */

import { query } from "@anthropic-ai/claude-agent-sdk";
import { fetchRecentEmails } from "./lib/gmail-client.js";
import { sendDigest } from "./lib/telegram-format.js";
import { isKokoroAvailable, generateDigestAudio, sendVoiceMessage } from "./lib/tts-client.js";
import { auditLog, pruneOldLogs } from "./lib/audit.js";
import { acquireLock, releaseLock } from "./lib/session-guard.js";
import { isCircuitOpen, recordFailure, resetCircuit } from "./lib/circuit-breaker.js";
import {
  parseTriageResponse,
  formatEmailsForTriage,
  isSkillContaminated,
  TRIAGE_SYSTEM_PROMPT,
  ANTI_SKILL_PREFIX,
} from "./lib/triage.js";

// --- Configuration ---

const PID_FILE = "/tmp/gmail-digest.pid";
const CIRCUIT_FILE = "/tmp/gmail-digest-circuit.json";
const circuitOpts = { stateFile: CIRCUIT_FILE, maxFailures: 3, cooldownMs: 30 * 60 * 1000 };

// Triage system prompt — SSoT in triage.ts
const SYSTEM_PROMPT = TRIAGE_SYSTEM_PROMPT;

const PODCAST_SYSTEM_PROMPT = `You are a friendly podcast host delivering a personal email briefing. Convert the email triage below into a natural, conversational audio script that sounds like a morning briefing podcast.

Rules:
- Address the listener as "you" directly, as if speaking to a friend
- Use natural speech patterns with short sentences — this will be read aloud by TTS
- Start with a brief greeting and time context (e.g., "Hey, here's what landed in your inbox...")
- Follow the three-category structure naturally: lead with system and security alerts first, then work items, then personal and family stuff
- For security alerts, use an urgent but calm tone like "heads up, you need to check this right away"
- For work items, be professional but casual
- For personal messages, be warm and friendly
- For deadlines, mention the date clearly
- End with a brief sign-off
- Keep it under 200 words — this is a quick briefing, not a full show
- Do NOT use markdown, bullet points, or any formatting — pure spoken text
- Do NOT use emojis or special characters
- Avoid abbreviations that TTS would mangle`;

// --- Haiku completion backend ---
// Portable default: the Agent SDK's query() (spawns Claude's cli.js directly).
//
// Fleet override (DIGEST_CLAUDE_WRAPPER): on the ccmax fleet, claude.ai is logged
// out (pure bearer-pin mode) and the fleet proxy (tailproxy / HEART-101) fail-closes
// against headless non-wrapper inference — it requires a per-device sk-key plus a
// ~270s-expiring capability ticket that ONLY the `ccmax-claude` Go wrapper mints (via
// a per-request PoW handshake against doorward). The SDK spawns cli.js directly,
// bypassing that wrapper, so query() gets a 403. When DIGEST_CLAUDE_WRAPPER points at
// the wrapper binary, route one-shot completions through it instead: the wrapper does
// the handshake, mints/refreshes the per-device key + ticket, injects all four fleet
// headers, and self-heals across key rotation + version-floor bumps. --output-format
// text puts only the completion on stdout (fleet banner goes to stderr).
async function completeWithHaiku(opts: {
  prompt: string;
  systemPrompt: string;
  model: string;
}): Promise<string> {
  const wrapper = Bun.env.DIGEST_CLAUDE_WRAPPER;
  if (wrapper) {
    const proc = Bun.spawn(
      [
        wrapper, "--",
        "-p",
        "--model", opts.model,
        "--output-format", "text",
        "--append-system-prompt", opts.systemPrompt,
      ],
      { stdin: "pipe", stdout: "pipe", stderr: "inherit" }
    );
    proc.stdin!.write(opts.prompt);
    proc.stdin!.end();
    const out = await new Response(proc.stdout).text();
    const code = await proc.exited;
    if (code !== 0) throw new Error(`ccmax-claude wrapper exited with code ${code}`);
    return out.trim();
  }

  // Portable SDK path (non-fleet installs).
  let text = "";
  const result = query({
    prompt: opts.prompt,
    options: {
      model: opts.model as "haiku",
      maxTurns: 1,
      persistSession: false,
      tools: [],
      settingSources: [],
      systemPrompt: opts.systemPrompt,
    },
  });
  for await (const message of result) {
    if (message.type === "assistant" && message.message?.content) {
      for (const block of message.message.content) {
        if (block.type === "text") {
          text += block.text;
        }
      }
    }
  }
  return text;
}

// --- Failure alert (portable, best-effort) ---
// The digest failed silently for weeks before anyone noticed. When DIGEST_ALERT_CMD
// is set, run it with a one-line reason on stdin so a broken run surfaces immediately.
// The command is machine-local (on the fleet it's a vault-backed Pushover sender), so
// this plugin carries no notifier/credential coupling. Never lets alerting break the run.
async function alertDigestFailure(reason: string): Promise<void> {
  const cmd = Bun.env.DIGEST_ALERT_CMD;
  if (!cmd) return;
  try {
    const proc = Bun.spawn([cmd], { stdin: "pipe", stdout: "ignore", stderr: "ignore" });
    proc.stdin!.write(`gmail-digest: ${reason}`);
    proc.stdin!.end();
    await proc.exited;
  } catch {
    // best-effort: alerting must never break the digest
  }
}

// --- Main ---

async function main() {
  const startTime = Date.now();

  if (!acquireLock(PID_FILE)) {
    console.error("Another gmail-digest instance is running. Exiting.");
    process.exit(0);
  }

  try {
    auditLog("digest.started");
    pruneOldLogs();

    if (isCircuitOpen(circuitOpts)) {
      auditLog("digest.circuit_open");
      console.error("Circuit breaker open — skipping this run.");
      await alertDigestFailure("circuit breaker open — digest still failing, skipping run");
      return;
    }

    // Fetch recent emails
    console.error("Fetching emails from last 6 hours...");
    const emails = await fetchRecentEmails(6);

    auditLog("digest.emails_found", { count: emails.length });
    console.error(`Found ${emails.length} emails.`);

    if (emails.length === 0) {
      auditLog("digest.silent", { reason: "no_emails" });
      console.error("No emails. Silent exit.");
      return;
    }

    // Format for triage
    const emailText = formatEmailsForTriage(emails);
    const prompt = `${ANTI_SKILL_PREFIX}Triage these ${emails.length} emails:\n\n${emailText}`;

    // Call Agent SDK with Haiku
    console.error("Triaging with Haiku...");
    const model = Bun.env.HAIKU_MODEL;
    if (!model) throw new Error("HAIKU_MODEL not set in env");

    const triageText = await completeWithHaiku({ prompt, systemPrompt: SYSTEM_PROMPT, model });

    // Skill contamination check
    if (isSkillContaminated(triageText)) {
      auditLog("digest.skill_contamination", { textLen: triageText.length });
      console.error("Skill contamination detected. Discarding result.");
      recordFailure(circuitOpts);
      await alertDigestFailure("triage output was skill-contaminated — discarded");
      return;
    }

    console.error(`Triage result:\n${triageText}`);

    // Parse triage response
    const items = parseTriageResponse(triageText);

    auditLog("digest.triage_complete", {
      totalEmails: emails.length,
      significantItems: items.length,
      triageLen: triageText.length,
      durationMs: Date.now() - startTime,
    });

    if (items.length === 0) {
      auditLog("digest.silent", { reason: "no_significant" });
      console.error("No significant emails. Silent exit.");
      resetCircuit(circuitOpts);
      return;
    }

    // Send to Telegram
    console.error(`Sending ${items.length} significant items to Telegram...`);
    const sent = await sendDigest(items, emails.length);

    if (sent) {
      auditLog("digest.notification_sent", { items: items.length, totalEmails: emails.length });
      console.error("Telegram notification sent.");
      resetCircuit(circuitOpts);
    } else {
      auditLog("digest.telegram_error");
      console.error("Failed to send Telegram notification.");
      recordFailure(circuitOpts);
      await alertDigestFailure("triage OK but Telegram send failed");
    }

    // --- Podcast-style voice digest ---
    const kokoroUp = await isKokoroAvailable();
    if (!kokoroUp) {
      auditLog("tts.skipped", { reason: "kokoro_unavailable" });
      console.error("Kokoro TTS unavailable — skipping voice digest.");
    } else {
      console.error("Generating podcast narration with Haiku...");

      const podcastPrompt = `${ANTI_SKILL_PREFIX}Convert this email triage into a spoken podcast briefing:\n\n${triageText}`;
      const podcastText = await completeWithHaiku({ prompt: podcastPrompt, systemPrompt: PODCAST_SYSTEM_PROMPT, model });

      if (isSkillContaminated(podcastText)) {
        auditLog("tts.skill_contamination");
        console.error("Podcast narration contaminated — skipping voice.");
      } else if (podcastText.length > 0) {
        console.error(`Podcast script (${podcastText.length} chars):\n${podcastText}`);

        const audioBuffer = await generateDigestAudio(podcastText);
        if (audioBuffer) {
          const chatId = Bun.env.TELEGRAM_CHAT_ID;
          if (chatId) {
            const voiceSent = await sendVoiceMessage(
              chatId,
              audioBuffer,
              `<i>\u{1F4EC} Voice digest — ${items.length} items</i>`
            );
            auditLog("tts.voice_sent", {
              sent: voiceSent,
              audioBytes: audioBuffer.length,
              textLen: podcastText.length,
            });
            console.error(voiceSent ? "Voice message sent to Telegram." : "Failed to send voice message.");
          }
        }
      }
    }
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    auditLog("digest.error", { error: msg });
    console.error(`Error: ${msg}`);
    recordFailure(circuitOpts);
    await alertDigestFailure(`run error: ${msg}`);
  } finally {
    releaseLock(PID_FILE);
  }
}

main();
