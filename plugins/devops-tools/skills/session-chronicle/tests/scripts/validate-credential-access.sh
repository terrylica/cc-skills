#!/usr/bin/env bash
# validate-credential-access.sh - 1Password credential access test
# ADR: /docs/adr/2026-01-02-session-chronicle-s3-sharing.md

set -euo pipefail

echo "=== 1Password Credential Access Validation ==="

OP_ITEM_ID="uy6sbqwno7cofdapusds5f6aea"

# Check 1Password sign-in status
if ! op whoami &>/dev/null; then
  echo "✗ 1Password: NOT SIGNED IN"
  echo "  Run: op signin"
  exit 1
fi
echo "✓ 1Password: Signed in"

# Check Engineering vault access
if op vault list 2>/dev/null | grep -q "Engineering"; then
  echo "✓ Engineering vault: Accessible"
else
  echo "✗ Engineering vault: NOT ACCESSIBLE"
  exit 1
fi

# Check specific item access
ACCESS_KEY=$(op read "op://Engineering/$OP_ITEM_ID/access key id" 2>&1)
if [[ "$ACCESS_KEY" == AKIA* ]]; then
  echo "✓ AWS Access Key ID: Retrieved (${ACCESS_KEY:0:8}...)"
else
  echo "✗ AWS Access Key ID: FAILED"
  echo "  Error: $ACCESS_KEY"
  exit 1
fi

SECRET_KEY=$(op read "op://Engineering/$OP_ITEM_ID/secret access key" 2>&1)
if [[ ${#SECRET_KEY} -gt 20 ]]; then
  echo "✓ AWS Secret Access Key: Retrieved (${#SECRET_KEY} chars)"
else
  echo "✗ AWS Secret Access Key: FAILED"
  exit 1
fi

echo ""
echo "1Password credential access validation PASSED"
