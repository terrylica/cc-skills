#!/usr/bin/env bun
/**
 * Tool Schema Registry for Claude Code tool inputs.
 *
 * Defines strict schemas for every tool that hooks may return `updatedInput` for.
 * Tools NOT in this registry cannot receive updatedInput — the safest default.
 *
 * Strict mode rejects unknown properties to prevent schema corruption bugs
 * (e.g., injecting `env` into AskUserQuestion).
 *
 * Schemas sourced from official Claude Code hooks reference.
 *
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/15897 (updatedInput aggregation bug)
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/13439 (schema corruption via env injection)
 *
 * Hand-rolled to avoid the zod dependency — Claude Code's plugin install cache
 * has no node_modules, so external deps are unresolvable at hook runtime.
 */

type FieldSpec =
  | { type: "string"; optional?: boolean }
  | { type: "number"; optional?: boolean }
  | { type: "boolean"; optional?: boolean }
  | { type: "array-of-string"; optional?: boolean }
  | { type: "enum"; values: readonly string[]; optional?: boolean };

export interface SafeParseResult {
  success: boolean;
  data?: Record<string, unknown>;
  error?: { issues: Array<{ path: string[]; message: string }> };
}

class StrictSchema {
  constructor(private readonly fields: Record<string, FieldSpec>) {}

  safeParse(input: unknown): SafeParseResult {
    if (input === null || typeof input !== "object" || Array.isArray(input)) {
      return { success: false, error: { issues: [{ path: [], message: "Expected object" }] } };
    }
    const obj = input as Record<string, unknown>;
    const issues: Array<{ path: string[]; message: string }> = [];

    for (const key of Object.keys(obj)) {
      if (!(key in this.fields)) {
        issues.push({ path: [key], message: `Unrecognized key "${key}"` });
      }
    }

    for (const [key, spec] of Object.entries(this.fields)) {
      const v = obj[key];
      if (v === undefined) {
        if (!spec.optional) issues.push({ path: [key], message: "Required" });
        continue;
      }
      switch (spec.type) {
        case "string":
          if (typeof v !== "string") issues.push({ path: [key], message: `Expected string, got ${typeof v}` });
          break;
        case "number":
          if (typeof v !== "number") issues.push({ path: [key], message: `Expected number, got ${typeof v}` });
          break;
        case "boolean":
          if (typeof v !== "boolean") issues.push({ path: [key], message: `Expected boolean, got ${typeof v}` });
          break;
        case "array-of-string":
          if (!Array.isArray(v)) {
            issues.push({ path: [key], message: `Expected array, got ${typeof v}` });
          } else {
            for (let i = 0; i < v.length; i++) {
              if (typeof v[i] !== "string") issues.push({ path: [key, String(i)], message: "Expected string" });
            }
          }
          break;
        case "enum":
          if (!spec.values.includes(v as string)) {
            issues.push({ path: [key], message: `Expected one of [${spec.values.join(", ")}]` });
          }
          break;
      }
    }

    return issues.length > 0 ? { success: false, error: { issues } } : { success: true, data: obj };
  }
}

const str = (optional = false): FieldSpec => ({ type: "string", optional });
const num = (optional = false): FieldSpec => ({ type: "number", optional });
const bool = (optional = false): FieldSpec => ({ type: "boolean", optional });
const strArr = (optional = false): FieldSpec => ({ type: "array-of-string", optional });
const enm = (values: readonly string[], optional = false): FieldSpec => ({ type: "enum", values, optional });

/** Bash tool input schema */
export const BashSchema = new StrictSchema({
  command: str(),
  description: str(true),
  timeout: num(true),
  run_in_background: bool(true),
});

/** Read tool input schema */
export const ReadSchema = new StrictSchema({
  file_path: str(),
  offset: num(true),
  limit: num(true),
});

/** Write tool input schema */
export const WriteSchema = new StrictSchema({
  file_path: str(),
  content: str(),
});

/** Edit tool input schema */
export const EditSchema = new StrictSchema({
  file_path: str(),
  old_string: str(),
  new_string: str(),
  replace_all: bool(true),
});

/** Glob tool input schema */
export const GlobSchema = new StrictSchema({
  pattern: str(),
  path: str(true),
});

/** Grep tool input schema */
export const GrepSchema = new StrictSchema({
  pattern: str(),
  path: str(true),
  glob: str(true),
  type: str(true),
  output_mode: enm(["content", "files_with_matches", "count"], true),
  "-A": num(true),
  "-B": num(true),
  "-C": num(true),
  "-i": bool(true),
  "-n": bool(true),
  context: num(true),
  head_limit: num(true),
  offset: num(true),
  multiline: bool(true),
});

/** NotebookEdit tool input schema */
export const NotebookEditSchema = new StrictSchema({
  notebook_path: str(),
  new_source: str(),
  cell_id: str(true),
  cell_type: enm(["code", "markdown"], true),
  edit_mode: enm(["replace", "insert", "delete"], true),
});

/** LSP tool input schema */
export const LSPSchema = new StrictSchema({
  operation: str(),
  filePath: str(),
  line: num(),
  character: num(),
});

/** MCP shell_execute tool input schema */
export const McpShellExecuteSchema = new StrictSchema({
  command: strArr(),
  directory: str(true),
  timeout: num(true),
});

/**
 * Registry mapping tool names to their schemas.
 * Tools NOT in this registry → unknown → allow() without updatedInput (safe default).
 */
export const TOOL_SCHEMAS: Record<string, StrictSchema> = {
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
    const issues = (result.error?.issues ?? []).map((i) =>
      `${i.path.map(String).join(".")}: ${i.message}`
    ).join("; ");
    return { valid: false, error: `Schema validation failed for ${toolName}: ${issues}` };
  }
  return { valid: true, data: result.data as Record<string, unknown> };
}
