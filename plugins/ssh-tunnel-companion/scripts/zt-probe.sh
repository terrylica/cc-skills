#!/bin/bash
# zt-probe.sh — ZeroTier health probe for bigblack SSH tunnel
#
# Checks ZeroTier local service status and bigblack peer link.
# Restarts ZeroTier if local service is offline or peer is not DIRECT.
# Called by SwiftBar plugin or manually for diagnostics.
#
# 3-LAYER TUNNEL RESILIENCE SYSTEM (find one → find all):
#   Layer 1: SSH keepalive     — ~/.ssh/config (Host bigblack)
#   Layer 2: autossh           — /opt/homebrew/bin/autossh
#   Layer 3: launchd           — ~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist
#   Control: SwiftBar          — ~/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh
#   Probe:   THIS              — ~/eon/cc-skills/plugins/ssh-tunnel-companion/scripts/zt-probe.sh

set -e

BIGBLACK_ZT_NODE="8f53f201b7"
BIGBLACK_ZT_IP="172.25.253.142"

zt_peer_status() {
  sudo zerotier-cli peers 2>/dev/null | awk -v node="$BIGBLACK_ZT_NODE" '$1 == node { print $5 }'
}

zt_local_status() {
  sudo zerotier-cli info 2>/dev/null | awk '{ print $5 }'
}

echo "=== ZeroTier Health Probe ==="
echo ""

# Step 1: Check local ZeroTier service
LOCAL_STATUS=$(zt_local_status)
echo "Local ZeroTier: ${LOCAL_STATUS:-UNKNOWN}"

if [ "$LOCAL_STATUS" != "ONLINE" ]; then
  echo "  Restarting ZeroTier service..."
  sudo launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist 2>/dev/null || true
  sleep 1
  sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist
  sleep 3
  LOCAL_STATUS=$(zt_local_status)
  echo "  After restart: ${LOCAL_STATUS:-UNKNOWN}"
fi

# Step 2: Check bigblack peer status
echo ""
PEER_LINK=$(zt_peer_status)
echo "bigblack peer ($BIGBLACK_ZT_NODE): link=${PEER_LINK:-NOT_FOUND}"

if [ "$PEER_LINK" != "DIRECT" ]; then
  echo "  Peer not DIRECT — forcing NAT re-punch..."
  sudo launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist 2>/dev/null || true
  sleep 1
  sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist
  echo "  Waiting for peer re-negotiation (up to 15s)..."
  for i in $(seq 1 5); do
    sleep 3
    PEER_LINK=$(zt_peer_status)
    echo "    attempt $i/5: link=${PEER_LINK:-NOT_FOUND}"
    if [ "$PEER_LINK" = "DIRECT" ]; then
      break
    fi
  done
fi

# Step 3: Summary
echo ""
if [ "$LOCAL_STATUS" = "ONLINE" ] && [ "$PEER_LINK" = "DIRECT" ]; then
  echo "=== ZeroTier OK ==="
  echo "  bigblack reachable at $BIGBLACK_ZT_IP"
else
  echo "=== ZeroTier DEGRADED ==="
  echo "  Local: ${LOCAL_STATUS:-UNKNOWN}"
  echo "  Peer:  ${PEER_LINK:-NOT_FOUND}"
  echo ""
  echo "  Check:"
  echo "    - Is bigblack powered on?"
  echo "    - ping $BIGBLACK_ZT_IP"
  echo "    - sudo zerotier-cli peers | grep $BIGBLACK_ZT_NODE"
fi
