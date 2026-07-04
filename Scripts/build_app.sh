#!/bin/bash
#
# build_app.sh — Build n-doc monitor as a distributable .app bundle.
#
# Usage:
#   ./Scripts/build_app.sh            # Build .app only
#   ./Scripts/build_app.sh --dmg      # Build .app and wrap in a .dmg
#
# Output:
#   build/n-doc monitor.app           # The application bundle
#   build/n-doc-monitor-1.0.0.dmg     # (with --dmg) Disk image for distribution
#
# The app is ad-hoc signed (no Apple Developer ID required).
# Recipients will need to right-click → Open on first launch.

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────
APP_NAME="n-doc monitor"
BUNDLE_NAME="n-doc monitor.app"
EXECUTABLE_NAME="NDocMonitor"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$BUNDLE_NAME"

# ── Step 1: Build release binary ──────────────────────────────────
echo "▸ Building release binary…"
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -3

# Find the built binary
BINARY=$(swift build -c release --show-bin-path)/$EXECUTABLE_NAME
if [ ! -f "$BINARY" ]; then
    echo "✗ Binary not found at $BINARY"
    exit 1
fi
echo "  Binary: $BINARY"

# ── Step 2: Create .app bundle structure ──────────────────────────
echo "▸ Creating app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Copy app icon if it exists
if [ -d "$PROJECT_DIR/Resources/AppIcon.icns" ] || [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
    echo "  App icon: included"
else
    echo "  App icon: none (using default)"
fi

# ── Step 3: Ad-hoc code sign ─────────────────────────────────────
echo "▸ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR"
echo "  Signed: $APP_DIR"

# ── Step 4: Verify ───────────────────────────────────────────────
echo "▸ Verifying…"
codesign --verify --verbose "$APP_DIR" 2>&1 | head -5
echo ""
echo "✔ Built: $APP_DIR"
echo "  Size: $(du -sh "$APP_DIR" | cut -f1)"

# ── Step 5 (optional): Create .dmg ───────────────────────────────
if [ "${1:-}" = "--dmg" ]; then
    DMG_NAME="n-doc-monitor-$VERSION.dmg"
    DMG_PATH="$BUILD_DIR/$DMG_NAME"

    echo ""
    echo "▸ Creating DMG…"

    # Remove old DMG if it exists
    rm -f "$DMG_PATH"

    # Create a temporary directory for DMG contents
    DMG_STAGE="$BUILD_DIR/dmg-stage"
    rm -rf "$DMG_STAGE"
    mkdir -p "$DMG_STAGE"
    cp -R "$APP_DIR" "$DMG_STAGE/"

    # Create a symlink to /Applications for drag-install
    ln -s /Applications "$DMG_STAGE/Applications"

    # Create DMG
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGE" \
        -ov \
        -format UDZO \
        "$DMG_PATH" \
        2>&1 | tail -3

    # Clean up staging
    rm -rf "$DMG_STAGE"

    echo "✔ DMG: $DMG_PATH"
    echo "  Size: $(du -sh "$DMG_PATH" | cut -f1)"
fi

echo ""
echo "Done! To install:"
echo "  1. Drag '$APP_NAME' to /Applications"
echo "  2. Right-click → Open on first launch (ad-hoc signed)"
