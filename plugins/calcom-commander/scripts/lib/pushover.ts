// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Pushover API client — dual-channel notification support.
 *
 * Pushover is PLAIN TEXT ONLY — never send HTML tags.
 * Build messages in HTML for Telegram, then strip for Pushover.
 *
 * Priority levels:
 *   0 = normal (respects quiet hours)
 *   1 = high (bypasses quiet hours)
 *   2 = emergency (requires acknowledge, retry + expire mandatory)
 *
 * Reference: devops-tools:dual-channel-watchexec pushover-integration.md
 */

const PUSHOVER_API = "https://api.pushover.net/1/messages.json";

export interface PushoverMessage {
  title: string;
  message: string;
  priority?: 0 | 1 | 2;
  sound?: string;
  retry?: number;
  expire?: number;
}

export interface PushoverResponse {
  status: number;
  request: string;
  receipt?: string;
}

/**
 * Send a Pushover notification. Returns the API response.
 * Throws on network errors; returns status=0 on API validation errors.
 */
export async function sendPushover(
  token: string,
  user: string,
  msg: PushoverMessage,
): Promise<PushoverResponse> {
  const body: Record<string, string | number> = {
    token,
    user,
    title: msg.title,
    message: msg.message,
    priority: msg.priority ?? 0,
    sound: msg.sound ?? "pushover",
  };

  // Emergency priority requires retry + expire
  if (msg.priority === 2) {
    body.retry = msg.retry ?? 30;
    body.expire = msg.expire ?? 300;
  }

  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(body)) {
    params.set(key, String(value));
  }

  const res = await fetch(PUSHOVER_API, {
    method: "POST",
    body: params,
  });

  return (await res.json()) as PushoverResponse;
}

/**
 * Strip HTML tags for Pushover plain text.
 * Converts <b>text</b> → text, <s>text</s> → text, etc.
 */
export function stripHtmlForPushover(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/?[^>]+(>|$)/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .trim();
}
