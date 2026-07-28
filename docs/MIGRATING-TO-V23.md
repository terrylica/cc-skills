<!-- SSoT-OK — a migration guide's entire job is to name the exact versions a
     consumer is moving between, so the version-guard's single-source-of-truth
     rule does not apply here. Every version below is a historical fact about a
     published release, not a pin that could drift out of sync with a manifest. -->

# Migrating to cc-skills v23.0.0

**Audience:** anyone who installs this marketplace (`claude plugin marketplace add terrylica/cc-skills`).

v23.0.0 carries three breaking changes. Two of them were **implemented** in
v22.19.0 but shipped there without a major-version signal — see
[Why some of this arrived in v22.19.0](#why-some-of-this-arrived-in-v22190)
below. If you are upgrading from v22.18.0 or earlier, everything on this page
is new to you. If you already took v22.19.0, you have been running the first
two changes since then; only the third is genuinely new.

---

## 1. TypeScript below 7 is blocked by default, with no configuration

Two `PreToolUse` guards in `itp-hooks` now refuse to let a pre-7 TypeScript
enter a project:

| Guard                                                | Blocks                                                                                                                           |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `pretooluse-typescript-version-guard`                | `Write`/`Edit` of a `package.json` that declares `typescript` below 7, and `tsconfig.json` options TypeScript 7 rejects outright |
| `pretooluse-typescript-legacy-install-command-guard` | `Bash` install commands that would install a pre-7 TypeScript — `npm i typescript@5…`, `bun add typescript@^6`, and equivalents  |

**These are on by default and there is no setting to turn them off.** That is
deliberate: an opt-in guard protects only the people who already knew to opt in.

### What still passes

- `"typescript": "latest"` — the recommended declaration.
- Any explicit 7.x range.
- The sanctioned dual-install compat alias, for tooling that embeds the
  compiler programmatically (Volar-based tooling such as `astro check`,
  `vue-tsc` and `svelte-check`; Angular template checking; typescript-eslint;
  `ts-morph`). TypeScript 7.0 ships no programmatic API — 7.1 will — so this is
  a real, temporary need, and it is recognized rather than blocked:

  ```json
  {
    "devDependencies": {
      "@typescript/native": "npm:typescript@latest",
      "typescript": "npm:@typescript/typescript6@^6.0.2"
    }
  }
  ```

  That yields `tsc` = 7.x and `tsc6` = 6.x.

### The escape hatch

To pin a pre-7 TypeScript deliberately, put the marker `ALLOW-LEGACY-TS`
anywhere in the file being written, or in the Bash command:

```jsonc
// ALLOW-LEGACY-TS
```

```bash
# ALLOW-LEGACY-TS
npm install typescript@5.9.3
```

The marker is file-wide and case-sensitive, and needs no reason string. It is
documented alongside every other marker in
[`docs/marketplace-escape-hatch-marker-reference.md`](marketplace-escape-hatch-marker-reference.md).

### Two traps worth knowing before you migrate

1. **`bun add -d typescript@latest` does not write `"latest"`.** It resolves and
   writes a caret range. Rewrite the specifier afterwards and reinstall if you
   want the floating declaration.
2. **`"latest"` does not mean current.** Installs resolve from the committed
   lockfile, not the registry, so a package declaring `"latest"` stays frozen
   at whatever the lockfile last recorded. Two packages in this very repo had
   declared `"latest"` for months and were still installing a 6.x compiler.
   Only an explicit `bun update typescript` / `npm update typescript` moves it.

   A corollary that has bitten us: under npm, `@typescript-eslint/eslint-plugin`
   peer ranges can drag `typescript@latest` _down_ to a 6.x release in Next.js
   repos. The type-check gate then goes green under TypeScript 6 and the green
   means nothing. **A migration is not done until
   `./node_modules/.bin/tsc --version` prints 7.x.** The remedy npm supports is
   an `overrides` entry in the root `package.json`.

---

## 2. `/mise:sred-commit` is removed

The SR&ED commit programme is retired. Removed:

- the `/mise:sred-commit` skill,
- the `sred-commit-guard` PreToolUse hook and its tests,
- the `sred-discovery` library, its tests, and the integration script.

**If you invoke `/mise:sred-commit`, it no longer exists.** Commits no longer
require `SRED-Type:` / `SRED-Claim:` trailers, and nothing validates them.

Existing history is untouched: `CHANGELOG.md` keeps its record, and the
governing ADR is marked `superseded` rather than deleted, so the decision trail
survives.

---

## 3. Breaking changes now actually cut a major release

This one is new in v23.0.0 and is the reason the two changes above are being
announced twice.

`release.config.cjs` builds on the Angular preset, which predates the `!`
shorthand and does not treat `feat!:` or `feat(scope)!:` as breaking. Separately,
Conventional Commits requires the exact footer token `BREAKING CHANGE` (or
`BREAKING-CHANGE`); a body opening `BREAKING:` is read as ordinary prose.

Both gaps are now closed: a `{ breaking: true, release: "major" }` release rule
catches the `!` shorthand, and `parserOpts.noteKeywords` accepts a bare
`BREAKING` keyword. The same `noteKeywords` list is set on **both**
`commit-analyzer` and `release-notes-generator` — they parse the range
independently, and setting it on only one yields a split brain where the version
bumps correctly but the changelog carries no BREAKING CHANGES section.

**Impact if you pin a caret range:** releases that should have been major will
now be major. You get correct semver signalling instead of an unannounced
breaking change buried inside a minor bump.

---

## Why some of this arrived in v22.19.0

The two commits implementing changes 1 and 2 were both authored with a `!` in
the subject and a body opening `BREAKING:`. Because of the parser gaps described
in change 3, semantic-release classified both as ordinary features and cut
**v22.19.0** — a minor.

The published v22.19.0 tag is left in place rather than rewritten; retracting a
pushed tag breaks every consumer that already resolved it. v23.0.0 is the
honest announcement, and change 3 ensures the failure mode cannot recur.

**Practical upgrade advice:** treat **v22.19.0 as if it were v23.0.0**. If you
are pinned to a caret range on 22, you may have already received the guards
without a major signal — check whether your builds started blocking pre-7
TypeScript.

---

## Upgrade checklist

- [ ] Confirm `./node_modules/.bin/tsc --version` prints 7.x in each project — not just that `package.json` looks right.
- [ ] Replace pre-7 `typescript` specifiers with `"latest"`, or add the dual-install alias if you embed the compiler API.
- [ ] Delete `tsconfig.json` options TypeScript 7 removed: `baseUrl`, `downlevelIteration`, `target: "es5"`, `moduleResolution: node|node10|classic`, `module: amd|umd|systemjs|none`, and the explicit `false` forms of `esModuleInterop`, `allowSyntheticDefaultImports`, `alwaysStrict`. Note `esModuleInterop: true` is fine — only the explicit `false` is rejected.
- [ ] If you deleted `baseUrl`, prefix every `paths` value with `./` or `../`, or TypeScript 7 rejects them with `TS5090: Non-relative paths are not allowed`.
- [ ] Add an explicit `types` array. TypeScript 7 defaults it to `[]`, so ambient globals silently stop resolving (`TS2591: Cannot find name 'process'`). Use bare names: `["bun"]`, `["node", "react", "react-dom"]`.
- [ ] Stop calling `/mise:sred-commit` and drop `SRED-*` trailers from any commit templates.
- [ ] If you deliberately need a pre-7 TypeScript, add `ALLOW-LEGACY-TS` and record why.
