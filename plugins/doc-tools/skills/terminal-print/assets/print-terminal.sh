#!/bin/bash
# Terminal Print - Print iTerm2 output to HP printer
# Based on cc-skills pandoc-pdf-generation pattern
#
# Usage: ./print-terminal.sh [OPTIONS]
#
# Options:
#   --file FILE    Read from file instead of clipboard
#   --no-preview   Skip preview, print directly
#   --no-print     Generate PDF only, don't print
#   -h, --help     Show help
#
# ADR: /docs/adr/2025-12-28-terminal-print-skill.md (if created)

set -e

TMPDIR="${TMPDIR:-/tmp}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default printer is the system default; users with multiple printers can override via env or --printer
PRINTER="${TERMINAL_PRINT_PRINTER:-$(lpstat -d 2>/dev/null | awk -F': ' '/system default/{print $2}')}"
PRINTER="${PRINTER:-HP_LaserJet_Pro_MFP_3101_3108__A02E22__20250803224332}"

# AirPrint bypass queue (created by setup-socket-9100-queue.sh)
# When --bypass-airprint is passed, this queue is used instead.
# See: ../references/airprint-blank-page-troubleshooting.md
BYPASS_QUEUE="${TERMINAL_PRINT_BYPASS_QUEUE:-HP_3101_PS9100}"

# Defaults
INPUT_FILE=""
NO_PREVIEW=""
NO_PRINT=""
BYPASS_AIRPRINT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            INPUT_FILE="$2"
            shift 2
            ;;
        --no-preview)
            NO_PREVIEW="yes"
            shift
            ;;
        --no-print)
            NO_PRINT="yes"
            shift
            ;;
        --bypass-airprint)
            # Use the socket-9100 + PostScript queue instead of the AirPrint queue.
            # Diagnoses blank-page output from the IPP-Everywhere PDF interpreter on
            # HP LaserJet Pro MFP 3101/3108/3201/3208/3301/3308 firmware.
            BYPASS_AIRPRINT="yes"
            shift
            ;;
        --printer)
            PRINTER="$2"
            shift 2
            ;;
        -h|--help)
            cat <<HELP
Terminal Print - Print iTerm2 output to HP printer

Usage: $0 [OPTIONS]

Options:
  --file FILE         Read from file instead of clipboard
  --no-preview        Skip preview, print directly
  --no-print          Generate PDF only, don't print
  --printer NAME      Override target printer queue (default: system default)
  --bypass-airprint   Use socket-9100 + PostScript queue ('$BYPASS_QUEUE')
                      instead of the default AirPrint queue. Workaround for
                      HP LaserJet Pro MFP 3101/3108/3201/3208/3301/3308
                      firmware that silently drops PDF jobs from AirPrint.
                      Run setup-socket-9100-queue.sh first to create the queue.
                      See references/airprint-blank-page-troubleshooting.md.
  -h, --help          Show this help

Environment overrides:
  TERMINAL_PRINT_PRINTER         Default printer queue
  TERMINAL_PRINT_BYPASS_QUEUE    Bypass queue name (default: HP_3101_PS9100)
HELP
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h for help" >&2
            exit 1
            ;;
    esac
done

# Pre-flight checks
preflight_check() {
    local missing=()

    command -v pandoc &>/dev/null || missing+=("pandoc (brew install pandoc)")
    command -v xelatex &>/dev/null || missing+=("xelatex (brew install --cask mactex)")

    if ! lpstat -p &>/dev/null; then
        missing+=("printer (none configured)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing prerequisites:"
        for item in "${missing[@]}"; do
            echo "   - $item"
        done
        exit 1
    fi
}

preflight_check

# 1. Get input
if [[ -n "$INPUT_FILE" ]]; then
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "❌ File not found: $INPUT_FILE"
        exit 1
    fi
    content=$(cat "$INPUT_FILE")
    echo "📋 Reading from file: $INPUT_FILE"
else
    content=$(pbpaste)
    echo "📋 Reading from clipboard"
fi

# 2. Check for empty input
if [[ -z "$content" ]]; then
    echo "❌ No text in clipboard."
    echo "   Copy terminal output first (Cmd+C in iTerm2)."
    exit 1
fi

# 3. Strip ANSI escape codes
# Handles: colors, cursor movement, and other escape sequences
clean_content=$(echo "$content" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')

echo "📝 Stripped ANSI codes, preparing markdown..."

# 4. Create markdown with code block
MD_FILE="$TMPDIR/terminal-$TIMESTAMP.md"
cat > "$MD_FILE" << 'MARKDOWN_HEADER'
# Terminal Output

```text
MARKDOWN_HEADER

echo "$clean_content" >> "$MD_FILE"
echo '```' >> "$MD_FILE"

# 5. Generate PDF with pandoc (landscape, monospace)
OUTPUT_PDF="$TMPDIR/terminal-output-$TIMESTAMP.pdf"

echo "🔧 Generating PDF with pandoc + xelatex..."

pandoc "$MD_FILE" \
  -o "$OUTPUT_PDF" \
  --pdf-engine=xelatex \
  -V geometry:letterpaper,landscape \
  -V geometry:margin=0.5in \
  -V mainfont="DejaVu Sans Mono" \
  -V monofont="DejaVu Sans Mono" \
  -V fontsize=9pt

echo "📄 PDF generated: $OUTPUT_PDF"

# 6. Preview (unless --no-preview)
if [[ -z "$NO_PREVIEW" ]]; then
    open "$OUTPUT_PDF"
    echo ""
    echo "👀 Preview opened. Press Enter to print, or Ctrl+C to cancel."
    read -r
fi

# 7. Print (unless --no-print)
if [[ -z "$NO_PRINT" ]]; then
    if [[ -n "$BYPASS_AIRPRINT" ]]; then
        # AirPrint blank-page workaround: route through the socket-9100/PostScript queue.
        # See references/airprint-blank-page-troubleshooting.md for the full diagnostic.
        if ! lpstat -p "$BYPASS_QUEUE" &>/dev/null; then
            echo "❌ Bypass queue '$BYPASS_QUEUE' does not exist."
            echo "   Run: $(dirname "$0")/setup-socket-9100-queue.sh"
            exit 1
        fi
        TARGET_QUEUE="$BYPASS_QUEUE"
        echo "🔀 --bypass-airprint: routing through $BYPASS_QUEUE (socket-9100 + PostScript)"
    else
        TARGET_QUEUE="$PRINTER"
    fi
    lpr -P "$TARGET_QUEUE" -o sides=one-sided "$OUTPUT_PDF"
    echo "✅ Sent to printer: $TARGET_QUEUE"
    echo "ℹ️  Verify the page actually came out — CUPS reports 'completed' even when"
    echo "    the printer silently drops jobs. If blank or missing, retry with --bypass-airprint."
else
    echo "ℹ️  --no-print specified, skipping print"
fi

echo "📁 PDF saved: $OUTPUT_PDF"
