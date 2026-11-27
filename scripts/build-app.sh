#!/bin/bash
# Builds PixelShift.app (universal: Apple Silicon + Intel, sandboxed) into ./build.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Version shown to people comes from ./VERSION. The build number (what Sparkle
# compares to decide an update is newer) is the commit count, so it only goes up.
VERSION="$(cat VERSION)"
BUILD="${BUILD:-$(git rev-list --count HEAD)}"
# Where installed copies look for updates. scripts/release.sh publishes there.
FEED_URL="${FEED_URL:-https://github.com/RivianTrackr/pixelshift/releases/latest/download/appcast.xml}"
SIGN="${SIGN_IDENTITY:--}"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"

APP="build/PixelShift.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
cp "$BIN/PixelShift" "$APP/Contents/MacOS/PixelShift"

# Sparkle (self-updates). Its helpers are re-signed with our identity, innermost
# first, as Sparkle's sandboxing guide describes.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign -f -s "$SIGN" -o runtime --timestamp=none "$SPK/XPCServices/Installer.xpc"
codesign -f -s "$SIGN" -o runtime --timestamp=none --preserve-metadata=entitlements "$SPK/XPCServices/Downloader.xpc"
codesign -f -s "$SIGN" -o runtime --timestamp=none "$SPK/Autoupdate"
codesign -f -s "$SIGN" -o runtime --timestamp=none "$SPK/Updater.app"
codesign -f -s "$SIGN" -o runtime --timestamp=none "$APP/Contents/Frameworks/Sparkle.framework"

# Icon/AppIcon.icon is an Icon Composer (Liquid Glass) icon. actool compiles it
# into Assets.car (layered, rendered live by macOS 26+) plus AppIcon.icns for older systems.
xcrun actool "$PWD/Icon/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --target-device mac \
    --app-icon AppIcon --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null

# Privacy manifest (required by App Store review): no tracking, no data collected.
cp Support/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
# License texts travel with the app (MIT requires the notices in copies).
cp LICENSE THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PixelShift</string>
    <key>CFBundleDisplayName</key><string>PixelShift</string>
    <key>CFBundleExecutable</key><string>PixelShift</string>
    <key>CFBundleIdentifier</key><string>com.riviantrackr.pixelshift</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>$(cat Support/sparkle-public-key.txt)</string>
    <key>SUEnableInstallerLauncherService</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
    <key>NSHumanReadableCopyright</key><string>Shift pixels, reshape possibilities.</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Resize with PixelShift</string></dict>
            <key>NSMessage</key><string>resizeWithPixelShift</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.image</string><string>public.folder</string></array>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Image</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.image</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Folder</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.folder</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature with the sandbox entitlements and hardened runtime. For copies
# you hand out, set SIGN_IDENTITY to your "Developer ID Application" identity.
ENTITLEMENTS=Support/PixelShift.entitlements
if [[ "$SIGN" == "-" ]]; then
    # Ad-hoc signatures have no Team ID, so the hardened runtime would refuse to
    # load Sparkle.framework. Allow it for local builds only; Developer ID builds
    # share one Team ID and keep library validation on.
    ENTITLEMENTS=build/adhoc.entitlements
    cp Support/PixelShift.entitlements "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
fi
codesign --force --sign "$SIGN" --options runtime \
    --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
echo "Built $APP ($VERSION, build $BUILD)"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/PixelShift.app
    cp -R "$APP" /Applications/PixelShift.app
    # Register the app and refresh the Services list so Finder's right-click item appears.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/PixelShift.app
    /System/Library/CoreServices/pbs -update
    echo "Installed /Applications/PixelShift.app"
fi
