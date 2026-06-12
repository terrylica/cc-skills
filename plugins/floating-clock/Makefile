APP_NAME := FloatingClock
BIN_NAME := floating-clock
BUNDLE_ID := com.terryli.floating-clock
VERSION := 1.0.0

BUILD := build
APP := $(BUILD)/$(APP_NAME).app
CONTENTS := $(APP)/Contents
MACOS := $(CONTENTS)/MacOS

CFLAGS := -framework Cocoa -framework QuartzCore -framework CoreLocation -framework CoreAudio -framework AVFoundation -framework IOBluetooth -framework CoreText -Os -dead_strip -fobjc-arc -Wall -ISources
ICON_CFLAGS := -framework Cocoa -framework ImageIO -framework UniformTypeIdentifiers -framework CoreServices -Os -fobjc-arc -Wall

# All non-gen-icon .m sources under Sources/. New modules dropped into
# Sources/<area>/ automatically compile in.
APP_SOURCES := $(shell find Sources -name '*.m' ! -name 'gen-icon.m')

ICON_SIZES := 16 32 64 128 256 512 1024
ICONSET := $(BUILD)/icons.iconset
ICON_PNGS := $(foreach sz,$(ICON_SIZES),$(BUILD)/icon_$(sz).png)
ICON_ICNS := $(BUILD)/Icon.icns

.PHONY: all build bundle icon sign install run clean test check help leaks

