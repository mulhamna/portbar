#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="PortBar"
SCHEME="PortBar"
BUNDLE_ID="com.portbar.PortBar"

# Read version from project
VERSION=$(xcodebuild -project "$PROJECT_ROOT/PortBar.xcodeproj" \
  -scheme "$SCHEME" \
  -showBuildSettings 2>/dev/null \
  | grep "MARKETING_VERSION" | awk '{print $3}' | head -1)

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
RELEASE_DIR="$BUILD_DIR/Release"
APP_PATH="$RELEASE_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "Building $APP_NAME $VERSION..."

# Build release
xcodebuild \
  -project "$PROJECT_ROOT/PortBar.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CONFIGURATION_BUILD_DIR="$RELEASE_DIR" \
  build

echo "Build complete: $APP_PATH"

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create DMG
if command -v create-dmg &>/dev/null; then
  echo "Using create-dmg..."
  create-dmg \
    --volname "$APP_NAME" \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 130 160 \
    --app-drop-link 400 160 \
    --hide-extension "$APP_NAME.app" \
    "$DMG_PATH" \
    "$RELEASE_DIR/"
else
  echo "create-dmg not found, using hdiutil..."
  STAGING="$BUILD_DIR/dmg-staging"
  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  cp -r "$APP_PATH" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  rm -rf "$STAGING"
fi

echo ""
echo "DMG ready: $DMG_PATH"
echo ""
echo "SHA256 (for Homebrew cask):"
shasum -a 256 "$DMG_PATH"
