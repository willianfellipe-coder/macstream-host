#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
PRODUCT_NAME="MacStreamHostApp"
APP_NAME="MacStream Host"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
PACKAGE_DIR="$ROOT_DIR/.build/package"
APP_DIR="$PACKAGE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_STAGING_DIR="$PACKAGE_DIR/dmg-staging"
SUNSHINE_STAGE_DIR="$ROOT_DIR/Resources/sunshine"
SUNSHINE_STAGE_APP="$SUNSHINE_STAGE_DIR/Sunshine.app"
SUNSHINE_BUNDLE_DEST="$RESOURCES_DIR/sunshine"
SWIFTPM_CACHE_DIR="$PACKAGE_DIR/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$PACKAGE_DIR/swiftpm-config"
SWIFTPM_SECURITY_DIR="$PACKAGE_DIR/swiftpm-security"
XDG_CACHE_DIR="$PACKAGE_DIR/xdg-cache"
CLANG_MODULE_CACHE_DIR="$PACKAGE_DIR/clang-module-cache"

echo "Building $PRODUCT_NAME $VERSION ($CONFIGURATION)"

if [[ ! -x "$SUNSHINE_STAGE_APP/Contents/MacOS/sunshine" ]]; then
  echo "Sunshine.app is not staged at $SUNSHINE_STAGE_APP" >&2
  echo "Run ./scripts/fetch_sunshine.sh first (downloads pinned upstream DMG, verifies SHA-256)." >&2
  exit 5
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "Dry run only."
  echo "App bundle: $APP_DIR"
  echo "DMG staging: $DMG_STAGING_DIR"
  echo "Bundle identifier: org.macstream.host"
  echo "Sunshine staging: $SUNSHINE_STAGE_APP"
  echo "Sunshine bundle destination: $SUNSHINE_BUNDLE_DEST/Sunshine.app"
  echo "Create DMG: ${CREATE_DMG:-0}"
  exit 0
fi

mkdir -p "$SWIFTPM_CACHE_DIR" "$SWIFTPM_CONFIG_DIR" "$SWIFTPM_SECURITY_DIR" "$XDG_CACHE_DIR" "$CLANG_MODULE_CACHE_DIR"
export XDG_CACHE_HOME="$XDG_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_DIR"
export MACSTREAM_GIT_COMMIT="$GIT_COMMIT"
SWIFT_BUILD_ARGS=(
  --disable-sandbox
  --cache-path "$SWIFTPM_CACHE_DIR"
  --config-path "$SWIFTPM_CONFIG_DIR"
  --security-path "$SWIFTPM_SECURITY_DIR"
  --manifest-cache local
  -c "$CONFIGURATION"
)
swift build "${SWIFT_BUILD_ARGS[@]}" --product "$PRODUCT_NAME"
swift build "${SWIFT_BUILD_ARGS[@]}" --product macstreamctl
swift build "${SWIFT_BUILD_ARGS[@]}" --product macstream-agent

BINARY_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BINARY_PATH="$BINARY_DIR/$PRODUCT_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Missing built binary at $BINARY_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"

if [[ -x "$BINARY_DIR/macstreamctl" ]]; then
  cp "$BINARY_DIR/macstreamctl" "$MACOS_DIR/macstreamctl"
fi

if [[ -x "$BINARY_DIR/macstream-agent" ]]; then
  cp "$BINARY_DIR/macstream-agent" "$MACOS_DIR/macstream-agent"
fi

cp "$ROOT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
cp "$ROOT_DIR/UPSTREAMS.md" "$RESOURCES_DIR/UPSTREAMS.md"

rm -rf "$SUNSHINE_BUNDLE_DEST"
mkdir -p "$SUNSHINE_BUNDLE_DEST"
/usr/bin/ditto "$SUNSHINE_STAGE_APP" "$SUNSHINE_BUNDLE_DEST/Sunshine.app"
for sunshine_note in "$SUNSHINE_STAGE_DIR/LICENSE" "$SUNSHINE_STAGE_DIR/README.md"; do
  if [[ -f "$sunshine_note" ]]; then
    cp "$sunshine_note" "$SUNSHINE_BUNDLE_DEST/$(basename "$sunshine_note")"
  fi
done

