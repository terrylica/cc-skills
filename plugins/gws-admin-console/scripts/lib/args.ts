// args.ts — a small, declarative flag parser. The FlagSpec list is also the machine-readable CLI description
// (`--help --json`), so the flags an agent sees and the flags the parser accepts cannot drift apart.

export interface FlagSpec {
  name: string; // without the leading --
  type: "string" | "bool" | "int";
  help: string;
  required?: boolean;
  default?: string | number | boolean;
  choices?: string[];
  env?: string; // environment variable that supplies a default
}

export type Flags = Record<string, string | number | boolean | undefined>;

export class UsageError extends Error {}

export function parseFlags(argv: string[], specs: FlagSpec[], env: Record<string, string | undefined> = {}): Flags {
  const byName = new Map(specs.map((s) => [s.name, s]));
  const out: Flags = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (!a.startsWith("--")) throw new UsageError(`unexpected argument "${a}"`);
    let name = a.slice(2);
    let inline: string | undefined;
    const eq = name.indexOf("=");
    if (eq >= 0) {
      inline = name.slice(eq + 1);
      name = name.slice(0, eq);
    }
    const s = byName.get(name);
    if (!s) throw new UsageError(`unknown flag --${name}`);
    if (s.type === "bool") {
      if (inline !== undefined) throw new UsageError(`--${name} takes no value`);
      out[name] = true;
      continue;
    }
    const v = inline ?? argv[++i];
    if (v === undefined || (inline === undefined && v.startsWith("--"))) throw new UsageError(`--${name} needs a value`);
    out[name] = coerce(s, v);
  }
  for (const s of specs) {
    if (out[s.name] !== undefined) continue;
    const e = s.env ? env[s.env] : undefined;
    if (e !== undefined && e !== "") out[s.name] = coerce(s, e);
    else if (s.default !== undefined) out[s.name] = s.default;
    else if (s.required) throw new UsageError(`--${s.name} is required`);
  }
  return out;
}

function coerce(s: FlagSpec, v: string): string | number {
  if (s.choices && !s.choices.includes(v)) throw new UsageError(`--${s.name} must be one of ${s.choices.join(", ")} (got "${v}")`);
  if (s.type === "int") {
    if (!/^\d+$/.test(v)) throw new UsageError(`--${s.name} must be a whole number (got "${v}")`);
    return Number(v);
  }
  return v;
}

export function helpText(specs: FlagSpec[]): string {
  return specs
    .map((s) => {
      const arg = s.type === "bool" ? "" : s.choices ? ` <${s.choices.join("|")}>` : ` <${s.type === "int" ? "n" : "value"}>`;
      const extra = [s.required ? "required" : "", s.default !== undefined ? `default ${s.default}` : "", s.env ? `env ${s.env}` : ""].filter(Boolean).join("; ");
      return `  --${s.name}${arg}\n      ${s.help}${extra ? ` (${extra})` : ""}`;
    })
    .join("\n");
}
