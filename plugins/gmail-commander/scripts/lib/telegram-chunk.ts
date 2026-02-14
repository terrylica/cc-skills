// PROCESS-STORM-OK
/**
 * Telegram Message Chunking (Fence-Aware)
 *
 * Splits long messages respecting the 4096-char Telegram limit.
 * Fence-aware: never breaks inside code blocks.
 *
 * Ported from claude-telegram-sync/src/telegram/format.ts + fences.ts.
 * SSoT: ~/fork-tools/openclaw/src/auto-reply/chunk.ts
 *
 * // ADR: ~/.claude/docs/adr/2026-02-03-telegram-cli-sync-openclaw-patterns.md
 */

// --- Fence Span Parser ---

export type FenceSpan = {
  start: number;
  end: number;
  openLine: string;
  marker: string;
  indent: string;
};

export function parseFenceSpans(buffer: string): FenceSpan[] {
  const spans: FenceSpan[] = [];
  let open:
    | {
        start: number;
        markerChar: string;
        markerLen: number;
        openLine: string;
        marker: string;
        indent: string;
      }
    | undefined;

  let offset = 0;
  while (offset <= buffer.length) {
    const nextNewline = buffer.indexOf("\n", offset);
    const lineEnd = nextNewline === -1 ? buffer.length : nextNewline;
    const line = buffer.slice(offset, lineEnd);

    const match = line.match(/^( {0,3})(`{3,}|~{3,})(.*)$/);
    if (match) {
      const indent = match[1]!;
      const marker = match[2]!;
      const markerChar = marker[0]!;
      const markerLen = marker.length;
      if (!open) {
        open = { start: offset, markerChar, markerLen, openLine: line, marker, indent };
      } else if (open.markerChar === markerChar && markerLen >= open.markerLen) {
        spans.push({
          start: open.start,
          end: lineEnd,
          openLine: open.openLine,
          marker: open.marker,
          indent: open.indent,
        });
        open = undefined;
      }
    }

    if (nextNewline === -1) break;
    offset = nextNewline + 1;
  }

  if (open) {
    spans.push({
      start: open.start,
      end: buffer.length,
      openLine: open.openLine,
      marker: open.marker,
      indent: open.indent,
    });
  }

  return spans;
}

export function findFenceSpanAt(spans: FenceSpan[], index: number): FenceSpan | undefined {
  return spans.find((span) => index > span.start && index < span.end);
}

export function isSafeFenceBreak(spans: FenceSpan[], index: number): boolean {
  return !findFenceSpanAt(spans, index);
}

// --- Chunking ---

export function chunkTelegramHtml(text: string, limit: number = 4096): string[] {
  if (!text) return [];
  if (text.length <= limit) return [text];

  const normalized = text.replace(/\r\n?/g, "\n");
  const spans = parseFenceSpans(normalized);
  const paragraphRe = /\n[\t ]*\n+/g;

  const parts: string[] = [];
  let lastIndex = 0;
  for (const match of normalized.matchAll(paragraphRe)) {
    const idx = match.index ?? 0;
    if (!isSafeFenceBreak(spans, idx)) continue;
    parts.push(normalized.slice(lastIndex, idx));
    lastIndex = idx + match[0].length;
  }
  parts.push(normalized.slice(lastIndex));

  const chunks: string[] = [];
  let current = "";

  for (const part of parts) {
    const paragraph = part.replace(/\s+$/g, "");
    if (!paragraph.trim()) continue;

    if (current && (current + "\n\n" + paragraph).length <= limit) {
      current += "\n\n" + paragraph;
      continue;
    }

    if (current) {
      chunks.push(current);
      current = "";
    }

    if (paragraph.length <= limit) {
      current = paragraph;
      continue;
    }

    chunks.push(...chunkMarkdownText(paragraph, limit));
  }

  if (current.trim()) chunks.push(current);
  return chunks;
}

function chunkMarkdownText(text: string, limit: number): string[] {
  if (!text || text.length <= limit) return text ? [text] : [];

  const chunks: string[] = [];
  let remaining = text;

  while (remaining.length > limit) {
    const spans = parseFenceSpans(remaining);
    const window = remaining.slice(0, limit);

    const softBreak = pickSafeBreakIndex(window, spans);
    let breakIdx = softBreak > 0 ? softBreak : limit;

    const fence = isSafeFenceBreak(spans, breakIdx)
      ? undefined
      : findFenceSpanAt(spans, breakIdx);

    let fenceToSplit = fence;
    if (fence) {
      const closeLine = `${fence.indent}${fence.marker}`;
      const maxIdx = limit - (closeLine.length + 1);

      if (maxIdx <= 0) {
        fenceToSplit = undefined;
        breakIdx = limit;
      } else {
        const minProgress = Math.min(
          remaining.length,
          fence.start + fence.openLine.length + 2
        );
        let lastNl = remaining.lastIndexOf("\n", Math.max(0, limit - closeLine.length - 1));
        let pickedNewline = false;
        while (lastNl !== -1) {
          const candidate = lastNl + 1;
          if (candidate < minProgress) break;
          const atFence = findFenceSpanAt(spans, candidate);
          if (atFence && atFence.start === fence.start) {
            breakIdx = Math.max(1, candidate);
            pickedNewline = true;
            break;
          }
          lastNl = remaining.lastIndexOf("\n", lastNl - 1);
        }
        if (!pickedNewline) {
          if (minProgress > limit - closeLine.length) {
            fenceToSplit = undefined;
            breakIdx = limit;
          } else {
            breakIdx = Math.max(minProgress, maxIdx);
          }
        }

        const atBreak = findFenceSpanAt(spans, breakIdx);
        fenceToSplit = atBreak && atBreak.start === fence.start ? atBreak : undefined;
      }
    }

    let rawChunk = remaining.slice(0, breakIdx);
    if (!rawChunk) break;

    const brokeOnSep = breakIdx < remaining.length && /\s/.test(remaining[breakIdx]!);
    const nextStart = Math.min(remaining.length, breakIdx + (brokeOnSep ? 1 : 0));
    let next = remaining.slice(nextStart);

    if (fenceToSplit) {
      const closeLine = `${fenceToSplit.indent}${fenceToSplit.marker}`;
      rawChunk = rawChunk.endsWith("\n") ? `${rawChunk}${closeLine}` : `${rawChunk}\n${closeLine}`;
      next = `${fenceToSplit.openLine}\n${next}`;
    } else {
      let i = 0;
      while (i < next.length && next[i] === "\n") i++;
      if (i > 0) next = next.slice(i);
    }

    chunks.push(rawChunk);
    remaining = next;
  }

  if (remaining.length) chunks.push(remaining);
  return chunks;
}

function pickSafeBreakIndex(
  window: string,
  spans: FenceSpan[]
): number {
  let lastNewline = -1;
  let lastWhitespace = -1;

  for (let i = 0; i < window.length; i++) {
    if (!isSafeFenceBreak(spans, i)) continue;
    const char = window[i];
    if (char === "\n") lastNewline = i;
    else if (/\s/.test(char!)) lastWhitespace = i;
  }

  if (lastNewline > 0) return lastNewline;
  if (lastWhitespace > 0) return lastWhitespace;
  return -1;
}
