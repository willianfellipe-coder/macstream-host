#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Downloads and stages the upstream Sunshine.app inside Resources/sunshine/
# so package_dmg.sh can embed it into the MacStream Host bundle.
#
# Idempotent: skips download when the staged Sunshine.app matches the expected
# SHA-256 of the source DMG. Pinned to the upstream release recorded in
# UPSTREAMS.md.
#
# Usage:
#   ./scripts/fetch_sunshine.sh              # arm64 (default on Apple Silicon)
#   ARCH=x86_64 ./scripts/fetch_sunshine.sh  # Intel
#   FORCE=1 ./scripts/fetch_sunshine.sh      # re-download even if cached
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="$ROOT_DIR/Resources/sunshine"
CACHE_DIR="$ROOT_DIR/.build/sunshine-cache"
STATE_FILE="$RESOURCES_DIR/.fetched-sha256"

SUNSHINE_VERSION="v2026.508.45922"
RELEASE_TAG_URL="https://github.com/LizardByte/Sunshine/releases/tag/$SUNSHINE_VERSION"

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64|arm64e)
    DMG_NAME="Sunshine-macOS-arm64.dmg"
    EXPECTED_SHA256="8b9819f2dafcfa430b00cc08b07aa61d0ad138998d68f369bfc210e07db3eb4b"
    ;;
  x86_64)
    DMG_NAME="Sunshine-macOS-x86_64.dmg"
    EXPECTED_SHA256="8d1518ef938e42d04fd013057aabdf2945d6a6dd12f053943d4d47f68d17089d"
    ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 2
    ;;
esac

DOWNLOAD_URL="https://github.com/LizardByte/Sunshine/releases/download/$SUNSHINE_VERSION/$DMG_NAME"
DMG_PATH="$CACHE_DIR/$DMG_NAME"
MOUNT_POINT="$CACHE_DIR/mount"

staged_executable=""
for candidate in \
  "$RESOURCES_DIR/Sunshine.app/Contents/MacOS/Sunshine" \
  "$RESOURCES_DIR/Sunshine.app/Contents/MacOS/sunshine"; do
  if [[ -x "$candidate" ]]; then
    staged_executable="$candidate"
    break
  fi
done

if [[ "${FORCE:-0}" != "1" && -f "$STATE_FILE" && -n "$staged_executable" ]]; then
  if [[ "$(cat "$STATE_FILE")" == "$EXPECTED_SHA256" ]]; then
    echo "Sunshine.app already staged for $SUNSHINE_VERSION ($ARCH). Use FORCE=1 to re-fetch."
    exit 0
  fi
fi

mkdir -p "$CACHE_DIR" "$RESOURCES_DIR"

if [[ ! -f "$DMG_PATH" ]] || [[ "$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')" != "$EXPECTED_SHA256" ]]; then
  echo "Downloading Sunshine $SUNSHINE_VERSION ($ARCH)..."
  curl --fail --location --progress-bar --output "$DMG_PATH" "$DOWNLOAD_URL"
fi

ACTUAL_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "SHA-256 mismatch for $DMG_NAME" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  echo "  source:   $RELEASE_TAG_URL" >&2
  exit 3
fi

if mount | grep -q " on $MOUNT_POINT "; then
  hdiutil detach "$MOUNT_POINT" -quiet || true
fi
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

trap 'hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true' EXIT

echo "Mounting $DMG_NAME..."
# The upstream DMG includes a GPL software license agreement. Pipe `yes` so
# hdiutil silently accepts before mounting; the agreement text is preserved at
# https://www.gnu.org/licenses/gpl-3.0.html.
/usr/bin/yes | /usr/bin/hdiutil attach "$DMG_PATH" \
  -mountpoint "$MOUNT_POINT" \
  -nobrowse -noverify -noautoopen \
  > /dev/null

SOURCE_APP="$(/usr/bin/find "$MOUNT_POINT" -maxdepth 3 -type d -name "Sunshine.app" -print -quit)"
if [[ -z "$SOURCE_APP" ]]; then
  echo "Sunshine.app not found inside $DMG_NAME" >&2
  exit 4
