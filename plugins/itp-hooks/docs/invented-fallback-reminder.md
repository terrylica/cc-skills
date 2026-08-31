# Invented-Fallback Reminder

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md) — extracted from the hub's hook table 2026-08-30 (hub was 37.8k chars against a 40k hard limit; the row's narrative was the only home for these facts).

- **Hook**: `posttooluse-invented-fallback-reminder.ts`
- **Event / matcher**: `PostToolUse` on `Bash|Write|Edit|MultiEdit`
- **Severity**: non-blocking reminder (context injection), never a deny.

## What it does

An **official-values nudge**. When an edit introduces a _net-new_ invented fallback display value — `Unknown`, `N/A`, `?` and that class of placeholder — the hook reminds you to source the real value from the official/authoritative surface instead of inventing a stand-in that will be read as data.

## Scope rules

- **Net-new only.** Pre-existing occurrences in the file are not re-reported; only values the edit itself introduces fire the reminder. This is what keeps it quiet on large legacy files.
- **Covers Bash inline content**, not just Write/Edit file bodies — an invented fallback written via a heredoc or an inline `echo` in a Bash command is detected the same way.
- **Throwaway scratch is exempt** — the same scratch/temp-path exemption the sibling PostToolUse reminders use.

## Escape hatch

`INVENTED-FALLBACK-OK`

## Why it exists

A placeholder like `Unknown` or `N/A` is indistinguishable, downstream, from a measured value. The reminder exists to force the choice to be deliberate: either fetch the official value, or state explicitly (via the escape token) that no value exists.
