#!/usr/bin/env bash
# ITP Workflow Dependency Installer
# Usage: ./install-dependencies.sh [--check|--install]

set -euo pipefail

MODE="${1:---check}"
MISSING=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_tool() {
    local name="$1"
    local cmd="$2"
    local version_flag="${3:---version}"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" $version_flag 2>&1 | head -1) || version="installed"
        echo -e "${GREEN}✓${NC} $name ($version)"
        return 0
    else
        echo -e "${RED}✗${NC} $name (missing)"
        return 1
    fi
}

install_tool() {
    local name="$1"
    local install_cmd="$2"
    echo -e "${YELLOW}Installing $name...${NC}"
    if eval "$install_cmd"; then
        echo -e "${GREEN}✓${NC} $name installed"
    else
        echo -e "${RED}✗${NC} Failed to install $name"
        return 1
    fi
}

echo "=== ITP Workflow Dependency Check ==="
echo ""

# Core Tools (Required)
echo "## Core Tools (Required)"
check_tool "uv" "uv" || { MISSING=$((MISSING+1)); INSTALL_UV="brew install uv"; }
check_tool "gh" "gh" || { MISSING=$((MISSING+1)); INSTALL_GH="brew install gh"; }
check_tool "prettier" "prettier" || { MISSING=$((MISSING+1)); INSTALL_PRETTIER="npm i -g prettier"; }
echo ""

# ADR Diagrams (Required for Preflight)
echo "## ADR Diagrams (Required for Preflight)"
check_tool "cpanm" "cpanm" || { MISSING=$((MISSING+1)); INSTALL_CPANM="brew install cpanminus"; }
check_tool "graph-easy" "graph-easy" || { MISSING=$((MISSING+1)); INSTALL_GRAPH_EASY="cpanm Graph::Easy"; }
echo ""

# Code Audit (Optional - for Phase 1)
echo "## Code Audit (Optional)"
check_tool "ruff" "ruff" || { MISSING=$((MISSING+1)); INSTALL_RUFF="uv tool install ruff"; }
check_tool "semgrep" "semgrep" || { MISSING=$((MISSING+1)); INSTALL_SEMGREP="brew install semgrep"; }
check_tool "jscpd" "jscpd" || { MISSING=$((MISSING+1)); INSTALL_JSCPD="npm i -g jscpd"; }
echo ""

# Release (Optional - for Phase 3)
echo "## Release Tools (Optional)"
if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -ge 20 ]; then
        echo -e "${GREEN}✓${NC} node (v$NODE_VERSION - meets v20+ requirement)"
    else
        echo -e "${YELLOW}⚠${NC} node (v$NODE_VERSION - v20+ recommended)"
        MISSING=$((MISSING+1))
        INSTALL_NODE="mise install node@20 && mise use --global node@20"
    fi
else
    echo -e "${RED}✗${NC} node (missing)"
    MISSING=$((MISSING+1))
    INSTALL_NODE="mise install node@20 && mise use --global node@20"
fi
check_tool "semantic-release" "npx" "semantic-release --version" || { MISSING=$((MISSING+1)); INSTALL_SR="npm i -g semantic-release@25"; }
check_tool "doppler" "doppler" || { echo -e "${YELLOW}⚠${NC} doppler (optional - for PyPI publishing)"; }
echo ""

# Summary
echo "=== Summary ==="
if [ "$MISSING" -eq 0 ]; then
    echo -e "${GREEN}✅ All required dependencies installed${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  $MISSING dependencies missing${NC}"

    if [ "$MODE" = "--install" ]; then
        echo ""
        echo "=== Auto-Installing Missing Tools ==="

        # Core
        [ -n "${INSTALL_UV:-}" ] && install_tool "uv" "$INSTALL_UV"
        [ -n "${INSTALL_GH:-}" ] && install_tool "gh" "$INSTALL_GH"
        [ -n "${INSTALL_PRETTIER:-}" ] && install_tool "prettier" "$INSTALL_PRETTIER"

        # ADR Diagrams
        [ -n "${INSTALL_CPANM:-}" ] && install_tool "cpanm" "$INSTALL_CPANM"
        [ -n "${INSTALL_GRAPH_EASY:-}" ] && install_tool "graph-easy" "$INSTALL_GRAPH_EASY"

        # Code Audit
        [ -n "${INSTALL_RUFF:-}" ] && install_tool "ruff" "$INSTALL_RUFF"
        [ -n "${INSTALL_SEMGREP:-}" ] && install_tool "semgrep" "$INSTALL_SEMGREP"
        [ -n "${INSTALL_JSCPD:-}" ] && install_tool "jscpd" "$INSTALL_JSCPD"

        # Release
        [ -n "${INSTALL_NODE:-}" ] && install_tool "node" "$INSTALL_NODE"
        [ -n "${INSTALL_SR:-}" ] && install_tool "semantic-release" "$INSTALL_SR"

        echo ""
        echo "=== Re-checking ==="
        exec "$0" --check
    else
        echo ""
        echo "Run with --install to auto-install missing tools:"
        echo "  $0 --install"
    fi
    exit 1
fi
