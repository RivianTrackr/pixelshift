#!/bin/bash
# Builds PixelShift.app (universal: Apple Silicon + Intel, sandboxed) into ./build.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="1.0"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"

APP="build/PixelShift.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/PixelShift" "$APP/Contents/MacOS/PixelShift"

# Icon/AppIcon.icon is an Icon Composer (Liquid Glass) icon. actool compiles it
# into Assets.car (layered, rendered live by macOS 26+) plus AppIcon.icns for older systems.
xcrun actool "$PWD/Icon/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --target-device mac \
    --app-icon AppIcon --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null

# Privacy manifest (required by App Store review): no tracking, no data collected.
cp Support/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"

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
    <key>CFBundleVersion</key><string>${VERSION}</string>
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

# Ad-hoc signature with the sandbox entitlements and hardened runtime. For the
# App Store this becomes an Apple Distribution identity (set SIGN_IDENTITY).
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime \
    --entitlements Support/PixelShift.entitlements --timestamp=none "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/PixelShift.app
    cp -R "$APP" /Applications/PixelShift.app
    # Register the app and refresh the Services list so Finder's right-click item appears.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/PixelShift.app
    /System/Library/CoreServices/pbs -update
    echo "Installed /Applications/PixelShift.app"
fi
