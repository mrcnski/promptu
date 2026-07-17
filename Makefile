APP := Promptu.app
BIN := .build/release/Promptu
ICONSET := .build/AppIcon.iconset
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)

.PHONY: app icon run test install zip clean

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
