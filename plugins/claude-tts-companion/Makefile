# claude-tts-companion: build → deploy → restart in one step.
#
# Usage:
#   make          # build release, deploy binary, restart service
#   make build    # build only (no deploy)
#   make deploy   # copy binary + restart service (assumes already built)
#   make logs     # tail service stderr
#   make health   # check service health

SERVICE := com.terryli.claude-tts-companion
INSTALL_PATH := $(HOME)/.local/bin/claude-tts-companion
BUILD_PATH := .build/release/claude-tts-companion
PORT := 8780

.PHONY: all build deploy restart logs health stop

# Default: build + deploy + restart (the whole point)
all: build deploy
	@echo "✓ Built, deployed, restarted"

build:
	swift build -c release 2>&1 | grep -E 'error:|Build complete'
	@test -f $(BUILD_PATH) || (echo "Build failed" && exit 1)

deploy: $(BUILD_PATH)
	@# Kill any process holding the port (stale from previous run)
	@lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	@sleep 1
	cp $(BUILD_PATH) $(INSTALL_PATH)
	@# Bootout + bootstrap to pick up any plist changes (ProcessType, env vars)
	@launchctl bootout gui/$$(id -u)/$(SERVICE) 2>/dev/null || true
	@sleep 1
	@launchctl bootstrap gui/$$(id -u) $(HOME)/Library/LaunchAgents/$(SERVICE).plist 2>/dev/null
	@sleep 3
	@curl -sf --max-time 5 "http://[::1]:$(PORT)/health" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Health: {d[\"status\"]} | RSS: {d[\"rss_mb\"]:.0f}MB | Audio: {\"clean\" if d.get(\"audio_routing_clean\",True) else \"DEGRADED\"}')" \
		|| echo "⚠ Service not responding on port $(PORT)"

restart:
	launchctl kickstart -k gui/$$(id -u)/$(SERVICE)

logs:
	tail -f $(HOME)/.local/state/launchd-logs/claude-tts-companion/stderr.log

health:
	@curl -s --max-time 5 "http://[::1]:$(PORT)/health" | python3 -m json.tool

stop:
	@curl -sf --max-time 5 -X POST "http://[::1]:$(PORT)/tts/stop" && echo "TTS stopped" || echo "Failed"
