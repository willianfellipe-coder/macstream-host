#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/.build/package/MacStream Host.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/.build/package/MacStream Host.dmg}"
ENTITLEMENTS="$ROOT_DIR/packaging/entitlements.plist"
SUNSHINE_APP="$APP_PATH/Contents/Resources/sunshine/Sunshine.app"

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

if [[ ! -d "$SUNSHINE_APP" ]]; then
  echo "Missing embedded Sunshine.app at $SUNSHINE_APP. Run ./scripts/fetch_sunshine.sh then ./scripts/package_dmg.sh." >&2
  exit 1
fi

sign_target() {
  local target="$1"
  local options="${2:---options runtime}"
  echo "Signing: $target"
  codesign --force --timestamp $options --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID_APPLICATION" "$target"
}

echo "Re-signing nested Sunshine.app contents..."
# Sign embedded dylibs/frameworks inside Sunshine.app first so codesign can
# stitch a valid seal on the wrapper.
while IFS= read -r -d '' nested; do
  sign_target "$nested"
done < <(/usr/bin/find "$SUNSHINE_APP/Contents" \
  \( -name "*.dylib" -o -name "*.framework" -o -path "*/MacOS/*" -type f -perm +111 \) \
  -print0)

# Sign Sunshine.app wrapper.
sign_target "$SUNSHINE_APP"

echo "Signing helper binaries..."
for helper in "macstreamctl" "macstream-agent"; do
  if [[ -x "$APP_PATH/Contents/MacOS/$helper" ]]; then
    sign_target "$APP_PATH/Contents/MacOS/$helper"
  fi
done

echo "Signing app: $APP_PATH"
sign_target "$APP_PATH"
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
