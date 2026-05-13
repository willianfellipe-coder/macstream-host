#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/.build/package/MacStream Host.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/.build/package/MacStream Host.dmg}"
ENTITLEMENTS="$ROOT_DIR/packaging/entitlements.plist"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "DEVELOPER_ID_APPLICATION is required, for example: Developer ID Application: Example, Inc. (TEAMID)" >&2
  exit 2
fi

if [[ -z "${NOTARYTOOL_PROFILE:-}" && ( -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ) ]]; then
  echo "Configure NOTARYTOOL_PROFILE or APPLE_ID, APPLE_TEAM_ID and APPLE_APP_SPECIFIC_PASSWORD before notarization." >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle at $APP_PATH. Run ./scripts/package_dmg.sh first." >&2
  exit 1
fi

echo "Signing app: $APP_PATH"
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
codesign --verify --strict --deep --verbose=2 "$APP_PATH"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG at $DMG_PATH. Run CREATE_DMG=1 ./scripts/package_dmg.sh first." >&2
  exit 1
fi

echo "Signing DMG: $DMG_PATH"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"

echo "Submitting for notarization"
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
else
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
fi

xcrun stapler staple "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "Signed, notarized and stapled: $DMG_PATH"
