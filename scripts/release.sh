#!/bin/bash
# Builds a release and updates the Sparkle feed in ./release.
# Usage: scripts/release.sh
#   1. Set the new version in ./VERSION and commit.
#   2. Optional: write release notes to release/PixelShift-<version>.md
#   3. Run this, then upload everything in release/ to the folder SUFeedURL points at.
# Signs the archive with the EdDSA key in your login keychain (made once by generate_keys).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit your changes first, so the build number matches a commit." >&2
    exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
FEED_URL="${FEED_URL:-https://riviantrackr.com/pixelshift/appcast.xml}"
export FEED_URL
VERSION="$(cat VERSION)"

scripts/build-app.sh

mkdir -p release
ZIP="release/PixelShift-$VERSION.zip"
if [[ -e "$ZIP" ]]; then
    echo "$ZIP already exists. Bump ./VERSION for a new release." >&2
    exit 1
fi
ditto -c -k --sequesterRsrc --keepParent build/PixelShift.app "$ZIP"

# Adds this version to release/appcast.xml (keeping earlier entries) and signs it.
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --account com.riviantrackr.pixelshift \
    --download-url-prefix "${FEED_URL%/*}/" \
    --embed-release-notes \
    release

echo "Release $VERSION is ready in release/. Upload appcast.xml and $(basename "$ZIP") to ${FEED_URL%/*}/"
