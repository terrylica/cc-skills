// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Output formatting for Cal.com CLI.
 */

export function printJson(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}

export function printEventTypes(data: unknown): void {
  const response = data as { data?: Array<Record<string, unknown>> };
  const items = response.data || [];

  if (items.length === 0) {
    console.log("No event types found.");
    return;
  }

  console.log(`Event Types (${items.length}):`);
  console.log("─".repeat(60));
  for (const item of items) {
    const hidden = item.hidden ? " [HIDDEN]" : "";
    console.log(`  ${item.id}  ${item.title} (${item.lengthInMinutes || item.length}min)${hidden}`);
    if (item.slug) console.log(`       slug: ${item.slug}`);
    if (item.description) console.log(`       ${item.description}`);
  }
}

export function printBookings(data: unknown): void {
  const response = data as { data?: { bookings?: Array<Record<string, unknown>> } };
  const items = response.data?.bookings || [];

  if (items.length === 0) {
    console.log("No bookings found.");
    return;
  }

  console.log(`Bookings (${items.length}):`);
  console.log("─".repeat(60));
  for (const item of items) {
    const status = String(item.status || "unknown").toUpperCase();
    const start = item.startTime ? new Date(item.startTime as string).toLocaleString() : "?";
    const attendees = (item.attendees as Array<{ name?: string; email?: string }>) || [];
    const attendee = attendees[0];
    const who = attendee ? `${attendee.name || attendee.email}` : "Unknown";
    console.log(`  ${item.id}  [${status}] ${item.title || "Untitled"}`);
    console.log(`       ${start} — ${who}`);
  }
}

export function printSchedules(data: unknown): void {
  const response = data as { data?: Array<Record<string, unknown>> };
  const items = response.data || [];

  if (items.length === 0) {
    console.log("No schedules found.");
    return;
  }

  console.log(`Schedules (${items.length}):`);
  console.log("─".repeat(60));
  for (const item of items) {
    const isDefault = item.isDefault ? " [DEFAULT]" : "";
    console.log(`  ${item.id}  ${item.name}${isDefault}`);
    if (item.timezone) console.log(`       timezone: ${item.timezone}`);
  }
}
