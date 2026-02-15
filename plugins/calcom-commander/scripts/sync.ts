// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Cal.com Commander Sync — Scheduled booking sync + dual-channel notifications.
 *
 * Runs every 6h via launchd StartInterval (com.terryli.calcom-commander-sync).
 * Fetches recent bookings, detects changes, sends notifications to:
 *   - Telegram (HTML format, interactive)
 *   - Pushover (plain text, emergency alerts with custom sound)
 *
 * Pushover is optional — gracefully degrades to Telegram-only if not configured.
 *
 * Entry point: bun run scripts/sync.ts
 */

import { sessionGuard } from "./lib/session-guard";
import { loadBotCredentials } from "./lib/credentials";
import { CircuitBreaker } from "./lib/circuit-breaker";
import { audit } from "./lib/audit";
import { sendTelegramMessage } from "./lib/telegram-format";
import { sendPushover, stripHtmlForPushover } from "./lib/pushover";

const PID_FILE = "/tmp/calcom-sync.pid";
const CIRCUIT_FILE = "/tmp/calcom-sync-circuit.json";
const STATE_FILE = `${process.env.HOME}/own/amonic/state/calcom-sync-state.json`;

interface SyncState {
  lastSyncAt: string;
  knownBookingIds: number[];
  lastBookingCount: number;
}

async function loadSyncState(): Promise<SyncState> {
  try {
    const file = Bun.file(STATE_FILE);
    if (await file.exists()) {
      return await file.json();
    }
  } catch {}
  return { lastSyncAt: new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString(), knownBookingIds: [], lastBookingCount: 0 };
}

async function saveSyncState(state: SyncState): Promise<void> {
  const { mkdir } = await import("fs/promises");
  const { dirname } = await import("path");
  await mkdir(dirname(STATE_FILE), { recursive: true });
  await Bun.write(STATE_FILE, JSON.stringify(state, null, 2));
}

async function main() {
  await sessionGuard(PID_FILE);

  const creds = loadBotCredentials();
  const circuit = new CircuitBreaker(CIRCUIT_FILE);

  if (circuit.isOpen()) {
    console.log("Circuit breaker OPEN — skipping sync");
    return;
  }

  await audit("sync.started", { pid: process.pid });

  try {
    const state = await loadSyncState();

    // TODO: Fetch bookings from Cal.com API via calcom-cli
    // const bookings = await fetchRecentBookings(state.lastSyncAt);
    // await audit("sync.bookings_found", { count: bookings.length });

    // TODO: Compare against known booking IDs
    // const newBookings = bookings.filter(b => !state.knownBookingIds.includes(b.id));
    // const cancelledIds = state.knownBookingIds.filter(id => !bookings.find(b => b.id === id));

    // TODO: Send notifications for changes
    // for (const booking of newBookings) {
    //   const htmlMessage = formatNewBooking(booking);
    //   await sendTelegramMessage(creds, htmlMessage);
    //
    //   // Dual-channel: also send to Pushover if configured
    //   if (creds.pushoverToken && creds.pushoverUser) {
    //     const plainMessage = stripHtmlForPushover(htmlMessage);
    //     await sendPushover(creds.pushoverToken, creds.pushoverUser, {
    //       title: "Cal.com: New Booking",
    //       message: plainMessage,
    //       priority: 2,
    //       sound: creds.pushoverSound || "dune",
    //       retry: 30,
    //       expire: 300,
    //     });
    //   }
    //   await audit("sync.new_booking", { bookingId: booking.id });
    // }

    // Update state
    state.lastSyncAt = new Date().toISOString();
    // state.knownBookingIds = bookings.map(b => b.id);
    // state.lastBookingCount = bookings.length;
    await saveSyncState(state);

    circuit.recordSuccess();
    await audit("sync.completed", { bookingCount: state.lastBookingCount });
    console.log("Sync completed successfully");

  } catch (err) {
    circuit.recordFailure();
    await audit("sync.error", { error: (err as Error).message });
    console.error("Sync error:", err);
  } finally {
    const fs = await import("fs");
    try { fs.unlinkSync(PID_FILE); } catch {}
  }
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
