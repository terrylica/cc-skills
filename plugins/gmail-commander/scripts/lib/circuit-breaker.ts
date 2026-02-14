/**
 * File-Based Circuit Breaker
 *
 * Tracks consecutive failures and opens the circuit after a threshold.
 * Cooldown period allows automatic recovery.
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

import { existsSync, readFileSync, writeFileSync, unlinkSync } from "fs";

interface CircuitState {
  failures: number;
  lastFailure: number;
}

export interface CircuitBreakerOptions {
  /** Path to the state file */
  stateFile: string;
  /** Number of failures before opening the circuit */
  maxFailures?: number;
  /** Cooldown period in ms before auto-reset */
  cooldownMs?: number;
}

const DEFAULTS = {
  maxFailures: 3,
  cooldownMs: 30 * 60 * 1000, // 30 minutes
} as const;

export function isCircuitOpen(opts: CircuitBreakerOptions): boolean {
  const { stateFile, maxFailures = DEFAULTS.maxFailures, cooldownMs = DEFAULTS.cooldownMs } = opts;
  try {
    if (!existsSync(stateFile)) return false;
    const state: CircuitState = JSON.parse(readFileSync(stateFile, "utf-8"));
    if (state.failures >= maxFailures) {
      if (Date.now() - state.lastFailure < cooldownMs) return true;
      // Cooldown expired — reset
      unlinkSync(stateFile);
    }
    return false;
  } catch {
    return false;
  }
}

export function recordFailure(opts: CircuitBreakerOptions): void {
  const { stateFile } = opts;
  let state: CircuitState = { failures: 0, lastFailure: 0 };
  try {
    if (existsSync(stateFile)) {
      state = JSON.parse(readFileSync(stateFile, "utf-8"));
    }
  } catch {
    // Start fresh
  }
  state.failures += 1;
  state.lastFailure = Date.now();
  writeFileSync(stateFile, JSON.stringify(state));
}

export function resetCircuit(opts: CircuitBreakerOptions): void {
  try {
    if (existsSync(opts.stateFile)) unlinkSync(opts.stateFile);
  } catch {
    // Non-critical
  }
}
