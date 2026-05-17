#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Downloads the upstream Sunshine release and extracts the components MacStream
# Host needs into a flat staging directory:
#
#   Resources/sunshine/
#   ├── bin/MacStreamEngine          # renamed Sunshine binary
#   ├── Frameworks/{libssl,libcrypto,libminiupnpc}.dylib
#   └── assets/{apps.json,box.png,steam.png,desktop*.png,web/}
#
# package_dmg.sh later moves these into MacStream Host.app/Contents/{MacOS,
# Frameworks,Resources/assets} so the engine inherits the parent bundle's TCC
# identity. There is no embedded `.app` wrapper — having a nested bundle is
# exactly what made macOS 14+ treat Sunshine as a separate Screen Recording
# subject (and the disclaim API does not bypass that check).
#
# Idempotent: skips download when staged files match the expected SHA-256 of
# the source DMG. Pinned to the upstream release in UPSTREAMS.md.
#
# Usage:
#   ./scripts/fetch_sunshine.sh              # arm64 (default on Apple Silicon)
#   ARCH=x86_64 ./scripts/fetch_sunshine.sh  # Intel
#   FORCE=1 ./scripts/fetch_sunshine.sh      # re-download even if cached
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="$ROOT_DIR/Resources/sunshine"
CACHE_DIR="$ROOT_DIR/.build/sunshine-cache"
STATE_FILE="$STAGE_DIR/.fetched-sha256"

SUNSHINE_VERSION="v2026.516.143833"
RELEASE_TAG_URL="https://github.com/LizardByte/Sunshine/releases/tag/$SUNSHINE_VERSION"

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64|arm64e)
    DMG_NAME="Sunshine-macOS-arm64.dmg"
    EXPECTED_SHA256="ab31ad716117b913c6aab104268e820595c0baf89b319fd3b75d34c9ae8ddd1e"
    ;;
  x86_64)
    DMG_NAME="Sunshine-macOS-x86_64.dmg"
    EXPECTED_SHA256="6b17c8d5a20cb2d2fa7c3bb9387d1412e63bb5c964d6820af91dea12f31a665f"
    ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 2
    ;;
esac

DOWNLOAD_URL="https://github.com/LizardByte/Sunshine/releases/download/$SUNSHINE_VERSION/$DMG_NAME"
DMG_PATH="$CACHE_DIR/$DMG_NAME"
MOUNT_POINT="$CACHE_DIR/mount"

STAGED_BIN="$STAGE_DIR/bin/MacStreamEngine"

if [[ "${FORCE:-0}" != "1" && -f "$STATE_FILE" && -x "$STAGED_BIN" ]]; then
  if [[ "$(cat "$STATE_FILE")" == "$EXPECTED_SHA256" ]]; then
    echo "Sunshine staged for $SUNSHINE_VERSION ($ARCH). Use FORCE=1 to re-fetch."
    exit 0
  fi
fi

mkdir -p "$CACHE_DIR" "$STAGE_DIR"

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
# The upstream DMG includes a GPL software license agreement. Feed a bounded
# stream of "y" responses so hdiutil silently accepts before mounting; the
# agreement text is preserved at https://www.gnu.org/licenses/gpl-3.0.html.
# We use `printf` (bounded) instead of `yes` (infinite) because `yes` gets
# SIGPIPE when hdiutil closes its stdin, which trips `set -o pipefail` even
# though the mount succeeded.
printf 'y\n%.0s' {1..32} | /usr/bin/hdiutil attach "$DMG_PATH" \
  -mountpoint "$MOUNT_POINT" \
  -nobrowse -noverify -noautoopen \
  > /dev/null

SOURCE_APP="$(/usr/bin/find "$MOUNT_POINT" -maxdepth 3 -type d -name "Sunshine.app" -print -quit)"
if [[ -z "$SOURCE_APP" ]]; then
  echo "Sunshine.app not found inside $DMG_NAME" >&2
  exit 4
fi

