// PROCESS-STORM-OK — Scheduled digest entry point (runs every 6h via launchd)
/**
 * Gmail Digest — Automated Email Triage
 *
 * Runs every 6 hours via launchd. Fetches recent emails,
 * triages via Claude Agent SDK (Haiku), sends significant
 * findings to Telegram. Silent when nothing noteworthy.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
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

    let triageText = "";
    const result = query({
      prompt,
      options: {
        model: model as "haiku",
        maxTurns: 1,
        persistSession: false,
        tools: [],
        settingSources: [],
        systemPrompt: SYSTEM_PROMPT,
      },
    });

    for await (const message of result) {
      if (message.type === "assistant" && message.message?.content) {
        for (const block of message.message.content) {
          if (block.type === "text") {
            triageText += block.text;
          }
        }
      }
    }

    // Skill contamination check
    if (isSkillContaminated(triageText)) {
      auditLog("digest.skill_contamination", { textLen: triageText.length });
      console.error("Skill contamination detected. Discarding result.");
      recordFailure(circuitOpts);
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
    }

    // --- Podcast-style voice digest ---
    const kokoroUp = await isKokoroAvailable();
    if (!kokoroUp) {
      auditLog("tts.skipped", { reason: "kokoro_unavailable" });
      console.error("Kokoro TTS unavailable — skipping voice digest.");
    } else {
      console.error("Generating podcast narration with Haiku...");

      const podcastPrompt = `${ANTI_SKILL_PREFIX}Convert this email triage into a spoken podcast briefing:\n\n${triageText}`;
      let podcastText = "";

      const podcastResult = query({
        prompt: podcastPrompt,
        options: {
          model: model as "haiku",
          maxTurns: 1,
          persistSession: false,
          tools: [],
          settingSources: [],
          systemPrompt: PODCAST_SYSTEM_PROMPT,
        },
      });

      for await (const message of podcastResult) {
        if (message.type === "assistant" && message.message?.content) {
          for (const block of message.message.content) {
            if (block.type === "text") {
              podcastText += block.text;
            }
          }
        }
      }

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
  } finally {
    releaseLock(PID_FILE);
  }
}

main();
