**Skill**: [semantic-release](../SKILL.md)

## Monorepo Support (pnpm/npm Workspaces)

> **macOS Note**: Use global `semantic-release` to avoid Gatekeeper blocking `.node` files. See [Troubleshooting](./troubleshooting.md#macos-gatekeeper-blocks-node-files).

### pnpm Workspaces

Install pnpm plugin:

```bash
npm install --save-dev @anolilab/semantic-release-pnpm
```

Run release across workspaces:

```bash
# macOS (global install recommended)
pnpm -r --workspace-concurrency=1 exec -- semantic-release --no-ci

# Linux/CI (npx works without Gatekeeper issues)
pnpm -r --workspace-concurrency=1 exec -- npx --no-install semantic-release
```

### npm Workspaces

Use multi-semantic-release:

```bash
npm install --save-dev @anolilab/multi-semantic-release

# macOS (global install recommended)
multi-semantic-release

# Linux/CI
npx multi-semantic-release
```
