APP_NAME := FloatingClock
BIN_NAME := floating-clock
BUNDLE_ID := com.terryli.floating-clock
VERSION := 1.0.0

BUILD := build
APP := $(BUILD)/$(APP_NAME).app
CONTENTS := $(APP)/Contents
MACOS := $(CONTENTS)/MacOS

CFLAGS := -framework Cocoa -Os -dead_strip -fobjc-arc -Wall

.PHONY: all build bundle sign install run clean

all: sign

build: $(BUILD)/$(BIN_NAME)

$(BUILD)/$(BIN_NAME): Sources/clock.m
	@mkdir -p $(BUILD)
	clang $(CFLAGS) -o $@ $<
	@echo "Built: $@ ($$(du -h $@ | cut -f1))"

bundle: build
	@mkdir -p $(MACOS)
	cp $(BUILD)/$(BIN_NAME) $(MACOS)/$(BIN_NAME)
	cp Info.plist $(CONTENTS)/Info.plist

sign: bundle
	codesign --force --deep --sign - $(APP)
	@echo "Signed: $(APP)"

install: sign
	cp -R $(APP) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

run: sign
	open $(APP)

clean:
	rm -rf $(BUILD)
