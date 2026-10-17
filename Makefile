# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Carlos B and claudebar contributors
#
# This file is part of claudebar.

PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
APP_BUNDLE := build/claudebar.app
APP_DEST ?= /Applications

# Code-signing identity for `make app`: the local self-signed identity kefbar already uses, falling back to ad hoc when it isn't in the keychain. Override: make app SIGN_IDENTITY="Developer ID Application: …"
SIGN_IDENTITY ?= kefbar-codesign

.PHONY: all build release debug test run app snapshot install uninstall clean

all: app

## build (alias for release)
build: release

## release: optimised CLI + app binaries
release:
	swift build -c release

## debug build
debug:
	swift build

## run unit tests
test:
	swift test

## run the debug CLI, e.g.  make run ARGS="--json"
run:
	swift run claudebar $(ARGS)

## menu-bar app bundle: build the SwiftUI executable and wrap it into claudebar.app
app:
	swift build -c release --product ClaudebarApp
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp .build/release/ClaudebarApp "$(APP_BUNDLE)/Contents/MacOS/ClaudebarApp"
	cp App/Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)" 2>/dev/null || { echo "no '$(SIGN_IDENTITY)' identity: signing ad hoc"; codesign --force --sign - "$(APP_BUNDLE)"; }
	@echo "built $(APP_BUNDLE); launch with: open $(APP_BUNDLE)"

## render the menu to build/menu.png without clicking the menu bar (debug build; your real config unless CLAUDEBAR_CONFIG says otherwise; CLAUDEBAR_SNAPSHOT_DARK=1 for dark). DEMO=1 shows made-up accounts instead (SHOW=used to count up), e.g. for the README: make snapshot DEMO=1 OUT=docs/images/menu-left.png
OUT ?= build/menu.png
SHOW ?= left
snapshot:
	swift build --product ClaudebarApp
	mkdir -p build "$(dir $(OUT))"
ifeq ($(DEMO),1)
	printf '{"show":"%s"}\n' "$(SHOW)" > build/demo-config.json
	CLAUDEBAR_DEMO=1 CLAUDEBAR_CONFIG="$(CURDIR)/build/demo-config.json" CLAUDEBAR_SNAPSHOT="$(CURDIR)/$(OUT)" .build/debug/ClaudebarApp
else
	CLAUDEBAR_SNAPSHOT="$(CURDIR)/$(OUT)" .build/debug/ClaudebarApp
endif
	@echo "wrote $(OUT)"

## install the app into $(APP_DEST) and the CLI into $(BINDIR); quit a running claudebar first
install: release app
	rm -rf "$(APP_DEST)/claudebar.app"
	ditto "$(APP_BUNDLE)" "$(APP_DEST)/claudebar.app"
	install -d "$(BINDIR)"
	install -m 0755 .build/release/claudebar "$(BINDIR)/claudebar"
	@echo "installed $(APP_DEST)/claudebar.app and $(BINDIR)/claudebar"

## remove the installed app and CLI
uninstall:
	rm -rf "$(APP_DEST)/claudebar.app"
	rm -f "$(BINDIR)/claudebar"

## remove build products
clean:
	swift package clean
	rm -rf .build build
