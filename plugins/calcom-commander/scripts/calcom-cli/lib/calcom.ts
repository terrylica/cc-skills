// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * Cal.com API v2 client — wraps REST endpoints for event types, bookings, schedules.
 */

import type { CalcomConfig } from "./config";

export class CalcomClient {
  private apiKey: string;
  private baseUrl: string;

  constructor(config: CalcomConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.apiUrl;
  }

  private async request(path: string, options: RequestInit = {}): Promise<unknown> {
    const url = `${this.baseUrl}${path}`;
    const res = await fetch(url, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
        "cal-api-version": "2024-08-13",
        ...options.headers,
      },
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Cal.com API error ${res.status}: ${text}`);
    }

    return res.json();
  }

  // Event Types
  async listEventTypes(): Promise<unknown> {
    return this.request("/event-types");
  }

  async createEventType(data: {
    title: string;
    slug: string;
    length: number;
    description?: string;
    requiresConfirmation?: boolean;
  }): Promise<unknown> {
    return this.request("/event-types", {
      method: "POST",
      body: JSON.stringify({
        title: data.title,
        slug: data.slug,
        lengthInMinutes: data.length,
        description: data.description,
        requiresConfirmation: data.requiresConfirmation,
      }),
    });
  }

  async updateEventType(id: string, updates: Record<string, unknown>): Promise<unknown> {
    return this.request(`/event-types/${id}`, {
      method: "PATCH",
      body: JSON.stringify(updates),
    });
  }

  // Bookings
  async listBookings(opts: { limit?: number; status?: string } = {}): Promise<unknown> {
    const params = new URLSearchParams();
    if (opts.limit) params.set("take", String(opts.limit));
    if (opts.status) params.set("status", opts.status);
    const qs = params.toString();
    return this.request(`/bookings${qs ? `?${qs}` : ""}`);
  }

  async getBooking(id: string): Promise<unknown> {
    return this.request(`/bookings/${id}`);
  }

  async cancelBooking(id: string): Promise<unknown> {
    return this.request(`/bookings/${id}/cancel`, { method: "POST" });
  }

  // Schedules
  async listSchedules(): Promise<unknown> {
    return this.request("/schedules");
  }

  async createSchedule(data: {
    name: string;
    timezone?: string;
    availability?: Array<{ days: number[]; startTime: string; endTime: string }>;
  }): Promise<unknown> {
    return this.request("/schedules", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }

  // Availability
  async checkAvailability(data: {
    eventTypeId: number;
    startTime: string;
    endTime: string;
  }): Promise<unknown> {
    const params = new URLSearchParams({
      eventTypeId: String(data.eventTypeId),
      startTime: data.startTime,
      endTime: data.endTime,
    });
    return this.request(`/slots?${params.toString()}`);
  }
}
