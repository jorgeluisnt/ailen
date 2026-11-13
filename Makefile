# Ailen — build it yourself.
#
#   make sim       try it in the iOS Simulator (no Apple ID, no phone)
#   make install   install it on your own iPhone
#
# `make help` lists everything. `make doctor` tells you what's missing.
#
# Everything auto-detects. Override any of it:
#   make install TEAM=ABCDE12345 BUNDLE_ID=com.you.aria DEVICE=<udid>

PROJECT  := Ailen.xcodeproj
SCHEME   := Ailen
TESTS    := AilenTests
BUILD    := build

# Your Apple Developer Team ID, read out of the signing certificate Xcode
# created when you signed in. The `OU` field of the cert subject is the team.
TEAM ?= $(shell security find-certificate -a -c "Apple Development" -p 2>/dev/null \
	| openssl x509 -noout -subject 2>/dev/null \
	| sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)

# Bundle IDs must be globally unique across the App Store, so the committed
# one won't register under your account. Deriving it from your team ID gives
# you an ID nobody else can be holding.
BUNDLE_ID ?= dev.$(TEAM).aria

# First paired iPhone/iPad (not a simulator) `devicectl` can see. The UDID is matched
# by pattern because device names may contain spaces.
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null \
	| grep -E 'available|connected' | grep -v simulated \
	| grep -oE '[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1)

# 1,2 = iPhone and native iPad (default). 1 = iPhone only (scaled on iPad).
DEVICE_FAMILY ?= 1,2

# First available iPhone simulator, whatever this Xcode happens to ship.
# (Matched without parentheses on purpose — make can't parse an unbalanced
# one inside $(shell ...).)
SIM ?= $(shell xcrun simctl list devices available 2>/dev/null \
	| grep -o 'iPhone [0-9][0-9a-zA-Z ]*' | sed 's/ *$$//' | tail -1)

SIGNING := DEVELOPMENT_TEAM=$(TEAM) PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID) TARGETED_DEVICE_FAMILY=$(DEVICE_FAMILY)
APP     := $(BUILD)/Build/Products/Release-iphoneos/$(SCHEME).app

.PHONY: help doctor sim install install-mac test test-mac check clean

help:
	@echo "Ailen — build it yourself"
	@echo
	@echo "  make sim       build and run in the iOS Simulator (no Apple ID needed)"
	@echo "  make install   build and install on your connected iPhone"
	@echo "  make install-mac  build the native macOS app into /Applications"
	@echo "  make test-mac  run the unit tests natively on this Mac"
	@echo "  make test      run the test suite"
	@echo "  make check     compile app and tests without a simulator"
	@echo "  make doctor    check what you have and what you're missing"
	@echo "  make clean     delete build output"
	@echo
	@echo "Detected:"
	@echo "  Team ID      $(if $(TEAM),$(TEAM),(none — open Xcode and sign in, see 'make doctor'))"
	@echo "  Bundle ID    $(BUNDLE_ID)"
	@echo "  iPhone       $(if $(DEVICE),$(DEVICE),(none paired))"
	@echo "  Simulator    $(if $(SIM),$(SIM),(none))"

doctor:
	@fail=0; \
	if [ "$$(uname)" != "Darwin" ]; then \
		echo "✗ Not macOS. Building an iOS app requires a Mac — there is no way around this."; \
		exit 1; \
	fi; \
	if ! xcodebuild -version >/dev/null 2>&1; then \
		echo "✗ Xcode not found. Install it from the App Store, then run:"; \
		echo "    sudo xcode-select -s /Applications/Xcode.app"; \
		fail=1; \
	else \
		echo "✓ $$(xcodebuild -version | head -1)"; \
	fi; \
	if [ -z "$(TEAM)" ]; then \
		echo "✗ No signing certificate. Open Xcode → Settings → Accounts, add your"; \
		echo "  Apple ID (a free one works), then open $(PROJECT) once and pick your"; \
		echo "  team under Signing & Capabilities. Re-run 'make doctor'."; \
		echo "  Or skip signing entirely and use 'make sim'."; \
		fail=1; \
	else \
		echo "✓ Team ID $(TEAM) → bundle ID $(BUNDLE_ID)"; \
	fi; \
	if [ -z "$(DEVICE)" ]; then \
		echo "· No iPhone paired. Plug one in, unlock it, and tap Trust."; \
		echo "  ('make sim' needs no phone at all.)"; \
	else \
		echo "✓ iPhone $(DEVICE)"; \
	fi; \
	[ $$fail -eq 0 ] && echo && echo "Ready. Run 'make install' (or 'make sim')." || exit 1

