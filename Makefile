APP := Promptu.app
BIN := .build/release/Promptu
ICONSET := .build/AppIcon.iconset
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)

.PHONY: app icon run dev test install zip clean

# Host-arch only: a universal (--arch arm64 --arch x86_64) build needs
# full Xcode, not just the Command Line Tools.
app: icon
	swift build -c release
	rm -rf dist/$(APP)
	mkdir -p dist/$(APP)/Contents/MacOS dist/$(APP)/Contents/Resources
	cp Info.plist dist/$(APP)/Contents/Info.plist
	cp $(BIN) dist/$(APP)/Contents/MacOS/Promptu
	cp .build/AppIcon.icns dist/$(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - dist/$(APP)

icon:
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	swift scripts/make-icon.swift mascot.svg $(ICONSET)
	iconutil -c icns $(ICONSET) -o .build/AppIcon.icns

run:
	swift run

format:
	swift format -ir Sources/

# The edit loop: rebuild and relaunch on every source change. Sweeps
# up any earlier loop and stray instance first.
#
# The -x -f pair matches watchexec's exact command line, not this recipe's own
# shell (a plain -f pattern would kill it).
dev:
	@command -v watchexec >/dev/null || { echo "make dev needs watchexec (brew install watchexec)"; exit 1; }
	-pkill -x -f "watchexec -r -e swift -- swift run"
	-pkill -x Promptu
	watchexec -r -e swift -- swift run

test:
	swift test

install: app
	rm -rf /Applications/$(APP)
	cp -R dist/$(APP) /Applications/

# Release artifact for GitHub Releases; ditto preserves the bundle
# structure and signature the way Archive Utility expects.
zip: app
	ditto -c -k --keepParent dist/$(APP) dist/Promptu-$(VERSION).zip

clean:
	rm -rf .build dist
