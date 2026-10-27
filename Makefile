# Local build helpers for this fork. Run from the repository root.
#
#   make test     run the logic tests (no Xcode test runner needed)
#   make build    build the Release app
#   make install  test, build, replace /Applications/Boring Notch.app and relaunch it

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

BUNDLE_ID := theboringteam.boringnotch
DERIVED_DATA := build/DerivedData
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Boring Notch.app
INSTALLED_APP := /Applications/Boring Notch.app

# Foundation-only files the tests compile against
LOGIC_SOURCES := \
	boringNotch/helpers/DevTransforms.swift \
	boringNotch/helpers/SecurityTransforms.swift \
	boringNotch/helpers/DevServerParser.swift \
	boringNotch/helpers/SystemStats.swift \
	boringNotch/helpers/ClipboardDetector.swift \
	boringNotch/helpers/StudyStats.swift \
	boringNotch/helpers/Flashcards.swift \
	boringNotch/helpers/MonthGrid.swift
TEST_SOURCES := $(wildcard Tests/LogicTests/*.swift)
TEST_BINARY := build/tests/logic-tests

# There is no developer certificate on this Mac, so the app is signed ad hoc. Hardened runtime
# must be off then: dyld refuses the prebuilt MediaRemoteAdapter.framework otherwise, because
# its Team ID can't match an ad-hoc signed app. The app sandbox stays on.
SIGNING := CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO

.PHONY: test build install

test:
	@mkdir -p build/tests
	@xcrun swiftc -o $(TEST_BINARY) $(LOGIC_SOURCES) $(TEST_SOURCES)
	@./$(TEST_BINARY)

build:
	xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
		-derivedDataPath $(DERIVED_DATA) $(SIGNING) -quiet
	codesign --verify --deep --strict "$(RELEASE_APP)"

install: test build
	@echo "Quitting Boring Notch..."
	@if pgrep -f "Boring Notch.app/Contents/MacOS/Boring Notch" >/dev/null; then \
		osascript -e 'tell application id "$(BUNDLE_ID)" to quit'; \
		for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "Boring Notch.app/Contents/MacOS/Boring Notch" >/dev/null || break; sleep 0.5; done; \
	fi
	@pkill -f "Boring Notch.app/Contents/Resources/mediaremote-adapter.pl" || true
	@pkill -f "BoringNotchXPCHelper.xpc/Contents/MacOS/BoringNotchXPCHelper" || true
	rm -rf "$(INSTALLED_APP)"
	ditto "$(RELEASE_APP)" "$(INSTALLED_APP)"
	@# Sparkle would otherwise replace this build with the official release
	@defaults write $(BUNDLE_ID) SUEnableAutomaticChecks -bool false
	@defaults write $(BUNDLE_ID) SUAutomaticallyUpdate -bool false
	open "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"
