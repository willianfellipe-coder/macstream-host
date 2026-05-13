#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
PRODUCT_NAME="MacStreamHostApp"
APP_NAME="MacStream Host"
PACKAGE_DIR="$ROOT_DIR/.build/package"
APP_DIR="$PACKAGE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SWIFTPM_CACHE_DIR="$PACKAGE_DIR/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$PACKAGE_DIR/swiftpm-config"
SWIFTPM_SECURITY_DIR="$PACKAGE_DIR/swiftpm-security"
XDG_CACHE_DIR="$PACKAGE_DIR/xdg-cache"
CLANG_MODULE_CACHE_DIR="$PACKAGE_DIR/clang-module-cache"

echo "Building $PRODUCT_NAME ($CONFIGURATION)"
mkdir -p "$SWIFTPM_CACHE_DIR" "$SWIFTPM_CONFIG_DIR" "$SWIFTPM_SECURITY_DIR" "$XDG_CACHE_DIR" "$CLANG_MODULE_CACHE_DIR"
export XDG_CACHE_HOME="$XDG_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_DIR"
SWIFT_BUILD_ARGS=(
  --disable-sandbox
  --cache-path "$SWIFTPM_CACHE_DIR"
  --config-path "$SWIFTPM_CONFIG_DIR"
  --security-path "$SWIFTPM_SECURITY_DIR"
  --manifest-cache local
  -c "$CONFIGURATION"
)
swift build "${SWIFT_BUILD_ARGS[@]}" --product "$PRODUCT_NAME"

BINARY_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BINARY_PATH="$BINARY_DIR/$PRODUCT_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Missing built binary at $BINARY_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacStream Host</string>
  <key>CFBundleIdentifier</key>
  <string>org.macstream.host</string>
  <key>CFBundleName</key>
  <string>MacStream Host</string>
  <key>CFBundleDisplayName</key>
  <string>MacStream Host</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.2</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Created app bundle: $APP_DIR"

if [[ "${CREATE_DMG:-0}" == "1" ]]; then
  DMG_PATH="$PACKAGE_DIR/$APP_NAME.dmg"
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
  echo "Created unsigned development DMG: $DMG_PATH"
else
  echo "Set CREATE_DMG=1 to also create an unsigned development DMG."
fi
