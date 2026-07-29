#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="UsageBar"
VERSION="${1:?Usage: scripts/package_release.sh <version> [build-number]}"
BUILD_NUMBER="${2:-1}"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to a Developer ID Application signing identity.}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a notarytool Keychain profile.}"
APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
NOTARIZATION_ZIP="$ROOT_DIR/.build/$APP_NAME-notarization.zip"
RELEASE_ZIP="$ROOT_DIR/.build/$APP_NAME-$VERSION.zip"
CHECKSUM_FILE="$RELEASE_ZIP.sha256"

SIGNING_IDENTITY="$SIGNING_IDENTITY" \
APP_VERSION="$VERSION" \
APP_BUILD="$BUILD_NUMBER" \
"$ROOT_DIR/scripts/package_app.sh"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$NOTARIZATION_ZIP" "$RELEASE_ZIP" "$CHECKSUM_FILE"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARIZATION_ZIP"

xcrun notarytool submit "$NOTARIZATION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$RELEASE_ZIP"
shasum -a 256 "$RELEASE_ZIP" > "$CHECKSUM_FILE"

echo "Release archive: $RELEASE_ZIP"
echo "Checksum: $CHECKSUM_FILE"
