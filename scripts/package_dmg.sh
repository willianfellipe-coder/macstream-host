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
SUNSHINE_STAGE_APP="$SUNSHINE_STAGE_DIR/Sunshine.app"
SUNSHINE_STAGE_BIN="$SUNSHINE_STAGE_DIR/bin/MacStreamEngine"
SUNSHINE_STAGE_FRAMEWORKS="$SUNSHINE_STAGE_DIR/Frameworks"
SUNSHINE_STAGE_ASSETS="$SUNSHINE_STAGE_DIR/assets"
SUNSHINE_BUNDLE_DEST="$RESOURCES_DIR/sunshine"
SWIFTPM_CACHE_DIR="$PACKAGE_DIR/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$PACKAGE_DIR/swiftpm-config"
SWIFTPM_SECURITY_DIR="$PACKAGE_DIR/swiftpm-security"
XDG_CACHE_DIR="$PACKAGE_DIR/xdg-cache"
CLANG_MODULE_CACHE_DIR="$PACKAGE_DIR/clang-module-cache"

echo "Building $PRODUCT_NAME $VERSION ($CONFIGURATION)"

if [[ ! -d "$SUNSHINE_STAGE_APP" && ! -x "$SUNSHINE_STAGE_BIN" ]]; then
  echo "Sunshine is not staged under $SUNSHINE_STAGE_DIR" >&2
  echo "Run ./scripts/fetch_sunshine.sh first (downloads pinned upstream DMG, verifies SHA-256)." >&2
  exit 5
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "Dry run only."
  echo "App bundle: $APP_DIR"
  echo "DMG staging: $DMG_STAGING_DIR"
  echo "Bundle identifier: org.macstream.host"
  echo "Sunshine app staging: $SUNSHINE_STAGE_APP"
  echo "Flat engine fallback staging: $SUNSHINE_STAGE_BIN"
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

# Sunshine must remain a real `.app` bundle on macOS. Flattening the binary
# into Contents/MacOS made the process pass some TCC checks but hang forever
# in Sunshine's AVFoundation dummy-frame probe before opening HTTP/RTSP
# sockets. The app wrapper gives LaunchServices and AVFoundation the bundle
# context they expect, while LSUIElement keeps it out of the Dock.
rm -rf "$SUNSHINE_BUNDLE_DEST"
mkdir -p "$SUNSHINE_BUNDLE_DEST"
if [[ -d "$SUNSHINE_STAGE_APP" ]]; then
  /usr/bin/ditto "$SUNSHINE_STAGE_APP" "$SUNSHINE_BUNDLE_DEST/Sunshine.app"
else
  SYNTH_APP="$SUNSHINE_BUNDLE_DEST/Sunshine.app"
  mkdir -p "$SYNTH_APP/Contents/MacOS" "$SYNTH_APP/Contents/Frameworks" "$SYNTH_APP/Contents/Resources"
  /usr/bin/ditto "$SUNSHINE_STAGE_BIN" "$SYNTH_APP/Contents/MacOS/Sunshine"
  chmod 755 "$SYNTH_APP/Contents/MacOS/Sunshine"
  if [[ -d "$SUNSHINE_STAGE_FRAMEWORKS" ]]; then
    /usr/bin/ditto "$SUNSHINE_STAGE_FRAMEWORKS" "$SYNTH_APP/Contents/Frameworks"
  fi
  if [[ -d "$SUNSHINE_STAGE_ASSETS" ]]; then
    /usr/bin/ditto "$SUNSHINE_STAGE_ASSETS" "$SYNTH_APP/Contents/Resources/assets"
  fi
  cat > "$SYNTH_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Sunshine</string>
  <key>CFBundleIdentifier</key>
  <string>org.macstream.host.engine.sunshine</string>
  <key>CFBundleName</key>
  <string>MacStream Video Engine</string>
  <key>CFBundleDisplayName</key>
  <string>MacStream Video Engine</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.2</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>MacStream Video Engine precisa capturar a tela para transmitir ao Moonlight.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>MacStream Video Engine precisa do microfone para transmitir audio ao Moonlight.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>MacStream Video Engine precisa capturar o audio do sistema para transmitir ao Moonlight.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>MacStream Video Engine aceita conexoes Moonlight na rede local.</string>
</dict>
</plist>
PLIST
fi

for sunshine_note in "$SUNSHINE_STAGE_DIR/LICENSE" "$SUNSHINE_STAGE_DIR/README.md"; do
  if [[ -f "$sunshine_note" ]]; then
    cp "$sunshine_note" "$SUNSHINE_BUNDLE_DEST/$(/usr/bin/basename "$sunshine_note")"
  fi
done

# Sunshine v2026.516+ captures system audio via the macOS Tap API on
# macOS 14.2+, so we no longer bundle BlackHole. Users who want a
# Multi-Output Device setup can still install the upstream driver from
# https://github.com/ExistentialAudio/BlackHole separately.

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
#   1. Sunshine.app nested frameworks/dylibs first
#   2. Sunshine.app wrapper
#   3. Sibling helper executables (macstreamctl, macstream-agent)
#   4. The parent MacStream Host.app last
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
  # Try to provision (or reuse) the local self-signed identity that survives
  # rebuilds. Without it, codesign falls back to ad-hoc, the cdhash changes
  # on every build, and macOS TCC invalidates every Screen Recording /
  # Accessibility grant. The script is idempotent — it just emits the name
  # of an identity that already exists when re-run.
  if SIGN_IDENTITY=$("$ROOT_DIR/scripts/setup_local_codesign_identity.sh" 2>/dev/null \
       | tail -n 1); then
    if [[ -z "$SIGN_IDENTITY" ]]; then
      SIGN_IDENTITY="-"
    fi
  else
    SIGN_IDENTITY="-"
  fi
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "WARNING: signing ad-hoc ('-'). Screen Recording grants may be invalidated on each rebuild." >&2
    echo "         Set CODESIGN_IDENTITY (local) or DEVELOPER_ID_APPLICATION (production) for stable cdhash." >&2
  else
    echo "Using local self-signed identity for stable TCC: $SIGN_IDENTITY"
  fi
fi

echo "Signing with identity: $SIGN_IDENTITY"

EMBEDDED_SUNSHINE_APP="$SUNSHINE_BUNDLE_DEST/Sunshine.app"
if [[ -d "$EMBEDDED_SUNSHINE_APP/Contents/Frameworks" ]]; then
  echo "Signing embedded Sunshine.app frameworks..."
  /usr/bin/find "$EMBEDDED_SUNSHINE_APP/Contents/Frameworks" -maxdepth 1 \
    \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null \
    | xargs -0 -I {} /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp=none {} || true
fi

if [[ -d "$EMBEDDED_SUNSHINE_APP" ]]; then
  echo "Signing embedded Sunshine.app wrapper..."
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    --entitlements "$ROOT_DIR/packaging/entitlements.plist" \
    "$EMBEDDED_SUNSHINE_APP" >/dev/null
fi

for helper in macstreamctl macstream-agent; do
  if [[ -x "$MACOS_DIR/$helper" ]]; then
    # Keep MacStream's own helper tools under the parent bundle identifier so
    # app, CLI and resident agent share one stable macOS permission subject.
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" \
      --identifier "org.macstream.host" \
      --options runtime \
      --entitlements "$ROOT_DIR/packaging/entitlements.plist" \
      "$MACOS_DIR/$helper" >/dev/null
  fi
done

echo "Signing parent MacStream Host.app..."
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