sim:
	@test -n "$(SIM)" || { echo "No iOS simulator installed. Open Xcode → Settings → Components."; exit 1; }
	@echo "Building for the $(SIM) simulator…"
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-destination "platform=iOS Simulator,name=$(SIM)" \
		-derivedDataPath "$(BUILD)" CODE_SIGNING_ALLOWED=NO build
	@open -a Simulator
	@xcrun simctl boot "$(SIM)" 2>/dev/null || true
	@xcrun simctl install booted "$(BUILD)/Build/Products/Debug-iphonesimulator/$(SCHEME).app"
	@xcrun simctl launch booted "$$(plutil -extract CFBundleIdentifier raw -o - \
		"$(BUILD)/Build/Products/Debug-iphonesimulator/$(SCHEME).app/Info.plist")"
	@echo
	@echo "Running in the simulator. It starts as a local-file player with no server"
	@echo "configured — add one under More → Backend, or just import some files."

install:
	@$(MAKE) --no-print-directory doctor >/dev/null || { $(MAKE) --no-print-directory doctor; exit 1; }
	@test -n "$(DEVICE)" || { echo "No iPhone found. Plug one in, unlock it, tap Trust, then re-run."; exit 1; }
	@echo "Building for your iPhone as $(BUNDLE_ID)…"
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-configuration Release -destination "id=$(DEVICE)" \
		-derivedDataPath "$(BUILD)" -allowProvisioningUpdates -allowProvisioningDeviceRegistration $(SIGNING) build
	xcrun devicectl device install app --device "$(DEVICE)" "$(APP)"
	@echo
	@echo "Installed. Open Ailen on your device."
	@echo
	@echo "  First launch will say the developer is untrusted. On your iPhone:"
	@echo "  Settings → General → VPN & Device Management → trust your Apple ID."
	@echo
	@echo "  If you used a FREE Apple ID, this build STOPS LAUNCHING IN 7 DAYS."
	@echo "  That is Apple's limit, not Ailen's. Re-run 'make install' to reset the"
	@echo "  clock — your music and settings are kept. A paid account ($$99/yr)"
	@echo "  raises it to a year."

test:
	xcodebuild test -project "$(PROJECT)" -scheme "$(TESTS)" \
		-destination "platform=iOS Simulator,name=$(SIM)" \
		-derivedDataPath "$(BUILD)" CODE_SIGNING_ALLOWED=NO

# Compile-only check: works without an installed simulator runtime.
check:
	xcodebuild build-for-testing -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-destination "generic/platform=iOS Simulator" \
		-derivedDataPath "$(BUILD)" CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf "$(BUILD)"

# Native macOS build, installed to /Applications (signed with your team).
install-mac:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release \
		-destination "platform=macOS,arch=arm64" -derivedDataPath "$(BUILD)-macos" \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		DEVELOPMENT_TEAM=$(TEAM) PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID) build
	-pkill -x Ailen; sleep 1
	rm -rf /Applications/Ailen.app
	ditto "$(BUILD)-macos/Build/Products/Release/Ailen.app" /Applications/Ailen.app
	open /Applications/Ailen.app
	@echo "Installed natively to /Applications/Ailen.app"

# Unit tests run natively on this Mac (no iOS simulator runtime needed).
# iOS-only test files are excluded for macOS in the test target settings.
test-mac:
	xcodebuild test -project "$(PROJECT)" -scheme "$(TESTS)" \
		-destination "platform=macOS,arch=arm64" -derivedDataPath "$(BUILD)-macos" CODE_SIGNING_ALLOWED=NO
