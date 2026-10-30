#!/bin/bash
# Signs, notarizes, and packages Tidybyte. Uploading and publishing are
# separate, explicit steps.
#
# Direct channel (Developer ID):
#   SIGNING_IDENTITY="Developer ID Application: NAME (TEAMID)" \
#   NOTARY_PROFILE=tidybyte-notary \
#   SPARKLE_PUBLIC_KEY=... SPARKLE_PRIVATE_KEY_FILE=/secure/ed25519.key \
#   Scripts/package-release.sh direct
#
# Dry run without credentials: SIGNING_IDENTITY=- SKIP_NOTARIZE=1 Scripts/package-release.sh direct
set -euo pipefail
CHANNEL="${1:-direct}"
case "$CHANNEL" in direct|app-store) ;; *) echo "Usage: $0 direct|app-store" >&2; exit 2 ;; esac
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to the channel-specific application signing identity (- for ad hoc)}"

# Direct releases need the Sparkle inputs up front: a release without them
# ships a DMG no existing user ever sees (no feed, no embedded update key).
# Fail before the expensive build/notarize steps. NO_SPARKLE=1 opts out for
# local testing only.
if [ "$CHANNEL" = direct ] && [ -z "${NO_SPARKLE:-}" ]; then
    : "${SPARKLE_PUBLIC_KEY:?direct releases require SPARKLE_PUBLIC_KEY (the app embeds it) — set NO_SPARKLE=1 to override}"
    : "${SPARKLE_PRIVATE_KEY_FILE:?direct releases require SPARKLE_PRIVATE_KEY_FILE (sign_update input) — set NO_SPARKLE=1 to override}"
fi

Scripts/build-app.sh "$CHANNEL"

TIMESTAMP=(--timestamp)
if [ "$SIGNING_IDENTITY" = "-" ]; then TIMESTAMP=(); fi
sign() { codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --sign "$SIGNING_IDENTITY" "$@"; }

if [ "$CHANNEL" = app-store ]; then
    : "${INSTALLER_IDENTITY:?Set INSTALLER_IDENTITY to the Mac Installer Distribution identity}"
    APP=".build/app-store/Tidybyte.app"
    sign --entitlements Configuration/AppStore.entitlements "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" .build/app-store/Tidybyte.pkg
    echo "Upload .build/app-store/Tidybyte.pkg with Transporter, then submit it in App Store Connect."
    exit 0
fi

APP=".build/Tidybyte.app"
OUT=".build/direct"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT/Tidybyte-$VERSION.dmg"
mkdir -p "$OUT"

# Sign inside out: Sparkle's helpers, the framework, the MCP tool, then the app.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FRAMEWORK" ]; then
    sign "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
    sign "$FRAMEWORK/Versions/B/Autoupdate"
    sign "$FRAMEWORK/Versions/B/Updater.app"
    sign "$FRAMEWORK"
fi
sign --identifier com.sakshammittal.tidybyte.mcp "$APP/Contents/MacOS/tidybyte-mcp"
sign --entitlements Configuration/Direct.entitlements "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

notarize() {
    if [ -n "${SKIP_NOTARIZE:-}" ]; then echo "Skipping notarization of $1"; return; fi
    : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

ditto -c -k --keepParent "$APP" "$OUT/Tidybyte.zip"
notarize "$OUT/Tidybyte.zip"
if [ -z "${SKIP_NOTARIZE:-}" ]; then xcrun stapler staple "$APP"; fi
rm -f "$OUT/Tidybyte.zip"

# Disk image with an Applications shortcut.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Tidybyte.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname Tidybyte -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
codesign --force ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --sign "$SIGNING_IDENTITY" "$DMG"
notarize "$DMG"
if [ -z "${SKIP_NOTARIZE:-}" ]; then
    xcrun stapler staple "$DMG"
    spctl --assess --type execute --verbose "$APP"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

# One-item Sparkle appcast for this release (inputs validated at the top).
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ -n "${NO_SPARKLE:-}" ]; then
    :
elif [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ] && [ -x "$SIGN_UPDATE" ]; then
    SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$DMG")"
    BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
    URL="${DOWNLOAD_BASE_URL:-https://github.com/360ghar/tidybyte/releases/download/mac-v$VERSION}/$(basename "$DMG")"
    cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tidybyte for Mac</title>
    <item>
      <title>Tidybyte $VERSION</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML
    echo "Wrote $OUT/appcast.xml"
fi
echo "Release artifact: $DMG"
