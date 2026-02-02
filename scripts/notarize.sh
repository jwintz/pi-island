#!/bin/bash
#
# Notarizes a DMG for distribution
# Requires Apple Developer Program membership
#
# Usage:
#   export APPLE_ID="your@email.com"
#   export APPLE_PASSWORD="app-specific-password"
#   export APPLE_TEAM_ID="TEAM_ID"
#   ./scripts/notarize.sh Pi-Island-0.1.0.dmg
#

set -e

DMG_PATH="$1"

if [ -z "$DMG_PATH" ]; then
    echo "Usage: $0 <path-to-dmg>"
    exit 1
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: File $DMG_PATH not found"
    exit 1
fi

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
    echo "Error: Environment variables APPLE_ID, APPLE_PASSWORD, and APPLE_TEAM_ID must be set."
    echo "Create an app-specific password at: https://appleid.apple.com/"
    exit 1
fi

echo "Submitting $DMG_PATH for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "Done! $DMG_PATH is now notarized and stapled."
echo "You can verify it with: spctl -a -vv -t install \"$DMG_PATH\""
