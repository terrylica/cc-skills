#!/usr/bin/env bun
/**
 * Zod Schema Registry for Claude Code tool inputs.
 *
 * Defines strict schemas for every tool that hooks may return `updatedInput` for.
 * Tools NOT in this registry cannot receive updatedInput — the safest default.
 *
 * Key design: `.strict()` on every schema rejects unknown properties automatically.
 * This prevents schema corruption bugs (e.g., injecting `env` into AskUserQuestion).
 *
 * Schemas sourced from official Claude Code hooks reference.
 *
 * Analogy: Kubernetes admission webhooks validate mutation output against the
 * resource schema. This does the same for Claude Code hook updatedInput.
 *
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/15897 (updatedInput aggregation bug)
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/13439 (schema corruption via env injection)
 */

import { z } from "zod";

/** Bash tool input schema */
export const BashSchema = z.object({
  command: z.string(),
  description: z.string().optional(),
  timeout: z.number().optional(),
  run_in_background: z.boolean().optional(),
}).strict();

/** Read tool input schema */
export const ReadSchema = z.object({
  file_path: z.string(),
  offset: z.number().optional(),
  limit: z.number().optional(),
}).strict();

/** Write tool input schema */
export const WriteSchema = z.object({
  file_path: z.string(),
  content: z.string(),
}).strict();

/** Edit tool input schema */
export const EditSchema = z.object({
  file_path: z.string(),
  old_string: z.string(),
  new_string: z.string(),
  replace_all: z.boolean().optional(),
}).strict();

/** Glob tool input schema */
export const GlobSchema = z.object({
  pattern: z.string(),
  path: z.string().optional(),
}).strict();

/** Grep tool input schema */
export const GrepSchema = z.object({
  pattern: z.string(),
  path: z.string().optional(),
  glob: z.string().optional(),
  type: z.string().optional(),
  output_mode: z.enum(["content", "files_with_matches", "count"]).optional(),
  "-A": z.number().optional(),
  "-B": z.number().optional(),
  "-C": z.number().optional(),
  "-i": z.boolean().optional(),
  "-n": z.boolean().optional(),
  context: z.number().optional(),
  head_limit: z.number().optional(),
  offset: z.number().optional(),
  multiline: z.boolean().optional(),
}).strict();

/** NotebookEdit tool input schema */
export const NotebookEditSchema = z.object({
  notebook_path: z.string(),
  new_source: z.string(),
  cell_id: z.string().optional(),
  cell_type: z.enum(["code", "markdown"]).optional(),
  edit_mode: z.enum(["replace", "insert", "delete"]).optional(),
}).strict();

/** LSP tool input schema */
export const LSPSchema = z.object({
  operation: z.string(),
  filePath: z.string(),
  line: z.number(),
  character: z.number(),
}).strict();

/** MCP shell_execute tool input schema */
export const McpShellExecuteSchema = z.object({
  command: z.array(z.string()),
  directory: z.string().optional(),
  timeout: z.number().optional(),
}).strict();

/**
 * Registry mapping tool names to their Zod schemas.
 * Tools NOT in this registry → unknown → allow() without updatedInput (safe default).
 */
export const TOOL_SCHEMAS: Record<string, z.ZodTypeAny> = {
  Bash: BashSchema,
  Read: ReadSchema,
  Write: WriteSchema,
  Edit: EditSchema,
  Glob: GlobSchema,
  Grep: GrepSchema,
  NotebookEdit: NotebookEditSchema,
  LSP: LSPSchema,
  mcp__shell__shell_execute: McpShellExecuteSchema,
};

/**
 * Validate updatedInput against the target tool's schema.
 *
 * @returns validated data if valid, null if invalid or unknown tool
 */
export function validateToolInput(
  toolName: string,
  updatedInput: unknown,
): { valid: true; data: Record<string, unknown> } | { valid: false; error: string } {
  const schema = TOOL_SCHEMAS[toolName];
  if (!schema) {
    return { valid: false, error: `No schema for tool "${toolName}" — updatedInput not allowed` };
  }
  const result = schema.safeParse(updatedInput);
  if (!result.success) {
    const issues = result.error.issues.map((i) =>
      `${i.path.map(String).join(".")}: ${i.message}`
    ).join("; ");
    return { valid: false, error: `Schema validation failed for ${toolName}: ${issues}` };
  }
  return { valid: true, data: result.data as Record<string, unknown> };
}
