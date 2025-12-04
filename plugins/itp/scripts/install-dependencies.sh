#!/usr/bin/env bash
# itp plugin dependency installer
# Usage: ./install-dependencies.sh [--check|--install]
# Supports: macOS (Homebrew), Ubuntu/Debian (apt)

set -euo pipefail

MODE="${1:---check}"
MISSING=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Platform Detection
# ============================================================================

detect_platform() {
    case "$(uname -s)" in
        Darwin)
            OS="macos"
            if command -v brew &>/dev/null; then
                PM="brew"
            else
                echo -e "${RED}ERROR: Homebrew not found${NC}"
                echo ""
                echo "Install Homebrew first:"
                echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
            ;;
        Linux)
            OS="linux"
            if command -v apt-get &>/dev/null; then
                PM="apt"
            elif command -v brew &>/dev/null; then
                PM="brew"  # Linuxbrew
            else
                echo -e "${RED}ERROR: No supported package manager found${NC}"
                echo ""
                echo "Supported package managers:"
                echo "  - apt (Ubuntu/Debian)"
                echo "  - brew (Linuxbrew)"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}ERROR: Unsupported OS: $(uname -s)${NC}"
            echo ""
            echo "Supported platforms:"
            echo "  - macOS (Darwin)"
            echo "  - Linux (Ubuntu/Debian)"
            exit 1
            ;;
    esac
}

# Check if mise is available (preferred cross-platform tool manager)
HAS_MISE=false
if command -v mise &>/dev/null; then
    HAS_MISE=true
fi

# Get platform-specific install command for a tool
# Prefers mise where available for cross-platform consistency
get_install_cmd() {
    local tool="$1"

    # Tools that work via mise on ALL platforms (verified in mise registry + asdf plugins)
    # Priority: mise > platform package manager for cross-platform consistency
    if $HAS_MISE; then
        case "$tool" in
            node)      echo "mise install node && mise use --global node"; return ;;
            gh)        echo "mise install github-cli && mise use --global github-cli"; return ;;
            doppler)   echo "mise install doppler && mise use --global doppler"; return ;;
            ruff)      echo "mise install ruff && mise use --global ruff"; return ;;
            uv)        echo "mise install uv && mise use --global uv"; return ;;
            semgrep)   echo "mise install semgrep && mise use --global semgrep"; return ;;
            prettier)  echo "mise use --global npm:prettier@latest"; return ;;
            perl)      echo "mise install perl && mise use --global perl"; return ;;
            cpanminus) echo "mise install perl && mise exec perl -- curl -L https://cpanmin.us | mise exec perl -- perl - App::cpanminus"; return ;;
            graph-easy) echo "mise exec perl -- cpanm Graph::Easy"; return ;;
        esac
    fi

    # Tools that only work via npm (no mise alternative)
    case "$tool" in
        jscpd)            echo "npm i -g jscpd"; return ;;
        semantic-release) echo "npm i -g semantic-release@25"; return ;;
    esac

    # Fallbacks for tools when mise is NOT available (npm/cpanm)
    case "$tool" in
        prettier)  echo "npm i -g prettier"; return ;;
        graph-easy) echo "cpanm Graph::Easy"; return ;;
    esac

    # Platform-specific installations (fallback when mise not available)
    case "$PM" in
        brew)
            case "$tool" in
                uv)        echo "brew install uv" ;;
                gh)        echo "brew install gh" ;;
                cpanminus) echo "brew install cpanminus" ;;
                semgrep)   echo "brew install semgrep" ;;
                doppler)   echo "brew install dopplerhq/cli/doppler" ;;
                node)      echo "brew install node" ;;
                perl)      echo "brew install perl" ;;
            esac
            ;;
        apt)
            case "$tool" in
                uv)        echo "curl -LsSf https://astral.sh/uv/install.sh | sh" ;;
                gh)        echo "sudo apt-get install -y gh" ;;
                cpanminus) echo "sudo apt-get install -y cpanminus" ;;
                semgrep)   echo "python3 -m pip install --user semgrep" ;;
                doppler)   echo "curl -Ls https://cli.doppler.com/install.sh | sh" ;;
                node)      echo "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs" ;;
                perl)      echo "sudo apt-get install -y perl" ;;
            esac
            ;;
    esac
}

# ============================================================================
# Tool Check and Install Functions
# ============================================================================

