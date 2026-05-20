#!/usr/bin/env bash
# validate-s3-upload.sh - S3 upload/download verification
# ADR: /docs/adr/2026-01-02-session-chronicle-s3-sharing.md

set -euo pipefail

# iter-38 SC2034: removed unused SCRIPT_DIR declaration (dead since script
# inception — never referenced anywhere in the file)
TEMP_DIR=$(mktemp -d)
# iter-38 SC2064: single quotes so $TEMP_DIR expands at SIGNAL time, not
# at trap-registration time. Pre-iter-38: if TEMP_DIR were ever reassigned
# between this line and EXIT, the trap would rm the OLD path and leave the
# NEW one stale. Also quoted "$TEMP_DIR" to handle spaces in paths.
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "=== S3 Upload/Download Validation ==="

OP_VAULT="Employee"
OP_ITEM_ID="ise47dxnkftmxopupffavsgby4"
S3_BUCKET="eonlabs-findings"
S3_TEST_PREFIX="sessions-validation-test"
TEST_TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# iter-38 SC2155 (iter-37 leftover): split declare-from-assign on
# `export VAR=$(op read ...)`. Test-scripts/ path was filtered out of
# iter-37's audit so this leftover slipped through. Same hazard:
# silent op-read failure → empty AWS creds → cryptic "Unable to locate
# credentials" 15-60 min later.
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
AWS_ACCESS_KEY_ID=$(op read "op://$OP_VAULT/$OP_ITEM_ID/access key id")
AWS_SECRET_ACCESS_KEY=$(op read "op://$OP_VAULT/$OP_ITEM_ID/secret access key")
AWS_DEFAULT_REGION="us-west-2"

# Verify AWS identity
IDENTITY=$(aws sts get-caller-identity --output json 2>&1)
if [[ "$IDENTITY" == *"error"* ]]; then
  echo "✗ AWS Identity: FAILED"
  echo "  Error: $IDENTITY"
  exit 1
fi
ACCOUNT=$(echo "$IDENTITY" | jq -r '.Account')
USER_ARN=$(echo "$IDENTITY" | jq -r '.Arn')
echo "✓ AWS Identity: $USER_ARN"

# Verify expected account (company account)
if [[ "$ACCOUNT" != "050214414362" ]]; then
  echo "✗ AWS Account: WRONG (expected 050214414362, got $ACCOUNT)"
  exit 1
fi
echo "✓ AWS Account: $ACCOUNT"

# Create test file
echo '{"test":"validation","timestamp":"'$TEST_TIMESTAMP'"}' > "$TEMP_DIR/test-upload.json"
brotli -9 -o "$TEMP_DIR/test-upload.json.br" "$TEMP_DIR/test-upload.json"

# Upload test file
S3_PATH="s3://$S3_BUCKET/$S3_TEST_PREFIX/$TEST_TIMESTAMP/test-upload.json.br"
if aws s3 cp "$TEMP_DIR/test-upload.json.br" "$S3_PATH" --quiet; then
  echo "✓ S3 Upload: SUCCESS"
else
  echo "✗ S3 Upload: FAILED"
  exit 1
fi

# Download and verify
if aws s3 cp "$S3_PATH" "$TEMP_DIR/downloaded.json.br" --quiet; then
  echo "✓ S3 Download: SUCCESS"
else
  echo "✗ S3 Download: FAILED"
  exit 1
fi

# Verify integrity
if diff -q "$TEMP_DIR/test-upload.json.br" "$TEMP_DIR/downloaded.json.br" >/dev/null; then
  echo "✓ S3 Round-trip integrity: VERIFIED"
else
  echo "✗ S3 Round-trip integrity: FAILED"
  exit 1
fi

# Decompress downloaded file
brotli -d -o "$TEMP_DIR/downloaded.json" "$TEMP_DIR/downloaded.json.br"
DOWNLOADED_TIMESTAMP=$(jq -r '.timestamp' "$TEMP_DIR/downloaded.json")
if [[ "$DOWNLOADED_TIMESTAMP" == "$TEST_TIMESTAMP" ]]; then
  echo "✓ Content integrity: VERIFIED (timestamp matches)"
else
  echo "✗ Content integrity: FAILED"
  exit 1
fi

# Cleanup test file from S3
aws s3 rm "$S3_PATH" --quiet
echo "✓ S3 Cleanup: Test file removed"

echo ""
echo "S3 upload/download validation PASSED"