# Test binary sources are DERIVED from APP_SOURCES (DRY 2026-06-12): a new
# data/spec module is auto-included in the test link with zero Makefile
# edits; only the main()-bearing clock.m and AppKit-BOUND modules (NSPanel/
# NSView subclasses, panel categories, UI builders) are excluded. If a new
# module breaks the test link (duplicate main, unresolved AppKit symbols),
# add it to TEST_EXCLUDED — the failure is loud, never silent.
TEST_BIN := $(BUILD)/test_session
TEST_EXCLUDED := Sources/clock.m \
    $(wildcard Sources/menu/*.m) \
    $(wildcard Sources/actions/*.m) \
    $(wildcard Sources/segments/*.m) \
    $(wildcard Sources/vendor/RMBlurredView/*.m) \
    $(wildcard Sources/core/FloatingClockPanel+*.m) \
    Sources/core/AudioStatusIndicator.m \
    Sources/core/MicMuteIndicator.m \
    Sources/core/VPNStatusIndicator.m \
    Sources/core/AudioDeviceSelectionMenuController.m \
    Sources/core/BluetoothPairedAudioDeviceConnector.m \
    Sources/core/ClockChildWindowAttachment.m \
    Sources/core/LocationProvider.m \
    Sources/rendering/AttributedStringLayoutMeasurer.m \
    Sources/rendering/VerticallyCenteredTextFieldCell.m \
    Sources/rendering/SolarOutlinedTextRenderingView.m \
    Sources/preferences/FloatingClockPanel+ProfileManagement.m \
    Sources/content/ActiveSegmentContentBuilder.m \
    Sources/content/NextSegmentContentBuilder.m \
    Sources/content/SegmentHeaderRenderer.m
TEST_SOURCES := $(wildcard tests/*.m) $(filter-out $(TEST_EXCLUDED),$(APP_SOURCES))
$(if $(TEST_SOURCES),,$(error TEST_SOURCES is empty after filtering))
TEST_CFLAGS := -framework Cocoa -framework CoreAudio -fobjc-arc -Wall -ISources

all: sign

# Conventional CI-style target: build + test in one shot. Use before
# shipping or cutting a release. `make all` stays build-only to keep
# the fast iterate loop snappy.
check: all test
	@echo "check: build + tests passing."

help:
	@echo "Targets:"
	@echo "  make          build + bundle + sign (default: all)"
	@echo "  make run      same as 'all' then open the app"
	@echo "  make install  same as 'all' then copy to /Applications/"
	@echo "  make test     build + run unit tests (data/ layer only)"
	@echo "  make check    build + unit tests (full validation)"
	@echo "  make leaks    build + run briefly + leaks audit (Instruments-free)"
	@echo "  make clean    remove the build/ dir"

build: $(BUILD)/$(BIN_NAME)

$(BUILD)/$(BIN_NAME): $(APP_SOURCES)
	@mkdir -p $(BUILD)
	clang $(CFLAGS) -o $@ $(APP_SOURCES)
	@echo "Built: $@ ($$(du -h $@ | cut -f1))"

$(BUILD)/gen-icon: Sources/gen-icon.m
	@mkdir -p $(BUILD)
	clang $(ICON_CFLAGS) -o $@ $<
	@echo "Built: $@ ($$(du -h $@ | cut -f1))"

$(BUILD)/icon_%.png: $(BUILD)/gen-icon
	$(BUILD)/gen-icon $@ $*

$(ICON_ICNS): $(ICON_PNGS)
	@mkdir -p $(ICONSET)
	cp $(BUILD)/icon_16.png   $(ICONSET)/icon_16x16.png
	cp $(BUILD)/icon_32.png   $(ICONSET)/icon_16x16@2x.png
	cp $(BUILD)/icon_32.png   $(ICONSET)/icon_32x32.png
	cp $(BUILD)/icon_64.png   $(ICONSET)/icon_32x32@2x.png
	cp $(BUILD)/icon_128.png  $(ICONSET)/icon_128x128.png
	cp $(BUILD)/icon_256.png  $(ICONSET)/icon_128x128@2x.png
	cp $(BUILD)/icon_256.png  $(ICONSET)/icon_256x256.png
	cp $(BUILD)/icon_512.png  $(ICONSET)/icon_256x256@2x.png
	cp $(BUILD)/icon_512.png  $(ICONSET)/icon_512x512.png
	cp $(BUILD)/icon_1024.png $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $@
	@echo "Icon: $@ ($$(du -h $@ | cut -f1))"

icon: $(ICON_ICNS)

bundle: build icon
	@mkdir -p $(MACOS) $(CONTENTS)/Resources
	cp $(BUILD)/$(BIN_NAME) $(MACOS)/$(BIN_NAME)
	cp Info.plist $(CONTENTS)/Info.plist
	cp $(ICON_ICNS) $(CONTENTS)/Resources/Icon.icns

# Stable signing identity (2026-06-11): ad-hoc signing ("-") mints a NEW code
# identity every build, so macOS TCC re-prompts (Bluetooth, mic) after every
# reinstall. A persistent self-signed cert keeps the identity stable — the
# user authorizes ONCE and the grant survives rebuilds. Falls back to ad-hoc
# when the cert is absent (fresh machines). Cert lives in the login keychain;
# key material at ~/.local/share/floating-clock-signing/ (never in git).
SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -q "FloatingClock Local Signing" \
	&& echo "FloatingClock Local Signing" || echo "-")

sign: bundle
	codesign --force --deep --sign "$(SIGN_IDENTITY)" $(APP)
	@echo "Signed: $(APP) (identity: $(SIGN_IDENTITY))"

install: sign
	cp -R $(APP) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

run: sign
	open $(APP)

test: $(TEST_BIN)
	@$(TEST_BIN)

# Memory-leak audit without Instruments. Launches the app, waits long
# enough for a few ticks + layout passes, runs `leaks`, then terminates.
# Reports physical footprint + leak count — should be 0 leaks /
# <20 MB footprint (established in v1 iter-5 baseline).
leaks: sign
	@pkill -f "FloatingClock.app/Contents/MacOS/floating-clock" 2>/dev/null || true
	@sleep 0.3
	@open $(APP)
	@sleep 2
	@PID=$$(pgrep -f "FloatingClock.app/Contents/MacOS/floating-clock" | head -1); \
	if [ -z "$$PID" ]; then echo "floating-clock not running"; exit 1; fi; \
	leaks $$PID 2>&1 | grep -E "Physical footprint|leaks for|Process" | head -5 || true; \
	kill $$PID 2>/dev/null || true

$(TEST_BIN): $(TEST_SOURCES)
	@mkdir -p $(BUILD)
	clang $(TEST_CFLAGS) -o $@ $(TEST_SOURCES)

clean:
	rm -rf $(BUILD)
