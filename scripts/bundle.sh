#!/bin/bash
#
# Creates a proper macOS .app bundle from the SPM build
# This enables: app icon, no terminal on launch, proper LSUIElement behavior
#
# Usage:
#   ./scripts/bundle.sh              # Build app bundle only
#   ./scripts/bundle.sh --dmg        # Build app bundle + DMG
#   ./scripts/bundle.sh --sign       # Build + ad-hoc sign (for local use)
#   ./scripts/bundle.sh --sign-id "Developer ID Application: Name" --dmg  # Full release
#

set -e

# Configuration
APP_NAME="Pi Island"
BUNDLE_ID="me.jwintz.pi-island"
EXECUTABLE="PiIsland"
VERSION="0.1.0"

# Parse arguments
CREATE_DMG=false
SIGN_APP=false
SIGN_IDENTITY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dmg)
            CREATE_DMG=true
            shift
            ;;
        --sign)
            SIGN_APP=true
            shift
            ;;
        --sign-id)
            SIGN_APP=true
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy executable
cp "$BUILD_DIR/$EXECUTABLE" "$MACOS/"

# Copy resource bundle (contains assets)
if [ -d "$BUILD_DIR/${EXECUTABLE}_${EXECUTABLE}.bundle" ]; then
    cp -R "$BUILD_DIR/${EXECUTABLE}_${EXECUTABLE}.bundle" "$RESOURCES/"
fi

# Create Info.plist
cat > "$CONTENTS/Info.plist" << EOF
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
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Generate icon using actool from .icon package (Xcode 15+ format)
ICON_PACKAGE="$PROJECT_DIR/pi-island.icon"
if [ -d "$ICON_PACKAGE" ]; then
    echo "Compiling icon from .icon package..."
    ICON_OUTPUT=$(mktemp -d)

    xcrun actool --compile "$ICON_OUTPUT" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon pi-island \
        --output-partial-info-plist "$ICON_OUTPUT/Info.plist" \
        "$ICON_PACKAGE" 2>/dev/null

    # Extract the generated icns to an iconset, then add missing sizes
    if [ -f "$ICON_OUTPUT/pi-island.icns" ]; then
        ICONSET="$ICON_OUTPUT/AppIcon.iconset"
        iconutil -c iconset "$ICON_OUTPUT/pi-island.icns" -o "$ICONSET" 2>/dev/null || mkdir -p "$ICONSET"

        # Find the largest available icon to use as source
        SOURCE_ICON=""
        for size in 512 256 128; do
            if [ -f "$ICONSET/icon_${size}x${size}@2x.png" ]; then
                SOURCE_ICON="$ICONSET/icon_${size}x${size}@2x.png"
                break
            elif [ -f "$ICONSET/icon_${size}x${size}.png" ]; then
                SOURCE_ICON="$ICONSET/icon_${size}x${size}.png"
                break
            fi
        done

        # If no large icon, use 128x128@2x (256px)
        if [ -z "$SOURCE_ICON" ] && [ -f "$ICONSET/icon_128x128@2x.png" ]; then
            SOURCE_ICON="$ICONSET/icon_128x128@2x.png"
        fi

        # Generate all required sizes using sips
        if [ -n "$SOURCE_ICON" ]; then
            echo "Generating missing icon sizes from $SOURCE_ICON..."
            [ ! -f "$ICONSET/icon_16x16.png" ] && sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET/icon_16x16.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_16x16@2x.png" ] && sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_16x16@2x.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_32x32.png" ] && sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_32x32.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_32x32@2x.png" ] && sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET/icon_32x32@2x.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_128x128.png" ] && sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET/icon_128x128.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_128x128@2x.png" ] && sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_128x128@2x.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_256x256.png" ] && sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_256x256.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_256x256@2x.png" ] && sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_256x256@2x.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_512x512.png" ] && sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_512x512.png" 2>/dev/null
            [ ! -f "$ICONSET/icon_512x512@2x.png" ] && sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET/icon_512x512@2x.png" 2>/dev/null
        fi

        # Recreate icns with all sizes
        iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
        echo "Icon compiled with all resolutions"
    fi

    # Also copy the Assets.car for full icon support
    if [ -f "$ICON_OUTPUT/Assets.car" ]; then
        cp "$ICON_OUTPUT/Assets.car" "$RESOURCES/"
    fi

    rm -rf "$ICON_OUTPUT"
else
    echo "Warning: pi-island.icon not found, falling back to PNG icons"

    # Fallback: Create icns from PNG icons
    ICONSET="$RESOURCES/AppIcon.iconset"
    mkdir -p "$ICONSET"

    ICON_SOURCE="$PROJECT_DIR/Sources/$EXECUTABLE/Assets.xcassets/AppIcon.appiconset"
    if [ -d "$ICON_SOURCE" ]; then
        cp "$ICON_SOURCE/icon_16x16.png" "$ICONSET/icon_16x16.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_32x32.png" "$ICONSET/icon_16x16@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_32x32.png" "$ICONSET/icon_32x32.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_64x64.png" "$ICONSET/icon_32x32@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_128x128.png" "$ICONSET/icon_128x128.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_256x256.png" "$ICONSET/icon_128x128@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_256x256.png" "$ICONSET/icon_256x256.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_512x512.png" "$ICONSET/icon_256x256@2x.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_512x512.png" "$ICONSET/icon_512x512.png" 2>/dev/null || true
        cp "$ICON_SOURCE/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png" 2>/dev/null || true

        iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
        rm -rf "$ICONSET"
    fi
fi

# Code signing
if [ "$SIGN_APP" = true ]; then
    echo "Signing app bundle..."
    if [ -n "$SIGN_IDENTITY" ]; then
        # Sign with Developer ID for distribution
        codesign --force --deep --options runtime \
            --sign "$SIGN_IDENTITY" \
            --entitlements /dev/stdin \
            "$APP_BUNDLE" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS
        echo "Signed with: $SIGN_IDENTITY"
    else
        # Ad-hoc signing (for local use only)
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo "Ad-hoc signed (local use only)"
    fi
fi

# Create DMG
if [ "$CREATE_DMG" = true ]; then
    echo "Creating DMG..."
    DMG_NAME="Pi-Island-${VERSION}.dmg"
    DMG_PATH="$PROJECT_DIR/$DMG_NAME"

    # Remove old DMG if exists
    rm -f "$DMG_PATH"

    # Create temporary directory for DMG contents
    DMG_TEMP=$(mktemp -d)
    cp -R "$APP_BUNDLE" "$DMG_TEMP/"

    # Create symbolic link to Applications
    ln -s /Applications "$DMG_TEMP/Applications"

    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_TEMP"

    if [ "$SIGN_APP" = true ] && [ -n "$SIGN_IDENTITY" ]; then
        echo "Signing DMG..."
        codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
    fi

    echo "Created: $DMG_PATH"
fi

echo ""
echo "Created: $APP_BUNDLE"
echo ""

if [ "$SIGN_APP" != true ]; then
    echo "WARNING: App is not signed. Recipients may see 'damaged' error."
    echo "To sign for distribution, use:"
    echo "  ./scripts/bundle.sh --sign-id \"Developer ID Application: Your Name\" --dmg"
    echo ""
    echo "For local testing without signing, recipients can run:"
    echo "  xattr -cr \"$APP_NAME.app\""
    echo ""
fi

echo "To install:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "To add to Login Items:"
echo "  Open System Settings > General > Login Items"
echo "  Add '$APP_NAME' from Applications"
echo ""
