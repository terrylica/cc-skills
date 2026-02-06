# TypeScript Dead Code Detection with knip

Advanced usage patterns for knip in TypeScript/JavaScript projects.

## Installation

```bash
# Recommended: project-local
bun add -d knip

# Or with npm/pnpm
npm install -D knip
pnpm add -D knip
```

## Command Reference

```bash
# Initialize configuration
bunx knip --init

# Basic scan
bunx knip

# Show only specific issue types
bunx knip --include files,exports,dependencies

# Auto-fix (removes unused exports)
bunx knip --fix

# Dry-run fix (preview changes)
bunx knip --fix-type exports --dry

# Verbose output
bunx knip --debug

# JSON output for CI
bunx knip --reporter json
```

## Configuration (knip.json)

```json
{
  "$schema": "https://unpkg.com/knip@5/schema.json",
  "entry": ["src/index.ts", "src/cli.ts"],
  "project": ["src/**/*.ts", "src/**/*.tsx"],
  "ignore": ["**/*.test.ts", "**/*.spec.ts", "**/fixtures/**", "**/mocks/**"],
  "ignoreDependencies": ["@types/*", "prettier", "eslint-*"],
  "ignoreExportsUsedInFile": true
}
```

## Monorepo Configuration

```json
{
  "$schema": "https://unpkg.com/knip@5/schema.json",
  "workspaces": {
    "packages/*": {
      "entry": ["src/index.ts"],
      "project": ["src/**/*.ts"]
    },
    "apps/web": {
      "entry": ["src/main.tsx", "src/pages/**/*.tsx"],
      "project": ["src/**/*.{ts,tsx}"]
    }
  }
}
```

## What knip Detects

| Category            | Description                             | Auto-fix |
| ------------------- | --------------------------------------- | -------- |
| Unused files        | Files not imported anywhere             | No       |
| Unused exports      | Exported but never imported             | Yes      |
| Unused dependencies | Listed in package.json but not imported | No       |
| Unused devDeps      | Dev dependencies not used in scripts    | No       |
| Unlisted deps       | Imported but not in package.json        | No       |
| Duplicate exports   | Same thing exported multiple times      | Yes      |

## Framework Plugins

knip has built-in support for common frameworks:

```json
{
  "next": true,
  "remix": true,
  "astro": true,
  "vite": true,
  "vitest": true,
  "jest": true,
  "storybook": true
}
```

These automatically configure entry points and ignore patterns.

## Handling False Positives

### Dynamic Imports

```json
{
  "entry": ["src/index.ts", "src/plugins/*.ts"]
}
```

### Re-exports (barrel files)

```json
{
  "ignoreExportsUsedInFile": true,
  "ignore": ["**/index.ts"]
}
```

### Type-only Exports

knip v5+ handles type exports correctly. No special config needed.

### Ignore Specific Exports

```typescript
// Tells knip this export is intentionally unused
/** @internal */
export function _internalHelper() {}

// Or use comment
// knip-ignore
export const DEPRECATED_CONSTANT = 42;
```

## Migration from ts-prune

ts-prune is in maintenance mode. To migrate:

```bash
# Remove ts-prune
bun remove ts-prune

# Add knip
bun add -d knip

# Initialize
bunx knip --init

# ts-prune output format compatibility
bunx knip --reporter compact
```

## CI Integration

```json
// package.json
{
  "scripts": {
    "dead-code": "knip",
    "dead-code:fix": "knip --fix",
    "dead-code:ci": "knip --reporter json --no-exit-code"
  }
}
```

## Comparison: knip vs ts-prune

| Feature             | knip   | ts-prune    |
| ------------------- | ------ | ----------- |
| Maintained          | Active | Maintenance |
| Unused dependencies | Yes    | No          |
| Unused files        | Yes    | No          |
| Auto-fix            | Yes    | No          |
| Monorepo support    | Native | Limited     |
| Framework plugins   | 50+    | None        |
| Performance         | Fast   | Fast        |

## Sources

- [knip documentation](https://knip.dev/)
- [Effective TypeScript: Use knip](https://effectivetypescript.com/2023/07/29/knip/)
- [ts-prune to knip migration](https://knip.dev/explanations/comparison-and-migration)
- [Why knip over ts-prune](https://levelup.gitconnected.com/dead-code-detection-in-typescript-projects-why-we-chose-knip-over-ts-prune-8feea827da35)
