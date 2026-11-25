# Session Chronicle Tests

Validation scripts and fixtures for session-chronicle's local archiving and commit-message output. Everything runs on this machine; nothing is uploaded.

## Running Validations

Run all validations:

```bash
cd plugins/devops-tools/skills/session-chronicle
bash tests/scripts/validate-e2e.sh
```

Run individual validations:

```bash
bash tests/scripts/validate-prerequisites.sh
bash tests/scripts/validate-brotli.sh
bash tests/scripts/validate-extract-chain.sh
bash tests/scripts/validate-commit-format.sh
```

## Validation Scripts

| Script                      | Purpose                                                        |
| --------------------------- | -------------------------------------------------------------- |
| `validate-prerequisites.sh` | Tool installation check (brotli, jq)                           |
| `validate-brotli.sh`        | Compression round-trip test                                    |
| `validate-extract-chain.sh` | extract_session_chain.sh writes `.jsonl.br` archives           |
| `validate-commit-format.sh` | generate_commit_message.sh output, including partial manifests |
| `validate-e2e.sh`           | Runs all of the above                                          |

## Test Fixtures

| File                     | Description                   |
| ------------------------ | ----------------------------- |
| `mock-session.jsonl`     | Synthetic Claude Code session |
| `mock-uuid-chain.jsonl`  | Pre-traced UUID chain         |
| `expected-manifest.json` | Expected manifest output      |

## Prerequisites

```bash
brew install brotli jq
```

## Use Cases

- **Regression testing**: Re-run after any changes to session-chronicle
- **Onboarding**: New contributors can verify their setup
- **CI-local validation**: Manual pre-push checks
