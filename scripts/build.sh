#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IntelliWhisper"
BUILD_DIR="$PROJECT_ROOT/.build"
CORE_APP_NAME="${APP_NAME} Core"
APP_BUNDLE="$BUILD_DIR/${CORE_APP_NAME}.app"
ENTITLEMENTS="$PROJECT_ROOT/Resources/${APP_NAME}.entitlements"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --release   Build in release mode (default: debug)
  --pkg       Create .pkg installer (installs to /Applications)
  --zip       Create .zip with just the .app bundle
  --direct    Create .zip with launcher workaround (runs binary directly)
  --all       Create all three artifacts (--pkg --zip --direct)
  --help      Show this help message

Artifact flags imply --release. Debug builds only produce the .app bundle.
EOF
}

# ---------------------------------------------------------------------------
# Shared helper: build the launcher app bundle into a given directory
# ---------------------------------------------------------------------------
build_launcher() {
    local output_dir="$1"
    local launcher_app="$output_dir/${APP_NAME}.app"
    local macos_dir="$launcher_app/Contents/MacOS"
    local plist="$launcher_app/Contents/Info.plist"

    local resources_dir="$launcher_app/Contents/Resources"

    # Build a real app bundle from scratch (no osacompile) so the binary
    # identity is genuinely "IntelliWhisper", not the system "applet".
    rm -rf "$launcher_app"
    mkdir -p "$macos_dir"
    mkdir -p "$resources_dir"

    # App icon
    local icon_src="$PROJECT_ROOT/Resources/${APP_NAME}.icns"
    if [ -f "$icon_src" ]; then
        cp "$icon_src" "$resources_dir/${APP_NAME}.icns"
    fi

    # Launcher executable — a simple shell script
    cat > "$macos_dir/${APP_NAME}" <<'LAUNCHER'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
"$DIR/IntelliWhisper Core.app/Contents/MacOS/IntelliWhisper" &>/dev/null &
LAUNCHER
    chmod +x "$macos_dir/${APP_NAME}"

    # Info.plist
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>de.intellilab.${APP_NAME}.Launcher</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

    codesign --force --sign - "$launcher_app"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CONFIG="debug"
BUILD_PKG=false
BUILD_ZIP=false
BUILD_DIRECT=false

for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="release" ;;
        --pkg)     CONFIG="release"; BUILD_PKG=true ;;
        --zip)     CONFIG="release"; BUILD_ZIP=true ;;
        --direct)  CONFIG="release"; BUILD_DIRECT=true ;;
        --all)     CONFIG="release"; BUILD_PKG=true; BUILD_ZIP=true; BUILD_DIRECT=true ;;
        --help|-h) usage; exit 0 ;;
        *)         echo "Unknown option: $arg"; echo ""; usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "Building ${APP_NAME} ($CONFIG)..."
cd "$PROJECT_ROOT"
swift build -c "$CONFIG"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$CONFIG/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ENTITLEMENTS" "$APP_BUNDLE/Contents/Resources/${APP_NAME}.entitlements"
cp "$PROJECT_ROOT/Resources/${APP_NAME}.icns" "$APP_BUNDLE/Contents/Resources/${APP_NAME}.icns"

# ---------------------------------------------------------------------------
# Sign (release only)
# ---------------------------------------------------------------------------
if [[ "$CONFIG" == "release" ]]; then
    echo "Signing app bundle..."
    codesign --force --sign - "$APP_BUNDLE"
fi

# ---------------------------------------------------------------------------
# Artifact: .pkg installer
# ---------------------------------------------------------------------------
if $BUILD_PKG; then
    echo "Creating .pkg installer..."

    PKG_ROOT="$BUILD_DIR/pkg-root"
    PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"
    INSTALL_DIR="$PKG_ROOT/Applications/${APP_NAME}"

    rm -rf "$PKG_ROOT" "$PKG_SCRIPTS"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$PKG_SCRIPTS"

    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

    echo "  Creating launcher..."
    build_launcher "$INSTALL_DIR"

    # postinstall: auto-launch and add to Dock after installation
    cat > "$PKG_SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/bash
TARGET="${2%/}"
APP_PATH="$TARGET/Applications/IntelliWhisper/IntelliWhisper.app"
CORE_APP="$TARGET/Applications/IntelliWhisper/IntelliWhisper Core.app"
INSTALL_USER="${USER:-$(stat -f '%Su' /dev/console)}"

