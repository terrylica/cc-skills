---
name: rust-dependency-audit
description: "Rust dependency audit - cargo-audit (vulnerabilities), cargo-deny (licenses and advisories), cargo-vet (supply chain), cargo-outdated and cargo-upgrades (freshness). TRIGGERS - cargo outdated, dependency audit, vulnerability scan, license check, cargo update, supply chain, crate freshness."
allowed-tools: Read, Grep, Bash
---

# Rust Dependency Audit

Comprehensive dependency audit workflow using four complementary tools: freshness checking, vulnerability scanning, license/advisory compliance, and supply chain verification.

## When to Use

- Before a release (full audit pipeline)
- After `cargo update` (verify no new vulnerabilities)
- CI pipeline setup (automated dependency checks)
- License compliance review (open source projects)
- Supply chain security assessment

## Four-Tool Audit Workflow

Run in this order — each tool catches different issues:

```bash
# 1. Freshness — what's outdated?
cargo outdated

# 2. Vulnerabilities — any known CVEs?
cargo audit

# 3. Licenses + Advisories — compliance check
cargo deny check

# 4. Supply Chain — who audited these crates?
cargo vet
```

### Quick Assessment

```bash
# One-liner: run all four (stop on first failure)
cargo outdated && cargo audit && cargo deny check && cargo vet
```

## Freshness: Finding Outdated Dependencies

Three tools for different needs:

| Tool                         | Install                        | Purpose                                                  | Best For            |
| ---------------------------- | ------------------------------ | -------------------------------------------------------- | ------------------- |
| `cargo-outdated`             | `cargo install cargo-outdated` | Full outdated report with compatible/latest versions     | Comprehensive audit |
| `cargo-upgrades`             | `cargo install cargo-upgrades` | Lightweight — only shows incompatible (breaking) updates | Quick check         |
| `cargo upgrade` (cargo-edit) | `cargo install cargo-edit`     | Actually updates `Cargo.toml` versions                   | Performing updates  |

```bash
# Show all outdated deps (compatible + incompatible)
cargo outdated --root-deps-only

# Show only breaking updates needed
cargo upgrades

# Actually update Cargo.toml (dry run first)
cargo upgrade --dry-run
cargo upgrade --incompatible

# Nightly: native cargo support (experimental)
cargo +nightly update --breaking
```

**Recommendation**: Use `cargo-upgrades` for quick checks, `cargo-outdated` for full audits, `cargo upgrade` (cargo-edit) when ready to actually update.

See [cargo-outdated reference](./references/cargo-outdated-guide.md).

## Security: Vulnerability Scanning

### cargo-audit (RUSTSEC Database)

```bash
# Scan for known vulnerabilities
cargo audit

# Auto-fix where possible (updates Cargo.lock)
cargo audit fix

# Binary scanning (audit compiled binaries)
cargo audit bin ./target/release/my-binary

# Custom config (ignore specific advisories)
# Create audit.toml:
```

```toml
# audit.toml
[advisories]
ignore = [
    "RUSTSEC-YYYY-NNNN",  # Reason for ignoring
]
```

See [cargo-audit reference](./references/cargo-audit-guide.md).

### cargo-deny (Advisories + More)

cargo-deny's advisory check complements cargo-audit with additional sources:

```bash
# Check advisories only
cargo deny check advisories

# All checks (advisories + licenses + bans + sources)
cargo deny check
```

See the License section below for full cargo-deny configuration.

## License: Compliance Checking

### cargo-deny License Check

```toml
# deny.toml
[licenses]
allow = [
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-3.0",
]
confidence-threshold = 0.8

[[licenses.clarify]]
name = "ring"
expression = "MIT AND ISC AND OpenSSL"
license-files = [{ path = "LICENSE", hash = 0xbd0eed23 }]
```

```bash
# Check licenses
cargo deny check licenses

# Generate deny.toml template
cargo deny init
```

See [cargo-deny reference](./references/cargo-deny-guide.md).

## Supply Chain: Audit Verification

### cargo-vet (Mozilla)

cargo-vet tracks which crates have been audited and by whom:

```bash
# Check supply chain status
cargo vet

# Audit a specific crate (certify you've reviewed it)
cargo vet certify <crate> <version>

# Import audits from trusted organizations
cargo vet trust --all mozilla
cargo vet trust --all google

# See what needs auditing
cargo vet suggest
```

Key files:

- `supply-chain/audits.toml` — Your audits
- `supply-chain/imports.lock` — Imported audits
- `supply-chain/config.toml` — Trusted sources

See [cargo-vet reference](./references/cargo-vet-guide.md).

## Combined CI Workflow (GitHub Actions)

```yaml
name: Dependency Audit
on:
  pull_request:
  schedule:
    - cron: "0 6 * * 1" # Weekly Monday 6am

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable

      - name: cargo-audit
        run: |
          cargo install cargo-audit
          cargo audit

      - name: cargo-deny
        uses: EmbarkStudios/cargo-deny-action@v2

      - name: cargo-vet
        run: |
          cargo install cargo-vet
          cargo vet

      - name: cargo-outdated
        run: |
          cargo install cargo-outdated
          cargo outdated --root-deps-only --exit-code 1
```

## Reference Documents

- [cargo-audit-guide.md](./references/cargo-audit-guide.md) — Vulnerability scanning
- [cargo-deny-guide.md](./references/cargo-deny-guide.md) — License + advisory compliance
- [cargo-outdated-guide.md](./references/cargo-outdated-guide.md) — Freshness + alternatives
- [cargo-vet-guide.md](./references/cargo-vet-guide.md) — Supply chain audit

## Troubleshooting

| Problem                             | Solution                                                    |
| ----------------------------------- | ----------------------------------------------------------- |
| `cargo audit` stale database        | Run `cargo audit fetch` to update RUSTSEC DB                |
| `cargo deny` false positive license | Add `[[licenses.clarify]]` entry in `deny.toml`             |
| `cargo vet` too many unaudited      | Import trusted org audits: `cargo vet trust --all mozilla`  |
| `cargo outdated` shows yanked       | Run `cargo update` first to refresh `Cargo.lock`            |
| Private registry crates             | Configure `[sources]` in `deny.toml` for private registries |
| Workspace vs single crate           | Most tools support `--workspace` flag                       |