check_tool() {
    local name="$1"
    local cmd="$2"
    local version_flag="${3:---version}"

    if command -v "$cmd" &>/dev/null; then
        local version
        # Use timeout to avoid slow version checks (cpanm is notoriously slow)
        if command -v timeout &>/dev/null; then
            version=$(timeout 3 "$cmd" $version_flag 2>&1 | head -1) || version="installed"
        elif command -v gtimeout &>/dev/null; then
            # macOS with coreutils
            version=$(gtimeout 3 "$cmd" $version_flag 2>&1 | head -1) || version="installed"
        else
            # Fallback: no timeout available
            version=$("$cmd" $version_flag 2>&1 | head -1) || version="installed"
        fi
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
    echo -e "${YELLOW}Installing $name via $PM...${NC}"
    echo -e "${BLUE}  Command: $install_cmd${NC}"
    if eval "$install_cmd"; then
        echo -e "${GREEN}✓${NC} $name installed"
    else
        echo -e "${RED}✗${NC} Failed to install $name"
        echo ""
        echo "  Try installing manually:"
        echo "    $install_cmd"
        return 1
    fi
}

# ============================================================================
# Main Script
# ============================================================================

# Detect platform first
detect_platform

echo "=== itp plugin dependency check ==="
echo -e "Platform: ${BLUE}$OS${NC} | Package Manager: ${BLUE}$PM${NC} | mise: ${BLUE}$($HAS_MISE && echo 'yes' || echo 'no')${NC}"
echo ""

# Recommend mise if not installed (preferred cross-platform tool manager)
if ! $HAS_MISE; then
    echo -e "${YELLOW}💡 Recommendation: Install mise for unified cross-platform tool management${NC}"
    echo "   curl https://mise.run | sh"
    echo "   Then re-run this script for mise-first installations."
    echo ""
fi

# Core Tools (Required)
echo "## Core Tools (Required)"
check_tool "uv" "uv" || { MISSING=$((MISSING+1)); INSTALL_UV=$(get_install_cmd uv); }
check_tool "gh" "gh" || { MISSING=$((MISSING+1)); INSTALL_GH=$(get_install_cmd gh); }
check_tool "prettier" "prettier" || { MISSING=$((MISSING+1)); INSTALL_PRETTIER=$(get_install_cmd prettier); }
echo ""

# ADR Diagrams (Required for Preflight)
echo "## ADR Diagrams (Required for Preflight)"
# Check cpanm: direct command OR via mise perl
if command -v cpanm &>/dev/null; then
    echo -e "${GREEN}✓${NC} cpanm ($(cpanm --version 2>&1 | head -1 || echo 'installed'))"
elif $HAS_MISE && mise exec perl -- cpanm --version &>/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} cpanm (via mise perl)"
else
    echo -e "${RED}✗${NC} cpanm (missing)"
    MISSING=$((MISSING+1))
    INSTALL_CPANM=$(get_install_cmd cpanminus)
fi
# Check graph-easy: direct command OR via mise perl
# Note: graph-easy --version exits with code 2, so we check output instead
if command -v graph-easy &>/dev/null; then
    echo -e "${GREEN}✓${NC} graph-easy ($(graph-easy --version 2>&1 | head -1 || echo 'installed'))"
elif $HAS_MISE && { mise exec perl -- graph-easy --version 2>&1 || true; } | grep -q "Graph::Easy"; then
    echo -e "${GREEN}✓${NC} graph-easy (via mise perl)"
else
    echo -e "${RED}✗${NC} graph-easy (missing)"
    MISSING=$((MISSING+1))
    INSTALL_GRAPH_EASY=$(get_install_cmd graph-easy)
fi
echo ""

# Code Audit (Optional - for Phase 1)
echo "## Code Audit (Optional)"
check_tool "ruff" "ruff" || { MISSING=$((MISSING+1)); INSTALL_RUFF=$(get_install_cmd ruff); }
check_tool "semgrep" "semgrep" || { MISSING=$((MISSING+1)); INSTALL_SEMGREP=$(get_install_cmd semgrep); }
check_tool "jscpd" "jscpd" || { MISSING=$((MISSING+1)); INSTALL_JSCPD=$(get_install_cmd jscpd); }
echo ""

# Release (Optional - for Phase 3)
echo "## Release Tools (Optional)"
if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
    echo -e "${GREEN}✓${NC} node (v$NODE_VERSION)"
else
    echo -e "${RED}✗${NC} node (missing)"
    MISSING=$((MISSING+1))
    INSTALL_NODE=$(get_install_cmd node)
fi
check_tool "semantic-release" "npx" "semantic-release --version" || { MISSING=$((MISSING+1)); INSTALL_SR=$(get_install_cmd semantic-release); }
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
