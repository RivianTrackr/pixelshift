# PixelShift

*Shift pixels, reshape possibilities.*

A native Mac replacement for Resize Master 1.3 (Intel-only, 2015).
Drop images or folders on the window or the Dock icon, choose a destination
folder, and every image is resized with the settings in the window.

## What it does

- **Files:** save to a chosen folder (keeps folder structure, copies non-image files) or next to the originals; optional name suffix (photo.jpg → photo-1200.jpg, required beside originals); asks before replacing (Replace / Skip / Apply to all). Beside originals, the sandbox asks once per folder and remembers it.
- **Resize:** do not resize, by percent, by width, by height, fit to rectangle, crop to aspect ratio, crop then fit; scale down only.
- **Metadata:** remove all, keep all, or keep all except location (drops GPS and IPTC place fields), add artist and copyright, set DPI. Photos are always saved upright (EXIF rotation applied).
- **Watermark:** any image, nine positions plus stretch, pixel offsets inward from the edge.
- **Output:** JPEG, PNG, TIFF, HEIC; original, sRGB, Display P3 or Adobe RGB; quality; fill color for transparent areas.
- **Presets:** named sets of settings in the window and the Presets menu (⌘1–⌘9); shows "(edited)" when settings drift from the chosen preset. Starts with "Web, 1200 tall" and "Square 1080".
- **Finder:** right-click images or folders → Quick Actions (or Services) → Resize with PixelShift, using the current settings.
- **Updates:** PixelShift → Check for Updates…, plus automatic checks (asked on second launch), via [Sparkle](https://sparkle-project.org).
- Runs files in parallel, keeps the Mac awake while working, notifies when done (click opens the folder).

Defaults match the Resize Master settings in use when it was replaced:
scale by height to 1200 px, scale down only, JPEG at 70%, copy non-image files.

## Build

Requires Xcode (the Command Line Tools alone lack SwiftUI's macros).

```bash
swift test                      # engine tests
scripts/build-app.sh            # build/PixelShift.app (universal, sandboxed)
scripts/build-app.sh --install  # also copy to /Applications
```

Layout: `Sources/ResizeCore` is the resizing engine (ImageIO + Core Graphics, no UI),
`Sources/PixelShift` is the SwiftUI app, `Icon/AppIcon.icon` is the Liquid Glass icon (open it in Icon Composer to edit), `scripts/` builds the bundle.

## Releasing an update

Copies downloaded from the web update themselves with Sparkle. Installed copies read
`https://riviantrackr.com/pixelshift/appcast.xml` (override with `FEED_URL=` when building).

1. Put the new version in `VERSION` (for example `1.1`) and commit. The build number is the commit count, so it always goes up.
2. Optional: write release notes to `release/PixelShift-1.1.md`; they show in the update window.
3. Run `scripts/release.sh`. It builds, zips to `release/PixelShift-1.1.zip`, and adds a signed entry to `release/appcast.xml`.
4. Upload `appcast.xml` and the zip to the folder the feed URL points at. Keep `release/` between releases; it holds the feed history.

Updates are signed with an EdDSA key kept in the login keychain (item "Private key for signing Sparkle updates",
account `com.riviantrackr.pixelshift`); its public half is `Support/sparkle-public-key.txt`. Back up the private key
(`.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.riviantrackr.pixelshift -x key.txt`): without it,
installed copies can't be updated.

For copies other people download, sign with a Developer ID and notarize, or macOS blocks the first launch:
`SIGN_IDENTITY="Developer ID Application: …" scripts/release.sh`, then `xcrun notarytool submit` the zip and
`xcrun stapler staple` the app before zipping. Ad-hoc builds turn off library validation so Sparkle loads;
Developer ID builds keep it on.

## App Store readiness

Done: App Sandbox (`Support/PixelShift.entitlements`: user-selected files, app-scoped bookmarks for the watermark),
privacy manifest (`Support/PrivacyInfo.xcprivacy`: no tracking, no data collected, UserDefaults reason CA92.1),
universal binary (arm64 + x86_64, macOS 14+), `ITSAppUsesNonExemptEncryption = NO`. Bundle ID `com.riviantrackr.pixelshift`.

The App Store build must leave out Sparkle (the store does its own updates and rejects its sandbox exceptions).

Still needed: Apple Developer Program membership, an Xcode project for Archive/upload, an Apple Distribution
signing identity (`SIGN_IDENTITY`), and the App Store Connect listing (screenshots, privacy policy and support URLs).
