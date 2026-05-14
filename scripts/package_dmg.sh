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
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_STAGING_DIR="$PACKAGE_DIR/dmg-staging"
SUNSHINE_STAGE_DIR="$ROOT_DIR/Resources/sunshine"
SUNSHINE_STAGE_BIN="$SUNSHINE_STAGE_DIR/bin/MacStreamEngine"
SUNSHINE_STAGE_FRAMEWORKS="$SUNSHINE_STAGE_DIR/Frameworks"
SUNSHINE_STAGE_ASSETS="$SUNSHINE_STAGE_DIR/assets"
ENGINE_BIN_NAME="MacStreamEngine"
SWIFTPM_CACHE_DIR="$PACKAGE_DIR/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$PACKAGE_DIR/swiftpm-config"
SWIFTPM_SECURITY_DIR="$PACKAGE_DIR/swiftpm-security"
XDG_CACHE_DIR="$PACKAGE_DIR/xdg-cache"
CLANG_MODULE_CACHE_DIR="$PACKAGE_DIR/clang-module-cache"

echo "Building $PRODUCT_NAME $VERSION ($CONFIGURATION)"

if [[ ! -x "$SUNSHINE_STAGE_BIN" ]]; then
  echo "Engine binary is not staged at $SUNSHINE_STAGE_BIN" >&2
  echo "Run ./scripts/fetch_sunshine.sh first (downloads pinned upstream DMG, verifies SHA-256, extracts flat layout)." >&2
  exit 5
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "Dry run only."
  echo "App bundle: $APP_DIR"
  echo "DMG staging: $DMG_STAGING_DIR"
  echo "Bundle identifier: org.macstream.host"
  echo "Engine binary staging: $SUNSHINE_STAGE_BIN"
  echo "Engine binary destination: $MACOS_DIR/$ENGINE_BIN_NAME"
  echo "Engine frameworks destination: $FRAMEWORKS_DIR/"
  echo "Engine assets destination: $RESOURCES_DIR/assets/"
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
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
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

# Engine binary becomes a sibling of MacStream Host inside Contents/MacOS so
# the OS attributes its TCC calls to the parent bundle identity. The binary
# uses @executable_path/../Frameworks/ and ../Resources/assets/ which resolve
# to Contents/Frameworks/ and Contents/Resources/assets/ from this location.
cp "$SUNSHINE_STAGE_BIN" "$MACOS_DIR/$ENGINE_BIN_NAME"
chmod 755 "$MACOS_DIR/$ENGINE_BIN_NAME"

if [[ -d "$SUNSHINE_STAGE_FRAMEWORKS" ]]; then
  shopt -s nullglob
  for src in "$SUNSHINE_STAGE_FRAMEWORKS"/*.dylib "$SUNSHINE_STAGE_FRAMEWORKS"/*.framework; do
    [[ -e "$src" ]] || continue
    /usr/bin/ditto "$src" "$FRAMEWORKS_DIR/$(/usr/bin/basename "$src")"
  done
  shopt -u nullglob
fi

if [[ -d "$SUNSHINE_STAGE_ASSETS" ]]; then
  rm -rf "$RESOURCES_DIR/assets"
  /usr/bin/ditto "$SUNSHINE_STAGE_ASSETS" "$RESOURCES_DIR/assets"
fi

if [[ -f "$SUNSHINE_STAGE_DIR/LICENSE" ]]; then
  cp "$SUNSHINE_STAGE_DIR/LICENSE" "$RESOURCES_DIR/LICENSE-engine"
fi

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
  <key>NSScreenCaptureUsageDescription</key>
  <string>MacStream precisa capturar a tela para transmitir ao Moonlight.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>MacStream precisa do microfone para transmitir áudio ao Moonlight.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>MacStream precisa capturar o áudio do sistema para transmitir ao Moonlight.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>MacStream descobre dispositivos Moonlight na rede local.</string>
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

# Sign the bundle. Order matters:
#   1. Embedded dylibs in Contents/Frameworks first (codesign --deep does NOT
#      descend into Frameworks reliably on every macOS version)
#   2. The helper engine binary in Contents/MacOS
#   3. Sibling helper executables (macstreamctl, macstream-agent)
#   4. The parent .app last — its signature now seals everything underneath
#
# Identity priority:
#   - DEVELOPER_ID_APPLICATION env var (Apple Developer ID) → production
#   - CODESIGN_IDENTITY env var → any valid local identity
#   - Otherwise: ad-hoc with a warning (Screen Recording grants survive ad-hoc
#     only when cdhash is stable, which it is for unchanged code; the user
#     gets a fresh prompt only when the binary actually changes).
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
elif [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$CODESIGN_IDENTITY"
else
  SIGN_IDENTITY="-"
  echo "WARNING: signing ad-hoc ('-'). Screen Recording grants may be invalidated on each rebuild." >&2
  echo "         Set CODESIGN_IDENTITY (local) or DEVELOPER_ID_APPLICATION (production) for stable cdhash." >&2
fi

echo "Signing with identity: $SIGN_IDENTITY"

if [[ -d "$FRAMEWORKS_DIR" ]]; then
  echo "Signing Contents/Frameworks/..."
  /usr/bin/find "$FRAMEWORKS_DIR" -maxdepth 1 \
    \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null \
    | xargs -0 -I {} /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp=none {} || true
fi

if [[ -x "$MACOS_DIR/$ENGINE_BIN_NAME" ]]; then
  # Use the parent bundle's identifier so TCC sees the helper as part of
  # MacStream Host instead of as a standalone Mach-O with its own ad-hoc
  # identity. Without --identifier, codesign falls back to `<basename>-<hash>`
  # which makes the helper a separate TCC subject.
  echo "Signing Contents/MacOS/$ENGINE_BIN_NAME (engine helper) as org.macstream.host..."
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" \
    --identifier "org.macstream.host" \
    --options runtime \
    --entitlements "$ROOT_DIR/packaging/entitlements.plist" \
    "$MACOS_DIR/$ENGINE_BIN_NAME" >/dev/null
fi

for helper in macstreamctl macstream-agent; do
  if [[ -x "$MACOS_DIR/$helper" ]]; then
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime "$MACOS_DIR/$helper" >/dev/null
  fi
done

echo "Signing parent MacStream Host.app (without --deep so helper identifier is preserved)..."
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" \
  --options runtime \
  --entitlements "$ROOT_DIR/packaging/entitlements.plist" \
  "$APP_DIR" >/dev/null

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