# Launch the core app
if [ -d "$CORE_APP" ]; then
    su "$INSTALL_USER" -c "open '$CORE_APP'" &
fi

# Add launcher to Dock if not already present
if ! su "$INSTALL_USER" -c "defaults read com.apple.dock persistent-apps" | grep -q "IntelliWhisper.app"; then
    su "$INSTALL_USER" -c "defaults write com.apple.dock persistent-apps -array-add '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>'"
    su "$INSTALL_USER" -c "killall Dock" 2>/dev/null || true
fi
exit 0
POSTINSTALL
    chmod +x "$PKG_SCRIPTS/postinstall"

    # Disable bundle relocation so .app always installs to /Applications
    COMPONENT_PLIST="$BUILD_DIR/component.plist"
    pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST"
    plutil -replace 0.BundleIsRelocatable -bool false "$COMPONENT_PLIST"
    plutil -replace 1.BundleIsRelocatable -bool false "$COMPONENT_PLIST"

    PKG_PATH="$BUILD_DIR/${APP_NAME}.pkg"
    rm -f "$PKG_PATH"
    pkgbuild \
        --root "$PKG_ROOT" \
        --component-plist "$COMPONENT_PLIST" \
        --identifier "de.intellilab.${APP_NAME}" \
        --version "1.0" \
        --scripts "$PKG_SCRIPTS" \
        "$PKG_PATH"
fi

# ---------------------------------------------------------------------------
# Artifact: plain .zip
# ---------------------------------------------------------------------------
if $BUILD_ZIP; then
    echo "Creating .zip..."
    ZIP_PATH="$BUILD_DIR/${APP_NAME}.zip"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
fi

# ---------------------------------------------------------------------------
# Artifact: direct launcher .zip (workaround for TCC issues)
# ---------------------------------------------------------------------------
if $BUILD_DIRECT; then
    echo "Creating direct launcher .zip..."

    DIRECT_DIR="$BUILD_DIR/${APP_NAME}-direct"
    rm -rf "$DIRECT_DIR"
    mkdir -p "$DIRECT_DIR"

    cp -R "$APP_BUNDLE" "$DIRECT_DIR/"

    echo "  Creating launcher..."
    build_launcher "$DIRECT_DIR"

    cat > "$DIRECT_DIR/Fix Permissions.command" <<'FIXSCRIPT'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
xattr -cr "$DIR"
echo ""
echo "Done! You can now open 'IntelliWhisper'."
echo "Press any key to close..."
read -n 1
FIXSCRIPT
    chmod +x "$DIRECT_DIR/Fix Permissions.command"

    DIRECT_ZIP_PATH="$BUILD_DIR/${APP_NAME}-direct.zip"
    rm -f "$DIRECT_ZIP_PATH"
    ditto -c -k --keepParent "$DIRECT_DIR" "$DIRECT_ZIP_PATH"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "App bundle: $APP_BUNDLE"
$BUILD_PKG    && echo "Installer:  ${PKG_PATH:-}"
$BUILD_ZIP    && echo "Zip:        ${ZIP_PATH:-}"
$BUILD_DIRECT && echo "Direct zip: ${DIRECT_ZIP_PATH:-}"

if ! $BUILD_PKG && ! $BUILD_ZIP && ! $BUILD_DIRECT; then
    if [[ "$CONFIG" == "debug" ]]; then
        echo ""
        echo "To run: open $APP_BUNDLE"
        echo "Or:     $APP_BUNDLE/Contents/MacOS/${APP_NAME}"
    fi
fi

# Print instructions for whichever artifacts were built
if $BUILD_PKG; then
    echo ""
    echo "=== .pkg instructions ==="
    echo "  1. Double-click ${APP_NAME}.pkg (right-click → Open if blocked)"
    echo "  2. Click through installer (Continue → Install)"
    echo "  3. App launches automatically after install"
    echo "  4. Grant permissions when prompted, relaunch once for Input Monitoring"
    echo "  Relaunch: open '/Applications/${APP_NAME}/${APP_NAME}.app'"
fi

if $BUILD_DIRECT; then
    echo ""
    echo "=== Direct launcher instructions ==="
    echo "  1. Unzip ${APP_NAME}-direct.zip"
    echo "  2. Double-click 'Fix Permissions' (right-click → Open if prompted)"
    echo "  3. Double-click '${APP_NAME}' (right-click → Open first time)"
    echo "  4. Grant permissions when prompted, relaunch once for Input Monitoring"
fi
