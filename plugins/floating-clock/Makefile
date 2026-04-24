APP_NAME := FloatingClock
BIN_NAME := floating-clock
BUNDLE_ID := com.terryli.floating-clock
VERSION := 1.0.0

BUILD := build
APP := $(BUILD)/$(APP_NAME).app
CONTENTS := $(APP)/Contents
MACOS := $(CONTENTS)/MacOS

CFLAGS := -framework Cocoa -Os -dead_strip -fobjc-arc -Wall -ISources
ICON_CFLAGS := -framework Cocoa -framework ImageIO -framework UniformTypeIdentifiers -framework CoreServices -Os -fobjc-arc -Wall

# All non-gen-icon .m sources under Sources/. New modules dropped into
# Sources/<area>/ automatically compile in.
APP_SOURCES := $(shell find Sources -name '*.m' ! -name 'gen-icon.m')

ICON_SIZES := 16 32 64 128 256 512 1024
ICONSET := $(BUILD)/icons.iconset
ICON_PNGS := $(foreach sz,$(ICON_SIZES),$(BUILD)/icon_$(sz).png)
ICON_ICNS := $(BUILD)/Icon.icns

.PHONY: all build bundle icon sign install run clean test

# Test binary: links the data/ layer (MarketCatalog + MarketSessionCalculator)
# with the test harness. Excludes clock.m (has main) and AppKit-dependent modules.
TEST_BIN := $(BUILD)/test_session
TEST_SOURCES := tests/test_session.m Sources/data/MarketCatalog.m Sources/data/MarketSessionCalculator.m
TEST_CFLAGS := -framework Cocoa -fobjc-arc -Wall -ISources

all: sign

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

$(TEST_BIN): $(TEST_SOURCES)
	@mkdir -p $(BUILD)
	clang $(TEST_CFLAGS) -o $@ $(TEST_SOURCES)

clean:
	rm -rf $(BUILD)