ICON_PATH="$RESOURCES_DIR/AppIcon.icns"
if [[ -f "$ROOT_DIR/packaging/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/packaging/AppIcon.icns" "$ICON_PATH"
else
  ICON_WORK_DIR="$PACKAGE_DIR/icon-work"
  rm -rf "$ICON_WORK_DIR"
  mkdir -p "$ICON_WORK_DIR"
  cat > "$ICON_WORK_DIR/icon.swift" <<'SWIFT'
import AppKit
import Foundation

let pngOutputPath = CommandLine.arguments[1]
let icnsOutputPath = CommandLine.arguments[2]
let side = 1024.0
let rect = NSRect(x: 0, y: 0, width: side, height: side)
let image = NSImage(size: rect.size)

image.lockFocus()
NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.20, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220).fill()

NSColor(calibratedRed: 0.02, green: 0.82, blue: 0.76, alpha: 1).setStroke()
let wave = NSBezierPath()
wave.lineWidth = 58
wave.move(to: NSPoint(x: 190, y: 500))
wave.curve(
    to: NSPoint(x: 835, y: 525),
    controlPoint1: NSPoint(x: 345, y: 745),
    controlPoint2: NSPoint(x: 660, y: 300)
)
wave.stroke()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 250, weight: .bold),
    .foregroundColor: NSColor.white
]
let text = "MS" as NSString
let textSize = text.size(withAttributes: attrs)
text.draw(
    at: NSPoint(x: (side - textSize.width) / 2, y: 360),
    withAttributes: attrs
)
image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let data = rep.representation(using: .png, properties: [:])
else {
    Foundation.exit(1)
}

func fourCC(_ value: String) -> Data {
    Data(value.utf8)
}

func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: 4)
}

try data.write(to: URL(fileURLWithPath: pngOutputPath), options: .atomic)

var iconData = Data()
let totalLength = UInt32(8 + 8 + data.count)
iconData.append(fourCC("icns"))
iconData.append(bigEndian(totalLength))
iconData.append(fourCC("ic10"))
iconData.append(bigEndian(UInt32(8 + data.count)))
iconData.append(data)
try iconData.write(to: URL(fileURLWithPath: icnsOutputPath), options: .atomic)
SWIFT
  /usr/bin/swift "$ICON_WORK_DIR/icon.swift" "$ICON_WORK_DIR/base.png" "$ICON_PATH"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacStream Host</string>
  <key>CFBundleIdentifier</key>
  <string>org.macstream.host</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>MacStream Host</string>
  <key>CFBundleDisplayName</key>
  <string>MacStream Host</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.2</string>
  <key>NSHumanReadableCopyright</key>
  <string>GPL-3.0-or-later. Sunshine, BlackHole and Moonlight are independent upstream projects.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>MacStream Host validates audio capture routes for Sunshine streaming.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>MacStream Host validates local Moonlight pairing and Sunshine connectivity.</string>
</dict>
</plist>
PLIST

cat > "$RESOURCES_DIR/build-info.json" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD_NUMBER",
  "commit": "$GIT_COMMIT",
  "buildDate": "$BUILD_DATE",
  "bundleIdentifier": "org.macstream.host"
}
JSON

echo "Created app bundle: $APP_DIR"

# Ad-hoc sign the bundle when a Developer ID is not provided. macOS TCC keys
# Screen Recording grants on the code signature; without any signature, every
# rebuild invalidates the embedded Sunshine grant and the user has to re-allow
# the toggle from scratch. Ad-hoc signing gives the bundle a stable cdhash so
# TCC has something coherent to track, and is replaced by the proper Developer
# ID signature in sign_and_notarize.sh when releasing.
if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "Applying ad-hoc code signature (no DEVELOPER_ID_APPLICATION set)..."
  /usr/bin/codesign --force --deep --sign - \
    --options runtime \
    --entitlements "$ROOT_DIR/packaging/entitlements.plist" \
    "$APP_DIR" >/dev/null
fi

if [[ "${CREATE_DMG:-0}" == "1" ]]; then
  DMG_PATH="$PACKAGE_DIR/$APP_NAME.dmg"
  CHECKSUM_PATH="$DMG_PATH.sha256"
  rm -f "$DMG_PATH"
  rm -rf "$DMG_STAGING_DIR"
  mkdir -p "$DMG_STAGING_DIR"
  /usr/bin/ditto "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
  cp "$ROOT_DIR/LICENSE" "$DMG_STAGING_DIR/LICENSE"
  cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$DMG_STAGING_DIR/THIRD_PARTY_NOTICES.md"
  cp "$ROOT_DIR/UPSTREAMS.md" "$DMG_STAGING_DIR/UPSTREAMS.md"
  hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO "$DMG_PATH"
  shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"
  echo "Created unsigned development DMG: $DMG_PATH"
  echo "Created checksum: $CHECKSUM_PATH"
else
  echo "Set CREATE_DMG=1 to also create an unsigned development DMG."
fi
