APP = build/Claude Kullanım.app
VERSION = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP = build/ClaudeUsage-$(VERSION)-macos-universal.zip
ARCHS =

.PHONY: app run install release clean

app:
	swift build -c release $(ARCHS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$(swift build -c release $(ARCHS) --show-bin-path)/ClaudeUsage" "$(APP)/Contents/MacOS/ClaudeUsage"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

run: app
	open "$(APP)"

install: app
	pkill -x ClaudeUsage || true
	rm -rf "$(HOME)/Applications/Claude Kullanım.app"
	mkdir -p "$(HOME)/Applications"
	cp -R "$(APP)" "$(HOME)/Applications/"
	open "$(HOME)/Applications/Claude Kullanım.app"

# Universal (arm64 + x86_64) build zipped for GitHub Releases
release:
	$(MAKE) app ARCHS="--arch arm64 --arch x86_64"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	shasum -a 256 "$(ZIP)"

clean:
	rm -rf .build build
