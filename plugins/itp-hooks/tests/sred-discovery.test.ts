/**
 * sred-discovery.test.ts - Unit tests for SR&ED project discovery
 *
 * ADR: 2026-01-18-sred-dynamic-discovery
 */

import { describe, expect, test } from 'bun:test';
import {
  extractScope,
  formatFailure,
  formatSuggestion,
  generateFallbackProject,
  scopeToProject,
  type FailurePatternCode,
} from '../hooks/failure-patterns';
import {
  generateCacheKey,
  sanitizeInput,
} from '../hooks/sred-discovery';

describe('scopeToProject', () => {
  test('converts lowercase to uppercase', () => {
    expect(scopeToProject('my-feature')).toBe('MY-FEATURE');
  });

  test('removes invalid characters', () => {
    expect(scopeToProject('my_feature.v2')).toBe('MY-FEATURE-V2');
  });

  test('collapses multiple hyphens', () => {
    expect(scopeToProject('my--feature---name')).toBe('MY-FEATURE-NAME');
  });

  test('removes leading/trailing hyphens', () => {
    expect(scopeToProject('-my-feature-')).toBe('MY-FEATURE');
  });

  test('handles single word', () => {
    expect(scopeToProject('feature')).toBe('FEATURE');
  });

  test('handles numbers', () => {
    expect(scopeToProject('feature-v2')).toBe('FEATURE-V2');
  });
});

describe('extractScope', () => {
  test('extracts scope from conventional commit', () => {
    expect(extractScope('feat(my-scope): add feature')).toBe('my-scope');
  });

  test('handles complex scope names', () => {
    expect(extractScope('fix(core-rust): fix bug')).toBe('core-rust');
  });

  test('returns null for commits without scope', () => {
    expect(extractScope('feat: add feature')).toBeNull();
  });

  test('returns null for malformed commits', () => {
    expect(extractScope('not a conventional commit')).toBeNull();
  });

  test('handles different commit types', () => {
    expect(extractScope('refactor(utils): cleanup')).toBe('utils');
    expect(extractScope('perf(optimizer): speedup')).toBe('optimizer');
    expect(extractScope('docs(readme): update')).toBe('readme');
  });
});

describe('generateFallbackProject', () => {
  test('generates project from scope', () => {
    expect(generateFallbackProject('feat(my-feature): add feature')).toBe('MY-FEATURE');
  });

  test('returns UNKNOWN-PROJECT for no scope', () => {
    expect(generateFallbackProject('feat: add feature')).toBe('UNKNOWN-PROJECT');
  });

  test('handles multiline commit messages', () => {
    const message = `feat(core): add feature

This is the body of the commit message.

SRED-Type: experimental-development`;
    expect(generateFallbackProject(message)).toBe('CORE');
  });
});

describe('formatFailure', () => {
  test('formats network timeout failure', () => {
    const result = formatFailure('NETWORK_TIMEOUT', 'MY-PROJECT', ['ALT-1', 'ALT-2']);
    expect(result).toContain('[SRED-GUARD] Discovery failed (network timeout)');
    expect(result).toContain('Fallback suggestion: SRED-Claim: MY-PROJECT');
    expect(result).toContain('ALT-1, ALT-2');
  });

  test('formats SDK error failure', () => {
    const result = formatFailure('SDK_ERROR', 'MY-PROJECT', []);
    expect(result).toContain('[SRED-GUARD] Discovery failed (SDK error)');
    expect(result).toContain('MY-PROJECT (derived from scope)');
  });

  test('formats parse error failure', () => {
    const result = formatFailure('PARSE_ERROR', 'MY-PROJECT', ['OTHER']);
    expect(result).toContain('[SRED-GUARD] Discovery failed (invalid response)');
    expect(result).toContain('OTHER');
  });

  test('formats offline failure', () => {
    const result = formatFailure('OFFLINE', 'MY-PROJECT', []);
    expect(result).toContain('Discovery unavailable (offline)');
  });

  test('includes instruction to ask user', () => {
    const result = formatFailure('NETWORK_TIMEOUT', 'MY-PROJECT', []);
    expect(result).toContain('Please ask the user');
  });
});

describe('formatSuggestion', () => {
  test('formats high confidence suggestion', () => {
    const result = formatSuggestion('MY-PROJECT', 'Matches 5 prior commits', [], 0.9);
    expect(result).toContain('[SRED-GUARD] Missing SRED-Claim trailer');
    expect(result).toContain('Suggested project: SRED-Claim: MY-PROJECT');
    expect(result).toContain('high (90%)');
    expect(result).toContain('Matches 5 prior commits');
  });

  test('formats medium confidence suggestion', () => {
    const result = formatSuggestion('MY-PROJECT', 'Partial match', [], 0.6);
    expect(result).toContain('medium (60%)');
  });

  test('formats low confidence suggestion', () => {
    const result = formatSuggestion('MY-PROJECT', 'New project', [], 0.3);
    expect(result).toContain('low (30%)');
  });

  test('includes alternatives when provided', () => {
    const result = formatSuggestion('MY-PROJECT', 'Best match', ['ALT-1', 'ALT-2'], 0.8);
    expect(result).toContain('Alternatives:');
    expect(result).toContain('- ALT-1');
    expect(result).toContain('- ALT-2');
  });
});

describe('sanitizeInput', () => {
  test('removes control characters', () => {
    const result = sanitizeInput('hello\x00world\x1Ftest');
    expect(result).toBe('helloworldtest');
  });

  test('preserves newlines and tabs', () => {
    const result = sanitizeInput('hello\nworld\ttab');
    expect(result).toBe('hello\nworld\ttab');
  });

  test('truncates long input', () => {
    const longInput = 'x'.repeat(10000);
    const result = sanitizeInput(longInput);
    expect(result.length).toBe(4096);
  });

  test('handles empty input', () => {
    expect(sanitizeInput('')).toBe('');
  });
});

describe('generateCacheKey', () => {
  test('generates consistent hash for same inputs', () => {
    const key1 = generateCacheKey('my-scope', ['file1.ts', 'file2.ts']);
    const key2 = generateCacheKey('my-scope', ['file1.ts', 'file2.ts']);
    expect(key1).toBe(key2);
  });

  test('generates different hash for different scopes', () => {
    const key1 = generateCacheKey('scope-a', []);
    const key2 = generateCacheKey('scope-b', []);
    expect(key1).not.toBe(key2);
  });

  test('generates different hash for different files', () => {
    const key1 = generateCacheKey('scope', ['file1.ts']);
    const key2 = generateCacheKey('scope', ['file2.ts']);
    expect(key1).not.toBe(key2);
  });

  test('normalizes file order', () => {
    const key1 = generateCacheKey('scope', ['b.ts', 'a.ts']);
    const key2 = generateCacheKey('scope', ['a.ts', 'b.ts']);
    expect(key1).toBe(key2);
  });

  test('returns 16 character hex string', () => {
    const key = generateCacheKey('scope', []);
    expect(key.length).toBe(16);
    expect(/^[0-9a-f]+$/.test(key)).toBe(true);
  });
});
