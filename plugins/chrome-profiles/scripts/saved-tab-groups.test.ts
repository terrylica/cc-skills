// Synthetic records only: no real profile, account or URL.
import { describe, expect, test } from "bun:test";
import type { Rec } from "./extension-token-from-profile.ts";
import { savedPlaywrightGroups } from "./saved-tab-groups.ts";

const enc = new TextEncoder();
const rec = (key: string, value: string | null, seq: number): Rec => ({ key: enc.encode(key), value: value === null ? null : enc.encode(`\n\x12${value}\x1a`), seq: BigInt(seq) });
const G = (n: number) => `saved_tab_group-dt-0000000${n}-aaaa-bbbb-cccc-dddddddddddd`;

describe("savedPlaywrightGroups", () => {
  test("counts live Playwright groups and tallies them by client", () => {
    const r = savedPlaywrightGroups([rec(G(1), "Playwright · mcp-drive", 1), rec(G(2), "Playwright · mcp-drive", 2), rec(G(3), "Playwright · claude-code", 3)]);
    expect(r).toEqual({ live: 3, titles: { "mcp-drive": 2, "claude-code": 1 } });
  });
  test("the newest record per key decides: a later deletion removes the group", () => {
    expect(savedPlaywrightGroups([rec(G(1), "Playwright · mcp-drive", 5), rec(G(1), null, 9)]).live).toBe(0);
  });
  test("an older record cannot resurrect a deleted group, whatever the input order", () => {
    expect(savedPlaywrightGroups([rec(G(1), null, 9), rec(G(1), "Playwright · mcp-drive", 5)]).live).toBe(0);
  });
  test("other groups, other key spaces and metadata are ignored", () => {
    const r = savedPlaywrightGroups([rec(G(1), "Holiday plans", 1), rec("saved_tab_group-md-00000001-aaaa-bbbb-cccc-dddddddddddd", "Playwright · mcp-drive", 2), rec("sessions-dt-x", "Playwright · mcp-drive", 3)]);
    expect(r).toEqual({ live: 0, titles: {} });
  });
});
