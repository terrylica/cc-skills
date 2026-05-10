#!/bin/bash
# setup-socket-9100-queue.sh — create a CUPS queue that bypasses AirPrint
#
# Why this exists:
#   HP LaserJet Pro MFP 3101/3108/3201/3208/3301/3308 family firmware has
#   a buggy IPP-Everywhere PDF interpreter that silently drops jobs while
#   reporting "completed" to CUPS. The printer's PostScript Level 3
#   interpreter is reliable. This script creates a parallel queue that
#   sends raw PostScript over JetDirect socket-9100, taking the broken
#   PDF/PWG path out of the loop.
#
# Reference: ../references/airprint-blank-page-troubleshooting.md
#
# Usage:
#   setup-socket-9100-queue.sh [--name QUEUE_NAME] [--ip IP] [--probe-only]
#
# Defaults:
#   QUEUE_NAME = HP_3101_PS9100
#   IP         = auto-resolved from Bonjour (first reachable HP printer)

set -e

QUEUE_NAME="HP_3101_PS9100"
PRINTER_IP=""
PROBE_ONLY=""
PPD="drv:///sample.drv/generic.ppd"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)       QUEUE_NAME="$2"; shift 2 ;;
        --ip)         PRINTER_IP="$2"; shift 2 ;;
        --probe-only) PROBE_ONLY="yes"; shift ;;
        --ppd)        PPD="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's|^# \?||'
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

# 1. If queue already exists, report and exit successfully
if lpstat -p "$QUEUE_NAME" &>/dev/null; then
    EXISTING_URI=$(lpstat -v "$QUEUE_NAME" 2>/dev/null | awk -F': ' '{print $2}')
    echo "✅ Queue '$QUEUE_NAME' already exists"
    echo "   URI: $EXISTING_URI"
    [[ -n "$PROBE_ONLY" ]] && exit 0
    echo "   To recreate: lpadmin -x $QUEUE_NAME && rerun this script"
    exit 0
fi

# 2. Resolve printer IP via Bonjour if not provided
if [[ -z "$PRINTER_IP" ]]; then
    echo "🔍 Discovering HP printers via Bonjour..."
    # Browse for IPP/S printers, pick the first HP LaserJet, resolve its hostname
    INSTANCE=$(timeout 4 dns-sd -B _ipps._tcp local. 2>/dev/null \
                 | awk '/HP LaserJet|HP OfficeJet/ {sub(/.*_ipps\._tcp\.\s+/,""); print; exit}')
    if [[ -z "$INSTANCE" ]]; then
        echo "❌ No HP printers found via Bonjour. Pass --ip <address> manually."
        exit 1
    fi
    HOSTNAME=$(timeout 3 dns-sd -L "$INSTANCE" _ipps._tcp local. 2>&1 \
                 | awk '/reached at/ {gsub(":.*","",$3); print $3; exit}')
    if [[ -z "$HOSTNAME" ]]; then
        echo "❌ Failed to resolve hostname for '$INSTANCE'"
        exit 1
    fi
    # Resolve .local hostname to IP via mDNS
    PRINTER_IP=$(dscacheutil -q host -a name "${HOSTNAME%.}" 2>/dev/null \
                 | awk '/^ip_address:/ {print $2; exit}')
    if [[ -z "$PRINTER_IP" ]]; then
        # Fallback: ping briefly to populate the mDNS cache, then re-query
        ping -c 1 -W 2000 "$HOSTNAME" &>/dev/null || true
        PRINTER_IP=$(dscacheutil -q host -a name "${HOSTNAME%.}" 2>/dev/null \
                     | awk '/^ip_address:/ {print $2; exit}')
    fi
    if [[ -z "$PRINTER_IP" ]]; then
        echo "❌ Failed to resolve IP for $HOSTNAME"
        exit 1
    fi
    echo "✅ Found HP printer: $INSTANCE → $HOSTNAME → $PRINTER_IP"
fi

# 3. Probe TCP/9100 (JetDirect) reachability
echo "🔌 Probing TCP/9100 on $PRINTER_IP..."
if ! nc -z -v -w 3 "$PRINTER_IP" 9100 2>&1 | grep -q "succeeded"; then
    echo "❌ Printer not listening on TCP/9100. Check that JetDirect / Raw IP printing"
    echo "   is enabled in the printer's web UI (usually Networking → TCP/IP → Raw)."
    exit 1
fi
echo "✅ TCP/9100 reachable"

[[ -n "$PROBE_ONLY" ]] && { echo "ℹ️  --probe-only: skipping queue creation"; exit 0; }

# 4. Create the queue
echo "🛠  Creating queue '$QUEUE_NAME' with PPD '$PPD'..."
lpadmin -p "$QUEUE_NAME" \
    -E \
    -v "socket://$PRINTER_IP:9100" \
    -m "$PPD" \
    -D "HP LaserJet (PostScript over socket-9100, AirPrint bypass)" \
    -L "JetDirect bypass for AirPrint PDF interpreter bug"

# 5. Confirm
if lpstat -p "$QUEUE_NAME" &>/dev/null; then
    echo "✅ Queue created: $QUEUE_NAME"
    echo "   Print with: lp -d $QUEUE_NAME -o media=Letter <file>"
    echo "   Remove with: lpadmin -x $QUEUE_NAME"
else
    echo "❌ Queue creation reported success but lpstat can't see it"
    exit 1
fi