fi

echo "Staging Sunshine.app into Resources/sunshine/..."
rm -rf "$RESOURCES_DIR/Sunshine.app"
/usr/bin/ditto "$SOURCE_APP" "$RESOURCES_DIR/Sunshine.app"

# macOS Tahoe (26+) refuses to grant Screen Recording to apps whose code-signing
# identity differs from the responsible parent's. The upstream Sunshine.app is
# signed with LizardByte's Developer ID (dev.lizardbyte.app.Sunshine), but our
# MacStream Host parent is ad-hoc signed (no Developer ID yet) — Tahoe sees
# them as unrelated identities and silently refuses to add the embedded
# Sunshine to "Gravação do Áudio do Sistema e da Tela", which means the
# encoder probe can never get a captured frame.
#
# Re-bundle Sunshine under our identity:
#   - rewrite CFBundleIdentifier to a sub-namespace of org.macstream.host
#   - rewrite CFBundleName so the System Settings entry reads "MacStream Video Engine"
#   - strip the LizardByte signature so package_dmg.sh can re-sign the bundle
#     ad-hoc with the same identity as MacStream Host.app
PATCHED_PLIST="$RESOURCES_DIR/Sunshine.app/Contents/Info.plist"
if [[ -f "$PATCHED_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier org.macstream.host.engine.sunshine" "$PATCHED_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string org.macstream.host.engine.sunshine" "$PATCHED_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName 'MacStream Video Engine'" "$PATCHED_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleName string 'MacStream Video Engine'" "$PATCHED_PLIST"
  # Add usage descriptions so newer macOS will accept the app for TCC.
  for key in NSCameraUsageDescription NSMicrophoneUsageDescription; do
    if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PATCHED_PLIST" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Add :$key string 'MacStream Video Engine needs this permission to stream the desktop.'" "$PATCHED_PLIST" || true
    fi
  done
fi

# Drop the upstream Developer ID signature; the wrapper package_dmg.sh will
# re-sign Sunshine.app and every nested framework ad-hoc with our entitlements.
if /usr/bin/codesign --verify "$RESOURCES_DIR/Sunshine.app" >/dev/null 2>&1; then
  echo "Removing upstream Developer ID signature so the bundle can be re-signed..."
  /usr/bin/codesign --remove-signature "$RESOURCES_DIR/Sunshine.app" 2>/dev/null || true
  # Also strip nested frameworks/dylibs so the wrapper can re-seal them.
  /usr/bin/find "$RESOURCES_DIR/Sunshine.app/Contents/Frameworks" \
    \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null \
    | xargs -0 -I {} /usr/bin/codesign --remove-signature {} 2>/dev/null || true
fi

LICENSE_PATH=""
for candidate in \
  "$SOURCE_APP/Contents/Resources/LICENSE" \
  "$SOURCE_APP/Contents/Resources/LICENSE.txt" \
  "$MOUNT_POINT/LICENSE" \
  "$MOUNT_POINT/LICENSE.txt"; do
  if [[ -f "$candidate" ]]; then
    LICENSE_PATH="$candidate"
    break
  fi
done
if [[ -n "$LICENSE_PATH" ]]; then
  cp "$LICENSE_PATH" "$RESOURCES_DIR/LICENSE"
fi

echo "$EXPECTED_SHA256" > "$STATE_FILE"

cat > "$RESOURCES_DIR/README.md" <<EOF
# Sunshine staging

Staged by \`scripts/fetch_sunshine.sh\` for embedding in the MacStream Host
application bundle. This directory is git-ignored and is recreated whenever
the script runs.

- Upstream: $RELEASE_TAG_URL
- Version: $SUNSHINE_VERSION
- Architecture: $ARCH
- DMG SHA-256: $EXPECTED_SHA256
- License: GPL-3.0 (see \`LICENSE\` in this directory and \`THIRD_PARTY_NOTICES.md\`)
EOF

echo "Done. Sunshine.app is staged at $RESOURCES_DIR/Sunshine.app"
