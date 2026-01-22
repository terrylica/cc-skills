#!/usr/bin/env bun
/**
 * UserPromptSubmit hook: Time-Weighted Sharpe Context Injection
 *
 * When user's prompt contains quant/financial keywords, inject context
 * about time-weighted Sharpe for range bars to prime Claude's awareness.
 *
 * Output: `additionalContext` field for context injection (non-blocking)
 *
 * Reference: /docs/reference/range-bar-sharpe-calculation.md
 */

/**
 * Keywords that suggest quant/financial work where Sharpe might be relevant.
 */
const QUANT_KEYWORDS = [
  // Direct Sharpe mentions
  "sharpe",
  "sortino",
  "calmar",

  // Range bar context
  "range bar",
  "rangebar",
  "duration_us",
  "bar duration",

  // Financial metrics
  "backtest",
  "strategy",
  "pnl",
  "returns",
  "performance",
  "drawdown",
  "volatility",

  // ML finance
  "wfo",
  "walk-forward",
  "epoch selection",
  "bilstm",
  "slstm",
  "mlstm",
  "xlstm",

  // Crypto specific
  "btcusdt",
  "crypto",
  "binance",
];

/**
 * Parse stdin JSON for UserPromptSubmit.
 */
async function parseStdin() {
  try {
    const stdin = await Bun.stdin.text();
    return JSON.parse(stdin);
  } catch {
    return null;
  }
}

/**
 * Check if prompt contains quant keywords.
 */
function hasQuantKeywords(prompt) {
  const lowerPrompt = prompt.toLowerCase();
  return QUANT_KEYWORDS.some(keyword => lowerPrompt.includes(keyword.toLowerCase()));
}

/**
 * Output context injection (non-blocking).
 */
function injectContext(context) {
  console.log(JSON.stringify({
    additionalContext: context,
  }));
}

/**
 * Allow prompt without injection.
 */
function allow() {
  console.log(JSON.stringify({}));
}

/**
 * Main entry point.
 */
async function main() {
  const input = await parseStdin();
  if (!input) {
    allow();
    return;
  }

  const prompt = input.prompt || "";

  // Only inject context for quant-related prompts
  if (!hasQuantKeywords(prompt)) {
    allow();
    return;
  }

  // Inject time-weighted Sharpe context
  const context = `[TIME-WEIGHTED SHARPE CONTEXT]
When working with range bar data, remember:
- Range bars have VARIABLE DURATIONS (not fixed time intervals)
- Simple bar Sharpe (mean/std) treats all bars equally - INCORRECT for range bars
- Time-weighted Sharpe weights by bar duration - REQUIRED for accuracy
- Canonical implementation: compute_time_weighted_sharpe(pnl, duration_us)
- Preserve duration_us through the entire data pipeline
- For crypto: Use sqrt(365) annualization, NOT sqrt(252)
- Escape hatch: Add "# time-weighted-sharpe-ok" comment if simple Sharpe is intentional`;

  injectContext(context);
}

main().catch((e) => {
  console.error(`[sharpe-context] Error: ${e.message}`);
  console.log(JSON.stringify({}));  // Allow on error
});
