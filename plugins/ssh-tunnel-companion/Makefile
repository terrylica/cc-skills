# ssh-tunnel-companion — Makefile
#
# Pure SSH + launchd KeepAlive + sleepwatcher. No autossh.
#
# 3-LAYER TUNNEL RESILIENCE SYSTEM (find one → find all):
#   Layer 1: SSH keepalive     — ~/.ssh/config (Host $(TUNNEL_HOST))
#   Layer 2: launchd           — ~/Library/LaunchAgents/com.terryli.ssh-tunnel-companion.plist
#   Layer 3: sleepwatcher      — ~/.wakeup (kills stale SSH on wake)
#   Control: SwiftBar          — ~/Library/Application Support/SwiftBar/Plugins/ssh-tunnel.5s.sh
#   Source:  THIS repo         — <repo>/plugins/ssh-tunnel-companion/

LABEL := com.terryli.ssh-tunnel-companion

# Target host from config, never baked in (this plugin ships publicly).
# See libexec/ssh-tunnel-companion-runner for the rationale.
SSH_TUNNEL_CONFIG ?= $(HOME)/.config/ssh-tunnel-companion/config
TUNNEL_HOST := $(shell [ -f '$(SSH_TUNNEL_CONFIG)' ] && sed -n 's/^[[:space:]]*TUNNEL_HOST=//p' '$(SSH_TUNNEL_CONFIG)' | tail -1)
PLIST := $(HOME)/Library/LaunchAgents/$(LABEL).plist

.PHONY: install uninstall start stop restart status logs ping help

install:            ## Deploy launchd + sleepwatcher + SwiftBar, start tunnel
	@bash scripts/install.sh

uninstall:          ## Remove launchd + sleepwatcher hook + SwiftBar, stop tunnel
	@bash scripts/uninstall.sh

start:              ## Start tunnel (load launchd agent)
	@launchctl unload "$(PLIST)" 2>/dev/null || true
	@launchctl load "$(PLIST)"
	@echo "Tunnel starting... (check: make status)"

stop:               ## Stop tunnel (unload launchd agent)
	@launchctl unload "$(PLIST)" 2>/dev/null || true
	@PID=$$(lsof -ti:18123 2>/dev/null); [ -n "$$PID" ] && kill $$PID 2>/dev/null || true
	@echo "Tunnel stopped"

restart:            ## Restart tunnel (kill SSH → launchd restarts it)
	@PID=$$(lsof -ti:18123 2>/dev/null); \
	if [ -n "$$PID" ]; then \
		kill $$PID 2>/dev/null; \
		echo "Tunnel killed (pid $$PID) — launchd will restart in ~10s"; \
	else \
		$(MAKE) -s start; \
	fi

status:             ## Show all 3 layers + connectivity
	@echo "=== SSH Tunnel Companion Status ==="
	@echo ""
	@echo "Layer 1 — SSH keepalive (~/.ssh/config):"
	@grep -A15 'Host $(TUNNEL_HOST)' ~/.ssh/config 2>/dev/null | grep -q ServerAliveInterval \
		&& echo "  ServerAliveInterval: configured" \
		|| echo "  ServerAliveInterval: MISSING"
	@grep -A15 'Host $(TUNNEL_HOST)' ~/.ssh/config 2>/dev/null | grep -q ExitOnForwardFailure \
		&& echo "  ExitOnForwardFailure: configured" \
		|| echo "  ExitOnForwardFailure: MISSING"
	@echo ""
	@echo "Layer 2 — launchd (KeepAlive=true):"
	@[ -f "$(PLIST)" ] \
		&& echo "  Plist: installed" \
		|| echo "  Plist: NOT FOUND"
	@launchctl list 2>/dev/null | grep -q $(LABEL) \
		&& echo "  Agent: loaded" \
		|| echo "  Agent: not loaded"
	@echo ""
	@echo "Layer 3 — sleepwatcher (instant wake recovery):"
	@pgrep -x sleepwatcher >/dev/null 2>&1 \
		&& echo "  Daemon: running" \
		|| echo "  Daemon: NOT running (brew services start sleepwatcher)"
	@[ -x "$(HOME)/.wakeup" ] \
		&& echo "  ~/.wakeup: executable" \
		|| echo "  ~/.wakeup: NOT found"
	@[ -f "$(HOME)/.wakeup" ] && grep -q ssh-tunnel-companion "$(HOME)/.wakeup" 2>/dev/null \
		&& echo "  Tunnel hook: present" \
		|| echo "  Tunnel hook: MISSING"
	@echo ""
	@echo "Connectivity:"
	@PID=$$(lsof -ti:18123 2>/dev/null); \
	if [ -n "$$PID" ]; then \
		echo "  Port 18123: OPEN (pid $$PID)"; \
		RESULT=$$(curl -sf --connect-timeout 2 "http://localhost:18123" --data "SELECT 'ok' FORMAT TabSeparated" 2>/dev/null); \
		if [ "$$RESULT" = "ok" ]; then \
			echo "  ClickHouse: responding"; \
		else \
			echo "  ClickHouse: NOT responding"; \
		fi; \
	else \
		echo "  Port 18123: CLOSED (tunnel down)"; \
	fi
	@echo ""
	@echo "Log: /tmp/ssh-tunnel-companion.log"

logs:               ## Tail tunnel log
	@tail -f /tmp/ssh-tunnel-companion.log

ping:               ## Tailscale connectivity check to the configured tunnel host
	@[ -n '$(TUNNEL_HOST)' ] || { echo 'No TUNNEL_HOST configured in $(SSH_TUNNEL_CONFIG)'; exit 78; }
	@tailscale ping $(TUNNEL_HOST)

help:               ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'
