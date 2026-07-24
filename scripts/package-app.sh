#!/bin/bash
#
# Packages the SPM executable into a proper macOS .app bundle so it can be
# launched from Finder (double-click) without opening a Terminal window.
#
# The bundle is marked as an agent (LSUIElement = true), matching the app's
# .accessory activation policy: no Dock icon, no menu bar — it lives in the
# floating character window and the status-bar menu.
#
# Usage:
#   ./scripts/package-app.sh            # release build (default)
#   ./scripts/package-app.sh debug      # debug build
#
# Output: ./AISecretary.app  (drag it to /Applications if you like)

set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="AI Secretary"
BUNDLE_ID="com.aisecretary.app"
EXECUTABLE="AISecretaryApp"

# Resolve repo root relative to this script so it works from anywhere.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$EXECUTABLE"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "✗ Built executable not found at $BIN_PATH" >&2
    exit 1
fi

APP_DIR="$ROOT/AISecretary.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$MACOS/$EXECUTABLE"

# Generate the app icon from the local character image, if present. The art is
# never committed (it may be licensed), so the icon is built at package time
# from whatever character.png the user has installed. Override with ICON_SRC.
ICON_SRC="${ICON_SRC:-$HOME/Library/Application Support/AISecretary/character.png}"
ICON_LINE=""
if [[ -f "$ICON_SRC" ]]; then
    echo "▸ Building icon from ${ICON_SRC}…"
    if swift "$ROOT/scripts/make-icon.swift" "$ICON_SRC" "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null; then
        ICON_LINE="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
    else
        echo "  (icon generation failed — bundling without a custom icon)"
    fi
else
    echo "▸ No character.png found — bundling without a custom icon."
    echo "  (set ICON_SRC=/path/to/image.png to use your own)"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
$ICON_LINE
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.4.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>AI Secretary</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Finder is willing to launch it locally without an extra prompt.
if command -v codesign >/dev/null 2>&1; then
    echo "▸ Ad-hoc signing…"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
        echo "  (ad-hoc signing skipped — the app still runs)"
fi

echo "✓ Built $APP_DIR"
echo "  Double-click it in Finder, or run:  open \"$APP_DIR\""
echo "  To install:  cp -R \"$APP_DIR\" /Applications/"
