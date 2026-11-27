#!/bin/bash
# Builds a release and publishes it on GitHub Releases, where installed copies look for updates.
# Usage: scripts/release.sh [--no-publish]
#   1. Set the new version in ./VERSION and commit.
#   2. Optional: write release notes to ReleaseNotes/<version>.md (shown in the update window).
#   3. Run this. --no-publish builds and signs everything in release/<version>/ but uploads nothing.
# Signs the archive with the EdDSA key in your login keychain (made once by generate_keys).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="RivianTrackr/pixelshift"
VERSION="$(cat VERSION)"
TAG="v$VERSION"
PUBLISH=1
[[ "${1:-}" == "--no-publish" ]] && PUBLISH=0

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit your changes first, so the build number matches a commit." >&2
    exit 1
fi
if [[ $PUBLISH == 1 ]] && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$TAG is already released. Bump ./VERSION for a new release." >&2
    exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scripts/build-app.sh

OUT="release/$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"
ZIP="$OUT/PixelShift-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent build/PixelShift.app "$ZIP"
NOTES="ReleaseNotes/$VERSION.md"
[[ -f "$NOTES" ]] && cp "$NOTES" "$OUT/PixelShift-$VERSION.md"

# A feed with just this version: Sparkle only needs the newest one. Installed copies read it
# from releases/latest/download/appcast.xml, which GitHub points at the newest release.
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --account com.riviantrackr.pixelshift \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO" \
    --embed-release-notes \
    "$OUT"

if [[ $PUBLISH == 0 ]]; then
    echo "Built $OUT (not published)."
    exit 0
fi

NOTES_ARGS=(--notes "PixelShift $VERSION")
[[ -f "$NOTES" ]] && NOTES_ARGS=(--notes-file "$NOTES")
gh release create "$TAG" --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "PixelShift $VERSION" "${NOTES_ARGS[@]}" "$ZIP" "$OUT/appcast.xml"
echo "Published $TAG: https://github.com/$REPO/releases/tag/$TAG"
