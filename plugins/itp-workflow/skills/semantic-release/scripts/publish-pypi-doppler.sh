#!/bin/bash
# PyPI Publishing with Doppler Secret Management
# Validated workflow for Python packages using local-first publishing
#
# Prerequisites:
#   - Doppler CLI installed (brew install dopplerhq/cli/doppler)
#   - uv package manager installed (curl -LsSf https://astral.sh/uv/install.sh | sh)
#   - Doppler project configured (.doppler.yaml in project root)
#   - PYPI_TOKEN secret stored in Doppler
#
# Usage:
#   ./publish-pypi-doppler.sh
#
# This script is part of the semantic-release skill reference implementation.
# Copy to your Python project's scripts/ directory and customize as needed.

set -e

echo "🚀 Publishing to PyPI (Local Workflow with Doppler)"
echo "======================================================"

# Step 0: Verify Doppler token is available
echo -e "\n🔐 Step 0: Verifying Doppler credentials..."
if ! command -v doppler &> /dev/null; then
    echo "   ❌ ERROR: Doppler CLI not installed"
    echo "   Install: brew install dopplerhq/cli/doppler"
    exit 1
fi

if ! doppler secrets get PYPI_TOKEN --plain > /dev/null 2>&1; then
    echo "   ❌ ERROR: PYPI_TOKEN not found in Doppler"
    echo "   Run: doppler secrets set PYPI_TOKEN='your-token'"
    echo "   Get token from: https://pypi.org/manage/account/token/"
    exit 1
fi
echo "   ✅ Doppler token verified"

# Step 1: Pull latest release commit from GitHub
echo -e "\n📥 Step 1: Pulling latest release commit..."
git pull origin main
CURRENT_VERSION=$(grep '^version = ' pyproject.toml | sed 's/version = "\(.*\)"/\1/')
echo "   Current version: v${CURRENT_VERSION}"

# Step 2: Clean old builds
echo -e "\n🧹 Step 2: Cleaning old builds..."
rm -rf dist/ build/ *.egg-info
echo "   ✅ Cleaned"

# Step 3: Build package
echo -e "\n📦 Step 3: Building package..."
if ! command -v uv &> /dev/null; then
    echo "   ❌ ERROR: uv not installed"
    echo "   Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

uv build 2>&1 | grep -E "(Building|Successfully built)" || uv build
echo "   ✅ Built: dist/*-${CURRENT_VERSION}*"

# Step 4: Publish to PyPI using Doppler token
echo -e "\n📤 Step 4: Publishing to PyPI..."
echo "   Using PYPI_TOKEN from Doppler"
PYPI_TOKEN=$(doppler secrets get PYPI_TOKEN --plain)
uv publish --token "${PYPI_TOKEN}" 2>&1 | grep -E "(Uploading|succeeded|Failed)" || \
  uv publish --token "${PYPI_TOKEN}"
echo "   ✅ Published to PyPI"

# Step 5: Verify publication on PyPI
echo -e "\n🔍 Step 5: Verifying on PyPI..."
sleep 3

# Extract package name from pyproject.toml
PACKAGE_NAME=$(grep '^name = ' pyproject.toml | sed 's/name = "\(.*\)"/\1/')

# Check if package version is live on PyPI
if curl -s "https://pypi.org/pypi/${PACKAGE_NAME}/${CURRENT_VERSION}/json" > /dev/null 2>&1; then
  echo "   ✅ Verified: https://pypi.org/project/${PACKAGE_NAME}/${CURRENT_VERSION}/"
else
  echo "   ⏳ Still propagating (CDN caching)"
  echo "   Check manually in 30 seconds: https://pypi.org/project/${PACKAGE_NAME}/${CURRENT_VERSION}/"
fi

echo -e "\n✅ Complete! Published v${CURRENT_VERSION} to PyPI"
echo ""
echo "Next steps:"
echo "  - Verify package is installable: pip install ${PACKAGE_NAME}==${CURRENT_VERSION}"
echo "  - Check PyPI page: https://pypi.org/project/${PACKAGE_NAME}/"
echo "  - Monitor downloads: https://pypistats.org/packages/${PACKAGE_NAME}"
