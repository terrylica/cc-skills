// ADR: docs/adr/2026-02-14-calcom-commander.md
/**
 * File-based circuit breaker — tracks failures, auto-reset on cooldown.
 */

import { existsSync, readFileSync, writeFileSync, unlinkSync } from "fs";

interface CircuitState {
  failures: number;
  lastFailure: string;
  openedAt?: string;
}

const MAX_FAILURES = 3;
const COOLDOWN_MS = 10 * 60 * 1000; // 10 minutes

export class CircuitBreaker {
  constructor(private filePath: string) {}

  private loadState(): CircuitState | null {
    if (!existsSync(this.filePath)) return null;
    try {
      return JSON.parse(readFileSync(this.filePath, "utf-8"));
    } catch {
      return null;
    }
  }

  private saveState(state: CircuitState): void {
    writeFileSync(this.filePath, JSON.stringify(state, null, 2));
  }

  isOpen(): boolean {
    const state = this.loadState();
    if (!state || state.failures < MAX_FAILURES) return false;

    // Check cooldown
    if (state.openedAt) {
      const elapsed = Date.now() - new Date(state.openedAt).getTime();
      if (elapsed > COOLDOWN_MS) {
        // Auto-reset after cooldown
        this.reset();
        return false;
      }
    }

    return true;
  }

  recordFailure(): void {
    const state = this.loadState() || { failures: 0, lastFailure: "" };
    state.failures += 1;
    state.lastFailure = new Date().toISOString();
    if (state.failures >= MAX_FAILURES) {
      state.openedAt = new Date().toISOString();
    }
    this.saveState(state);
  }

  recordSuccess(): void {
    this.reset();
  }

  reset(): void {
    try { unlinkSync(this.filePath); } catch {}
  }
}
