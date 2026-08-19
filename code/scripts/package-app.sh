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

# The version lives in the code (SecretaryCore/AppVersion.swift) so the app can
# report it with or without a bundle; the plist below is generated from it
# rather than carrying a second copy that goes stale.
VERSION_SOURCE="$ROOT/Sources/SecretaryCore/AppVersion.swift"
VERSION="$(sed -n 's/.*AppVersion(major: *\([0-9][0-9]*\), *minor: *\([0-9][0-9]*\), *patch: *\([0-9][0-9]*\)).*/\1.\2.\3/p' "$VERSION_SOURCE" | head -1)"
if [[ -z "$VERSION" ]]; then
    echo "✗ Could not read the version from $VERSION_SOURCE" >&2
    echo "  Expected a line like: AppVersion(major: 0, minor: 5, patch: 0)" >&2
    exit 1
fi

# Which commit this bundle was actually built from. Two bundles can carry the
# same version number and different code — that is exactly how a fixed feature
# appears to come back broken — so the build is stamped and shown in the app.
BUILD="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
if ! git -C "$ROOT" diff --quiet HEAD 2>/dev/null; then
    BUILD="${BUILD}-dirty"
fi

echo "▸ Building ($CONFIG) — version ${VERSION} (${BUILD} on ${BRANCH})…"
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

# Generate the app icon. The source is committed at docs/App-Icon.png — the
# app's own artwork, drawn for this purpose, so unlike the character portraits
# it carries no licence question and doesn't have to be built from whatever
# image the person running the script happens to have installed. It used to
# default to ~/Library/Application Support/AISecretary/character.png, which
# meant two machines packaging the same commit produced two different icons.
# Override with ICON_SRC.
ICON_SRC="${ICON_SRC:-$ROOT/../docs/App-Icon.png}"
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
    echo "▸ No icon source at ${ICON_SRC} — bundling without a custom icon."
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
    <string>$VERSION</string>
    <!-- Which commit this was built from. A separate key rather than
         CFBundleVersion, whose format the App Store constrains. -->
    <key>AISecretaryBuild</key>
    <string>$BUILD</string>
    <key>AISecretaryBranch</key>
    <string>$BRANCH</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Left empty on purpose: the About window prints this under the credits,
         and the app's own name there just read as a duplicate. -->
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Finder is willing to launch it locally without an extra prompt.
if command -v codesign >/dev/null 2>&1; then
    echo "▸ Ad-hoc signing…"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
        echo "  (ad-hoc signing skipped — the app still runs)"
fi

# Exactly one bundle, always. Worktrees mean several checkouts of this repo can
# each hold an AISecretary.app, all with the same bundle id and version and
# different code inside; launching the wrong one looks exactly like a feature
# that has stopped working. The one just built is the only one that survives.
REPO_ROOT="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
    while IFS= read -r other; do
        [[ "$other" == "$APP_DIR" ]] && continue
        echo "▸ Removing an older bundle: $other"
        rm -rf "$other"
    done < <(find "$REPO_ROOT" -name "AISecretary.app" -not -path "*/.build/*" 2>/dev/null)
fi

echo "✓ Built $APP_DIR  (version $VERSION, build $BUILD on $BRANCH)"
echo "  Double-click it in Finder, or run:  open \"$APP_DIR\""
echo "  To install:  cp -R \"$APP_DIR\" /Applications/"
