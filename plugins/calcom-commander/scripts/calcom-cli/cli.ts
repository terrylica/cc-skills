// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Cal.com CLI — compiled Bun binary for Cal.com API v2 access.
 *
 * Usage:
 *   calcom event-types list
 *   calcom bookings list -n 10
 *   calcom bookings get <id>
 *   calcom schedules list
 *   calcom availability check --event-type-id <id> --start <date> --end <date>
 */

import { parseArgs } from "util";
import { loadConfig } from "./lib/config";
import { CalcomClient } from "./lib/calcom";
import { printJson, printBookings, printEventTypes, printSchedules } from "./lib/output";

const { values, positionals } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    json: { type: "boolean", default: false },
    n: { type: "string", default: "20" },
    status: { type: "string" },
    title: { type: "string" },
    slug: { type: "string" },
    length: { type: "string" },
    description: { type: "string" },
    hidden: { type: "string" },
    name: { type: "string" },
    timezone: { type: "string" },
    availability: { type: "string" },
    "event-type-id": { type: "string" },
    start: { type: "string" },
    end: { type: "string" },
    "requires-confirmation": { type: "string" },
  },
  allowPositionals: true,
  strict: false,
});

async function main() {
  const config = await loadConfig();
  const client = new CalcomClient(config);

  const [resource, action, ...rest] = positionals;
  const limit = parseInt(values.n || "20", 10);

  switch (`${resource} ${action}`) {
    case "event-types list": {
      const types = await client.listEventTypes();
      values.json ? printJson(types) : printEventTypes(types);
      break;
    }
    case "event-types create": {
      const result = await client.createEventType({
        title: values.title!,
        slug: values.slug!,
        length: parseInt(values.length!, 10),
        description: values.description,
        requiresConfirmation: values["requires-confirmation"] === "true",
      });
      printJson(result);
      break;
    }
    case "event-types update": {
      const id = rest[0];
      const updates: Record<string, unknown> = {};
      if (values.title) updates.title = values.title;
      if (values.length) updates.length = parseInt(values.length, 10);
      if (values.hidden) updates.hidden = values.hidden === "true";
      if (values.description) updates.description = values.description;
      const result = await client.updateEventType(id, updates);
      printJson(result);
      break;
    }
    case "bookings list": {
      const bookings = await client.listBookings({ limit, status: values.status });
      values.json ? printJson(bookings) : printBookings(bookings);
      break;
    }
    case "bookings get": {
      const id = rest[0];
      const booking = await client.getBooking(id);
      printJson(booking);
      break;
    }
    case "bookings cancel": {
      const id = rest[0];
      const result = await client.cancelBooking(id);
      printJson(result);
      break;
    }
    case "schedules list": {
      const schedules = await client.listSchedules();
      values.json ? printJson(schedules) : printSchedules(schedules);
      break;
    }
    case "schedules create": {
      const result = await client.createSchedule({
        name: values.name!,
        timezone: values.timezone,
        availability: values.availability ? JSON.parse(values.availability) : undefined,
      });
      printJson(result);
      break;
    }
    case "availability check": {
      const result = await client.checkAvailability({
        eventTypeId: parseInt(values["event-type-id"]!, 10),
        startTime: values.start!,
        endTime: values.end!,
      });
      printJson(result);
      break;
    }
    default:
      console.error(`Unknown command: ${resource} ${action}`);
      console.error("Usage: calcom <resource> <action> [options]");
      console.error("");
      console.error("Resources:");
      console.error("  event-types  list|create|update");
      console.error("  bookings     list|get|cancel");
      console.error("  schedules    list|create");
      console.error("  availability check");
      process.exit(1);
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
