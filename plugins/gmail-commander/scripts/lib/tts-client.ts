// PROCESS-STORM-OK
/**
 * Kokoro TTS Client + Telegram Voice Message
 *
 * Generates podcast-style audio via Kokoro TTS on littleblack (ZeroTier),
 * converts WAV -> OGG/Opus via ffmpeg, sends as Telegram voice message.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { auditLog } from "./audit.js";
import { unlinkSync } from "fs";

const KOKORO_HOST = "172.25.236.1";
const KOKORO_PORT = "8090";
const KOKORO_URL = `http://${KOKORO_HOST}:${KOKORO_PORT}/tts`;
const HEALTH_URL = `http://${KOKORO_HOST}:${KOKORO_PORT}/health`;

const VOICE_EN = "af_heart";
const VOICE_ZH = "zf_xiaobei";
const SPEED = 1.1;
const GENERATE_TIMEOUT_MS = 30_000;
const HEALTH_TIMEOUT_MS = 3_000;
const MAX_TEXT_LEN = 1500;

function detectLanguage(text: string): { lang: string; voice: string } {
  let cjkCount = 0;
  for (const char of text) {
    const code = char.codePointAt(0)!;
    if (
      (code >= 0x4e00 && code <= 0x9fff) ||
      (code >= 0x3400 && code <= 0x4dbf) ||
      (code >= 0x20000 && code <= 0x2a6df)
    ) {
      cjkCount++;
    }
  }
  const ratio = text.length > 0 ? (cjkCount / text.length) * 100 : 0;
  if (ratio >= 20) return { lang: "cmn", voice: VOICE_ZH };
  return { lang: "en-us", voice: VOICE_EN };
}

export async function isKokoroAvailable(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), HEALTH_TIMEOUT_MS);
    const resp = await fetch(HEALTH_URL, { signal: controller.signal });
    clearTimeout(timer);
    return resp.ok;
  } catch {
    return false;
  }
}

export async function generateDigestAudio(text: string): Promise<Buffer | null> {
  if (text.length > MAX_TEXT_LEN) {
    text = text.slice(0, MAX_TEXT_LEN);
    auditLog("tts.truncated", { originalLen: text.length, maxLen: MAX_TEXT_LEN });
  }

  const { lang, voice } = detectLanguage(text);
  const tmpWav = `/tmp/gmail-digest-tts-${process.pid}-${Date.now()}.wav`;
  const tmpOgg = `/tmp/gmail-digest-tts-${process.pid}-${Date.now()}.ogg`;

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), GENERATE_TIMEOUT_MS);

    const genStart = Date.now();
    const response = await fetch(KOKORO_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text, voice, lang, speed: SPEED }),
      signal: controller.signal,
    });
    clearTimeout(timer);

    if (!response.ok) throw new Error(`Kokoro HTTP ${response.status}`);

    const wavData = await response.arrayBuffer();
    if (wavData.byteLength < 100) throw new Error("Kokoro response too small");

    await Bun.write(tmpWav, wavData);
    const genMs = Date.now() - genStart;

    auditLog("tts.generate", {
      provider: "kokoro",
      voice, lang,
      textLen: text.length,
      genMs,
      audioBytes: wavData.byteLength,
    });

    // Convert WAV -> OGG/Opus via ffmpeg (Telegram requires OGG/Opus for voice)
    const ffmpeg = Bun.spawn(
      [
        "ffmpeg", "-y",
        "-i", tmpWav,
        "-c:a", "libopus",
        "-b:a", "64k",
        "-vbr", "on",
        "-application", "voip",
        tmpOgg,
      ],
      { stdout: "pipe", stderr: "pipe" }
    );
    await ffmpeg.exited;

    const oggData = await Bun.file(tmpOgg).arrayBuffer();

    auditLog("tts.convert", {
      wavBytes: wavData.byteLength,
      oggBytes: oggData.byteLength,
    });

    return Buffer.from(oggData);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    auditLog("tts.error", { error: msg });
    console.error(`TTS error: ${msg}`);
    return null;
  } finally {
    try { unlinkSync(tmpWav); } catch {}
    try { unlinkSync(tmpOgg); } catch {}
  }
}

export async function sendVoiceMessage(
  chatId: string,
  oggBuffer: Buffer,
  caption?: string
): Promise<boolean> {
  const token = Bun.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error("TELEGRAM_BOT_TOKEN not set");

  const formData = new FormData();
  formData.append("chat_id", chatId);
  formData.append(
    "voice",
    new Blob([new Uint8Array(oggBuffer)], { type: "audio/ogg" }),
    "digest.ogg"
  );
  if (caption) {
    formData.append("caption", caption);
    formData.append("parse_mode", "HTML");
  }

  const resp = await fetch(
    `https://api.telegram.org/bot${token}/sendVoice`,
    { method: "POST", body: formData }
  );

  const result = await resp.json() as { ok: boolean; description?: string };
  if (!result.ok) {
    auditLog("tts.telegram_error", { error: result.description });
    console.error(`Telegram sendVoice error: ${result.description}`);
  }
  return result.ok === true;
}
