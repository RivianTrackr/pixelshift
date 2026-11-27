# Releasing PixelShift

Notes for maintainers. People who just want the app should use the [latest release](https://github.com/RivianTrackr/pixelshift/releases/latest).

## Publishing an update

Copies downloaded from the web update themselves with Sparkle from this repo's GitHub Releases.
Installed copies read `https://github.com/RivianTrackr/pixelshift/releases/latest/download/appcast.xml`,
which GitHub points at the newest release.

1. Put the new version in `VERSION` (for example `1.1`).
2. Optional: write release notes to `ReleaseNotes/1.1.md`; they show in the update window and on the release page.
3. Commit, then run `scripts/release.sh`. It builds, zips, signs the update, and creates release `v1.1`
   with `PixelShift-1.1.zip` and `appcast.xml` attached (needs `gh` signed in). The build number is the commit count, so it always goes up.

`scripts/release.sh --no-publish` does everything except the upload (output in `release/1.1/`).

Updates are signed with an EdDSA key kept in the login keychain (item "Private key for signing Sparkle updates",
account `com.riviantrackr.pixelshift`); its public half is `Support/sparkle-public-key.txt`. Back up the private key
(`.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.riviantrackr.pixelshift -x key.txt`): without it,
installed copies can't be updated.

For copies other people download, sign with a Developer ID and notarize, or macOS blocks the first launch:
`SIGN_IDENTITY="Developer ID Application: …"` (notarizing isn't in the script yet). Ad-hoc builds turn off library validation so Sparkle loads;
Developer ID builds keep it on.

## Mac App Store (not used yet)

Done: App Sandbox (`Support/PixelShift.entitlements`: user-selected files, app-scoped bookmarks for the watermark),
privacy manifest (`Support/PrivacyInfo.xcprivacy`: no tracking, no data collected, UserDefaults reason CA92.1),
universal binary (arm64 + x86_64, macOS 14+), `ITSAppUsesNonExemptEncryption = NO`. Bundle ID `com.riviantrackr.pixelshift`.

The App Store build must leave out Sparkle (the store does its own updates and rejects its sandbox exceptions).

Still needed: Apple Developer Program membership, an Xcode project for Archive/upload, an Apple Distribution
signing identity (`SIGN_IDENTITY`), and the App Store Connect listing (screenshots, privacy policy and support URLs).
