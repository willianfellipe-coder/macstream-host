#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Downloads the official BlackHole 2ch installer .pkg and stages it under
# Resources/dependencies/ so package_dmg.sh can embed it into the MacStream
# Host bundle. With the .pkg embedded, the host app installs the audio
# driver via AuthorizationExecuteWithPrivileges (one admin prompt, no
# Installer.app window) instead of downloading and opening the installer
# at first-run.
#
# Idempotent: skips download when the staged .pkg already matches the
# expected SHA-256 below. Pinned to BlackHole 2ch 0.6.1 to match what
# DependencyInstallerManager.blackHoleArtifact() declares.
#
# Usage:
#   ./scripts/fetch_blackhole.sh
#   FORCE=1 ./scripts/fetch_blackhole.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="$ROOT_DIR/Resources/dependencies"
STATE_FILE="$STAGE_DIR/.blackhole-sha256"
CACHE_DIR="$ROOT_DIR/.build/blackhole-cache"

BLACKHOLE_VERSION="0.6.1"
PKG_NAME="BlackHole2ch-${BLACKHOLE_VERSION}.pkg"
STAGED_PKG="$STAGE_DIR/BlackHole2ch.pkg"
DOWNLOAD_URL="https://existential.audio/downloads/${PKG_NAME}"
EXPECTED_SHA256="c829afa041a9f6e1b369c01953c8f079740dd1f02421109855829edc0d3c1988"
SOURCE_URL="https://github.com/ExistentialAudio/BlackHole/releases/tag/v${BLACKHOLE_VERSION}"

if [[ "${FORCE:-0}" != "1" && -f "$STATE_FILE" && -f "$STAGED_PKG" ]]; then
  if [[ "$(cat "$STATE_FILE")" == "$EXPECTED_SHA256" ]]; then
    echo "BlackHole ${BLACKHOLE_VERSION} already staged at $STAGED_PKG. Use FORCE=1 to re-fetch."
    exit 0
  fi
fi

mkdir -p "$CACHE_DIR" "$STAGE_DIR"

CACHED_PKG="$CACHE_DIR/$PKG_NAME"
if [[ ! -f "$CACHED_PKG" ]] || [[ "$(shasum -a 256 "$CACHED_PKG" | awk '{print $1}')" != "$EXPECTED_SHA256" ]]; then
  echo "Downloading BlackHole ${BLACKHOLE_VERSION}..."
  curl --fail --location --progress-bar --output "$CACHED_PKG" "$DOWNLOAD_URL"
fi

ACTUAL_SHA256="$(shasum -a 256 "$CACHED_PKG" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "SHA-256 mismatch for $PKG_NAME" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  echo "  source:   $SOURCE_URL" >&2
  exit 3
fi

cp "$CACHED_PKG" "$STAGED_PKG"
echo "$EXPECTED_SHA256" > "$STATE_FILE"

cat > "$STAGE_DIR/README.md" <<EOF
# Dependencies staged for embedding

Staged by \`scripts/fetch_blackhole.sh\` so \`scripts/package_dmg.sh\` can
copy them into \`MacStream Host.app/Contents/Resources/dependencies/\`. The
runtime \`DependencyInstallerManager\` installs from the embedded copy via
\`AuthorizationExecuteWithPrivileges\` — one admin password prompt, no
Installer.app window.

Pinned upstream artifacts:

- BlackHole 2ch v${BLACKHOLE_VERSION}
  - Source: $SOURCE_URL
  - Download URL: $DOWNLOAD_URL
  - SHA-256: $EXPECTED_SHA256
EOF

echo "Done. BlackHole staged at $STAGED_PKG ($(du -h "$STAGED_PKG" | awk '{print $1}'))"
