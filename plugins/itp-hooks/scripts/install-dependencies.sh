#!/usr/bin/env bash
# itp-hooks dependency installer
# Installs linters required for silent failure detection
# Usage: ./install-dependencies.sh [--check|--install|--detect-only]

set -euo pipefail

MODE="${1:---check}"
MISSING=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
                PM="brew"
            else
                echo -e "${RED}ERROR: No supported package manager found${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}ERROR: Unsupported OS: $(uname -s)${NC}"
            exit 1
            ;;
    esac
}

# Check for mise
HAS_MISE=false
if command -v mise &>/dev/null; then
    HAS_MISE=true
fi

# ============================================================================
# Install Commands
# ============================================================================

get_install_cmd() {
    local tool="$1"

    # Mise-first installations (cross-platform)
    if $HAS_MISE; then
        case "$tool" in
            ruff)       echo "mise install ruff && mise use --global ruff"; return ;;
            shellcheck) echo "mise install shellcheck && mise use --global shellcheck"; return ;;
        esac
    fi

    # npm-based installations
    case "$tool" in
        oxlint) echo "npm install -g oxlint"; return ;;
    esac

    # Platform-specific fallbacks
    case "$PM" in
        brew)
            case "$tool" in
                jq)         echo "brew install jq" ;;
                ruff)       echo "brew install ruff" ;;
                shellcheck) echo "brew install shellcheck" ;;
                oxlint)     echo "npm install -g oxlint" ;;
            esac
            ;;
        apt)
            case "$tool" in
                jq)         echo "sudo apt-get install -y jq" ;;
                ruff)       echo "pip install ruff" ;;
                shellcheck) echo "sudo apt-get install -y shellcheck" ;;
                oxlint)     echo "npm install -g oxlint" ;;
            esac
            ;;
    esac
}

# ============================================================================
# Tool Checks
# ============================================================================

check_tool() {
    local name="$1"
    local cmd="$2"
    local version_flag="${3:---version}"
    local required="${4:-optional}"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" $version_flag 2>&1 | head -1) || version="installed"
        echo -e "${GREEN}✓${NC} $name ($version)"
        return 0
    else
        if [[ "$required" == "required" ]]; then
            echo -e "${RED}✗${NC} $name (missing - REQUIRED)"
        else
            echo -e "${YELLOW}○${NC} $name (missing - optional)"
        fi
        return 1
    fi
}

install_tool() {
    local name="$1"
    local install_cmd="$2"
    echo -e "${YELLOW}Installing $name...${NC}"
    echo -e "${BLUE}  Command: $install_cmd${NC}"
    if eval "$install_cmd"; then
        echo -e "${GREEN}✓${NC} $name installed"
    else
        echo -e "${RED}✗${NC} Failed to install $name"
        echo "  Try installing manually: $install_cmd"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

detect_platform

if [ "$MODE" = "--detect-only" ]; then
    echo "Platform: OS=$OS PM=$PM HAS_MISE=$HAS_MISE"
    exit 0
fi

echo "=== itp-hooks dependency check ==="
echo -e "Platform: ${BLUE}$OS${NC} | Package Manager: ${BLUE}$PM${NC} | mise: ${BLUE}$($HAS_MISE && echo 'yes' || echo 'no')${NC}"
echo ""

# Required tools
echo "## Required"
check_tool "jq" "jq" "--version" "required" || { MISSING=$((MISSING+1)); INSTALL_JQ=$(get_install_cmd jq); }
echo ""

# Silent failure detection linters (optional - graceful degradation)
echo "## Silent Failure Detection Linters (optional)"
check_tool "ruff" "ruff" "--version" "optional" || { INSTALL_RUFF=$(get_install_cmd ruff); }
check_tool "shellcheck" "shellcheck" "--version" "optional" || { INSTALL_SHELLCHECK=$(get_install_cmd shellcheck); }
check_tool "oxlint" "oxlint" "--version" "optional" || { INSTALL_OXLINT=$(get_install_cmd oxlint); }
echo ""

# Summary
echo "=== Summary ==="

# Count optional missing
OPTIONAL_MISSING=0
command -v ruff &>/dev/null || OPTIONAL_MISSING=$((OPTIONAL_MISSING+1))
command -v shellcheck &>/dev/null || OPTIONAL_MISSING=$((OPTIONAL_MISSING+1))
command -v oxlint &>/dev/null || OPTIONAL_MISSING=$((OPTIONAL_MISSING+1))

if [ "$MISSING" -eq 0 ] && [ "$OPTIONAL_MISSING" -eq 0 ]; then
    echo -e "${GREEN}All dependencies installed (required + optional)${NC}"
    exit 0
elif [ "$MISSING" -eq 0 ]; then
    echo -e "${GREEN}Required dependencies OK${NC}"
    echo -e "${YELLOW}$OPTIONAL_MISSING optional linter(s) missing${NC}"
    echo ""
    echo "Silent failure detection works with graceful degradation."
    echo "Install optional linters for full coverage:"
    [ -n "${INSTALL_RUFF:-}" ] && echo "  ruff (Python):       ${INSTALL_RUFF}"
    [ -n "${INSTALL_SHELLCHECK:-}" ] && echo "  shellcheck (Shell):  ${INSTALL_SHELLCHECK}"
    [ -n "${INSTALL_OXLINT:-}" ] && echo "  oxlint (JS/TS):      ${INSTALL_OXLINT}"
else
    echo -e "${RED}$MISSING required dependency missing${NC}"
fi

if [ "$MODE" = "--install" ] || [ "$MODE" = "--yes" ]; then
    echo ""
    echo "=== Installing ==="

    # Required
    [ -n "${INSTALL_JQ:-}" ] && install_tool "jq" "$INSTALL_JQ"

    # Optional linters
    [ -n "${INSTALL_RUFF:-}" ] && install_tool "ruff" "$INSTALL_RUFF"
    [ -n "${INSTALL_SHELLCHECK:-}" ] && install_tool "shellcheck" "$INSTALL_SHELLCHECK"
    [ -n "${INSTALL_OXLINT:-}" ] && install_tool "oxlint" "$INSTALL_OXLINT"

    echo ""
    echo "=== Re-checking ==="
    exec "$0" --check
else
    echo ""
    echo "Run with --install to install all tools:"
    echo "  $0 --install"
    [ "$MISSING" -gt 0 ] && exit 1
fi
