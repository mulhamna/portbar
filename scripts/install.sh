#!/usr/bin/env bash
# PortBar installer — downloads the latest release DMG and installs to /Applications.
# Usage: curl -fsSL https://raw.githubusercontent.com/mulhamna/portbar/main/scripts/install.sh | bash
set -euo pipefail

REPO="mulhamna/portbar"
APP="PortBar"
DMG_NAME="PortBar.dmg"

echo "⚡ Installing $APP…"

# Resolve the latest release DMG asset URL from the GitHub API.
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o "https://github.com/$REPO/releases/download/[^\"]*\.dmg" \
    | head -1)

if [ -z "${URL:-}" ]; then
    echo "✗ Could not find a release DMG. Check https://github.com/$REPO/releases" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'hdiutil detach "$TMP/mnt" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

echo "→ Downloading $URL"
curl -fsSL "$URL" -o "$TMP/$DMG_NAME"

echo "→ Mounting"
mkdir -p "$TMP/mnt"
hdiutil attach "$TMP/$DMG_NAME" -nobrowse -quiet -mountpoint "$TMP/mnt"

echo "→ Copying to /Applications"
rm -rf "/Applications/$APP.app"
cp -R "$TMP/mnt/$APP.app" /Applications/

echo "→ Clearing quarantine"
xattr -dr com.apple.quarantine "/Applications/$APP.app" || true

echo "→ Launching"
open "/Applications/$APP.app"

echo "✓ Done — look for the ⚡ icon in your menu bar."
