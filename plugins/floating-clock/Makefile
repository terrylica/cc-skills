APP_NAME := FloatingClock
BIN_NAME := floating-clock
BUNDLE_ID := com.terryli.floating-clock
VERSION := 1.0.0

BUILD := build
APP := $(BUILD)/$(APP_NAME).app
CONTENTS := $(APP)/Contents
MACOS := $(CONTENTS)/MacOS

CFLAGS := -framework Cocoa -framework QuartzCore -Os -dead_strip -fobjc-arc -Wall -ISources
ICON_CFLAGS := -framework Cocoa -framework ImageIO -framework UniformTypeIdentifiers -framework CoreServices -Os -fobjc-arc -Wall

# All non-gen-icon .m sources under Sources/. New modules dropped into
# Sources/<area>/ automatically compile in.
APP_SOURCES := $(shell find Sources -name '*.m' ! -name 'gen-icon.m')

ICON_SIZES := 16 32 64 128 256 512 1024
ICONSET := $(BUILD)/icons.iconset
ICON_PNGS := $(foreach sz,$(ICON_SIZES),$(BUILD)/icon_$(sz).png)
ICON_ICNS := $(BUILD)/Icon.icns

.PHONY: all build bundle icon sign install run clean test check help leaks

# Test binary: links the data/ layer (MarketCatalog + MarketSessionCalculator)
# with the test harness. Excludes clock.m (has main) and AppKit-dependent modules.
TEST_BIN := $(BUILD)/test_session
TEST_SOURCES := tests/test_session.m Sources/data/MarketCatalog.m Sources/data/MarketSessionCalculator.m Sources/data/ThemeCatalog.m Sources/preferences/FloatingClockStarterProfiles.m Sources/content/LandingTimeFormatter.m Sources/rendering/FontResolver.m Sources/rendering/SegmentOpacityResolver.m
TEST_CFLAGS := -framework Cocoa -fobjc-arc -Wall -ISources

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

sign: bundle
	codesign --force --deep --sign - $(APP)
	@echo "Signed: $(APP)"

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
