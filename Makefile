APP = build/Claude Kullanım.app
BIN = .build/release/ClaudeUsage

.PHONY: app run install clean

app:
	swift build -c release
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp $(BIN) "$(APP)/Contents/MacOS/ClaudeUsage"
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

clean:
	rm -rf .build build
