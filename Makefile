PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
APPDIR = $(PREFIX)/Applications
APP_NAME = Monitor Keyboard Fix
BUNDLE_ID = com.shyamalschandra.MonitorKeyboardFix
VERSION = 1.0.0

BUILD_DIR = MonitorKeyboardFix/.build
RELEASE_BIN = $(BUILD_DIR)/release/MonitorKeyboardFix
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build release install uninstall app-bundle clean dist

build:
	cd MonitorKeyboardFix && swift build

release:
	cd MonitorKeyboardFix && swift build -c release --arch arm64

app-bundle: release
	@echo "Creating $(APP_NAME).app bundle..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(RELEASE_BIN)" "$(APP_BUNDLE)/Contents/MacOS/MonitorKeyboardFix"
	@cp MonitorKeyboardFix/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp MonitorKeyboardFix/Sources/MonitorKeyboardFix/Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@echo "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Created and signed $(APP_BUNDLE)"

install: release
	@echo "Installing MonitorKeyboardFix to $(BINDIR)..."
	@install -d "$(BINDIR)"
	@install -m 755 "$(RELEASE_BIN)" "$(BINDIR)/monitor-keyboard-fix"
	@echo "Installed. Run with: monitor-keyboard-fix"

uninstall:
	@rm -f "$(BINDIR)/monitor-keyboard-fix"
	@echo "Uninstalled monitor-keyboard-fix from $(BINDIR)"

dist: app-bundle
	@echo "Creating release archive..."
	@cd "$(BUILD_DIR)" && tar -czf "MonitorKeyboardFix-$(VERSION).tar.gz" "$(APP_NAME).app"
	@cd MonitorKeyboardFix && tar -czf "../$(BUILD_DIR)/MonitorKeyboardFix-$(VERSION)-source.tar.gz" \
		--exclude='.build' \
		-C .. MonitorKeyboardFix
	@echo "Archives created:"
	@echo "  $(BUILD_DIR)/MonitorKeyboardFix-$(VERSION).tar.gz (app bundle)"
	@echo "  $(BUILD_DIR)/MonitorKeyboardFix-$(VERSION)-source.tar.gz (source)"

clean:
	cd MonitorKeyboardFix && swift package clean
	rm -rf "$(APP_BUNDLE)"
