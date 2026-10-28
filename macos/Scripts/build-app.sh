#!/bin/bash
# Builds Tidybyte.app from the Swift package. Signing and notarization live in
# Scripts/package-release.sh. The version comes from the newest mac-v* tag.

set -euo pipefail

# Configuration
CHANNEL="${1:-direct}"
case "$CHANNEL" in direct|app-store) ;; *) echo "Usage: $0 direct|app-store" >&2; exit 2 ;; esac
SWIFT_FLAGS=()
# APP_STORE=1 also drops the Sparkle dependency from Package.swift. It needs its
# own scratch path: a shared .build keeps the direct build's link plan (Sparkle).
if [ "$CHANNEL" = app-store ]; then
    SWIFT_FLAGS=(-Xswiftc -DAPP_STORE --scratch-path .build/app-store-scratch)
    export APP_STORE=1
fi
APP_NAME="Tidybyte"
MCP_NAME="tidybyte-mcp"
BUNDLE_ID="com.sakshammittal.tidybyte"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$CHANNEL/$APP_NAME.app"
if [ "$CHANNEL" = direct ]; then APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"; fi
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# Version from the newest mac-v* tag (iOS releases use plain v* tags in the
# mono repo). Falls back to 1.0.0 outside a tagged repo.
APP_VERSION="$(git describe --tags --abbrev=0 --match 'mac-v*' 2>/dev/null || echo 'mac-v1.0.0')"
APP_VERSION="${APP_VERSION#mac-v}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo '1')"

echo "Building $APP_NAME..."

# Build the Swift package
swift build -c release --product "$APP_NAME" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
if [ "$CHANNEL" = direct ]; then swift build -c release --product "$MCP_NAME"; fi
BIN_DIR="$(swift build -c release ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --show-bin-path)"

# Create app bundle structure
echo "Creating app bundle..."
mkdir -p "$MACOS_DIR"
# Rebuild generated resources so removed fonts and old target bundles cannot ship.
rm -rf "$RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME.next"
mv -f "$MACOS_DIR/$APP_NAME.next" "$MACOS_DIR/$APP_NAME"

# Direct builds only: the MCP tool, Sparkle, and the autoscan agent. The App
# Store channel is sandboxed and must not carry them.
rm -rf "$CONTENTS/Frameworks" "$CONTENTS/Library"
if [ "$CHANNEL" = direct ]; then
    cp "$BIN_DIR/$MCP_NAME" "$MACOS_DIR/$MCP_NAME"
    if [ -d "$BIN_DIR/Sparkle.framework" ]; then
        mkdir -p "$CONTENTS/Frameworks"
        ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
    fi
    # Autoscan agent registered at runtime through SMAppService.agent(plistName:).
    mkdir -p "$CONTENTS/Library/LaunchAgents"
    cp "Configuration/$BUNDLE_ID.autoscan.plist" "$CONTENTS/Library/LaunchAgents/"
else
    rm -f "$MACOS_DIR/$MCP_NAME"
fi

cp Configuration/PrivacyInfo.xcprivacy "$RESOURCES_DIR/"


# Copy the SPM resource bundle next to the executable. SwiftPM compiles
# Localizable.xcstrings (and any other processed resources) into
# Tidybyte_MacOSCleanerAppKit.bundle; without it, Bundle.module lookups
# (localization) fail at runtime.
for bundle in "$BIN_DIR"/"${APP_NAME}"_*.bundle; do
    if [ -e "$bundle" ]; then
        cp -R "$bundle" "$RESOURCES_DIR/"
        # String(localized:) and standard SwiftUI labels use Bundle.main.
        for locale in "$bundle"/Contents/Resources/*.lproj "$bundle"/*.lproj; do
            if [ -d "$locale" ]; then
                cp -R "$locale" "$RESOURCES_DIR/"
            fi
        done
    fi
done

# App icon: compile the Icon Composer bundle (Liquid Glass layers plus a
# legacy .icns) into Assets.car.
if xcrun --find actool >/dev/null 2>&1; then
    xcrun actool Configuration/Tidybyte.icon --compile "$RESOURCES_DIR" --app-icon Tidybyte \
        --platform macosx --minimum-deployment-target 26.0 --target-device mac \
        --output-partial-info-plist "$BUILD_DIR/icon-partial.plist" >/dev/null
else
    echo "warning: actool not found; the app bundle will have no icon" >&2
fi

# Update feed and signing key come from the release environment.
SPARKLE_KEYS=""
if [ "$CHANNEL" = direct ] && [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
    FEED="${SPARKLE_FEED_URL:-https://tidybyte.360ghar.com/mac/appcast.xml}"
    SPARKLE_KEYS="
    <key>SUFeedURL</key>
    <string>$FEED</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>"
fi

# Create Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Tidybyte</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>Tidybyte</string>
    <key>CFBundleIconName</key>
    <string>Tidybyte</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Review local photos and videos. Confirmed Photos changes can sync to iCloud and are recoverable in Recently Deleted.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Find large, old, and duplicate files on your Desktop. Nothing changes until you approve it.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Find large, old, and duplicate files in Documents. Nothing changes until you approve it.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Find old installers, large files, and duplicates in Downloads. Nothing changes until you approve it.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Scan external drives that you choose. Nothing changes until you approve it.</string>
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>Create verified replacement photos and videos before removing originals.</string>
    <key>CFBundleURLTypes</key>
    <array><dict><key>CFBundleURLName</key><string>Tidybyte navigation</string>
    <key>CFBundleURLSchemes</key><array><string>tidybyte</string></array></dict></array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Saksham Mittal. All rights reserved.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>${SPARKLE_KEYS}
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

if [ "$CHANNEL" = app-store ]; then
    codesign --force --sign - --entitlements Configuration/AppStore.entitlements "$APP_BUNDLE"
fi

echo "App bundle created at: $APP_BUNDLE"
echo "You can now run: open $APP_BUNDLE"