# Resolve upstream component paths inside the mounted Sunshine.app
SRC_BIN=""
for candidate in \
  "$SOURCE_APP/Contents/MacOS/Sunshine" \
  "$SOURCE_APP/Contents/MacOS/sunshine"; do
  if [[ -x "$candidate" ]]; then
    SRC_BIN="$candidate"
    break
  fi
done
if [[ -z "$SRC_BIN" ]]; then
  echo "Sunshine binary not found inside the source .app" >&2
  exit 5
fi
SRC_FRAMEWORKS="$SOURCE_APP/Contents/Frameworks"
SRC_ASSETS="$SOURCE_APP/Contents/Resources/assets"

echo "Staging Sunshine into flat layout under Resources/sunshine/..."

# Wipe previous staging (including any old Sunshine.app wrapper from earlier builds)
rm -rf "$STAGE_DIR/Sunshine.app" \
       "$STAGE_DIR/bin" \
       "$STAGE_DIR/Frameworks" \
       "$STAGE_DIR/assets"

mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/Frameworks" "$STAGE_DIR/assets"

# 1. The binary (renamed)
/usr/bin/ditto "$SRC_BIN" "$STAGED_BIN"
chmod 755 "$STAGED_BIN"

# 2. Dynamic libraries the binary depends on via @executable_path/../Frameworks/
if [[ -d "$SRC_FRAMEWORKS" ]]; then
  shopt -s nullglob
  for src in "$SRC_FRAMEWORKS"/*.dylib "$SRC_FRAMEWORKS"/*.framework; do
    [[ -e "$src" ]] || continue
    /usr/bin/ditto "$src" "$STAGE_DIR/Frameworks/$(/usr/bin/basename "$src")"
  done
  shopt -u nullglob
fi

# 3. Assets (apps.json, icons, web UI). Sunshine resolves these via
#    `../Resources/assets/` relative to the binary, which after package_dmg.sh
#    becomes `MacStream Host.app/Contents/Resources/assets/`.
if [[ -d "$SRC_ASSETS" ]]; then
  /usr/bin/ditto "$SRC_ASSETS" "$STAGE_DIR/assets"
fi

# Strip upstream LizardByte signatures so package_dmg.sh can re-sign every
# component with the same identity as the parent MacStream Host.app. This is
# essential — when the helper binary shares the parent's code signature, macOS
# treats it as part of the parent bundle and a single Screen Recording grant
# covers both.
echo "Removing upstream signatures so the helper can be re-sealed..."
/usr/bin/codesign --remove-signature "$STAGED_BIN" 2>/dev/null || true
/usr/bin/find "$STAGE_DIR/Frameworks" \
  \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null \
  | xargs -0 -I {} /usr/bin/codesign --remove-signature {} 2>/dev/null || true

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
  cp "$LICENSE_PATH" "$STAGE_DIR/LICENSE"
fi

echo "$EXPECTED_SHA256" > "$STATE_FILE"

cat > "$STAGE_DIR/README.md" <<EOF
# Sunshine staging (flat layout)

Staged by \`scripts/fetch_sunshine.sh\` for embedding into MacStream Host's
main bundle as a helper executable (not a nested \`.app\`). Having a separate
\`.app\` bundle gives macOS a second TCC identity, which Screen Recording does
not let parent processes disclaim. By staging the binary, frameworks and
assets separately, \`package_dmg.sh\` can drop them into the parent bundle's
\`Contents/MacOS\`, \`Contents/Frameworks\` and \`Contents/Resources/assets\`
respectively — one identity, one permission grant.

- Upstream: $RELEASE_TAG_URL
- Version: $SUNSHINE_VERSION
- Architecture: $ARCH
- DMG SHA-256: $EXPECTED_SHA256
- License: GPL-3.0 (see \`LICENSE\` here and \`THIRD_PARTY_NOTICES.md\` at the repo root)
EOF

echo "Done."
echo "  binary    : $STAGED_BIN"
echo "  frameworks: $STAGE_DIR/Frameworks/"
echo "  assets    : $STAGE_DIR/assets/"
