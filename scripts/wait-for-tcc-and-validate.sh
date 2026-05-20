#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Polls until the user grants Screen Recording to MacStream Host, then
# respawns the engine and runs the full validation. macOS TCC cannot be
# bypassed in any way, but we CAN watch the engine log for the "No
# screen capture permission" diagnostic and react immediately when it
# stops appearing.
#
# Usage:
#   ./scripts/wait-for-tcc-and-validate.sh [TIMEOUT_SECONDS]
#
# Default timeout is 600 seconds (10 min). Exit 0 on success, 1 on
# validation failure, 2 on timeout.

set -uo pipefail

TIMEOUT="${1:-600}"
SUNSHINE_LOG="$HOME/.config/sunshine/sunshine.log"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

c_green='\033[1;32m'
c_yellow='\033[1;33m'
c_red='\033[1;31m'
c_dim='\033[2m'
c_reset='\033[0m'

start=$(date +%s)
attempt=0

trigger_respawn() {
  attempt=$((attempt+1))
  # Restart the owned nested Sunshine.app so it re-evaluates TCC.
  /Applications/MacStream\ Host.app/Contents/MacOS/macstreamctl restart >/dev/null 2>&1 || true
  : > "$SUNSHINE_LOG"
}

check_tcc_ok() {
  # The engine log either has "No screen capture permission" (failure) or
  # "Found H.264 encoder" (success). Use a fresh log truncated by trigger_respawn.
  local timeout_after=$((SECONDS+8))
  while (( SECONDS < timeout_after )); do
    if grep -aq "Found H.264 encoder" "$SUNSHINE_LOG" 2>/dev/null; then
      return 0
    fi
    if grep -aq "No screen capture permission" "$SUNSHINE_LOG" 2>/dev/null; then
      return 1
    fi
    sleep 0.3
  done
  return 2 # unknown — log didn't reach either marker
}

printf "${c_dim}Waiting for Screen Recording grant for MacStream Host + MacStream Video Engine.${c_reset}\n"
printf "${c_dim}System Settings > Privacy & Security > Screen Recording has been opened.${c_reset}\n"
printf "${c_dim}Will poll every 10s for up to %ss. Ctrl+C to abort.${c_reset}\n\n" "$TIMEOUT"

while :; do
  elapsed=$(($(date +%s)-start))
  if (( elapsed > TIMEOUT )); then
    printf "${c_red}Timeout after %ss without TCC grant.${c_reset}\n" "$elapsed"
    exit 2
  fi

  trigger_respawn
  printf "[%ss] attempt #%d: " "$elapsed" "$attempt"
  if check_tcc_ok; then
    printf "${c_green}TCC granted, encoder found!${c_reset}\n\n"
    break
  else
    printf "${c_yellow}still denied${c_reset}\n"
  fi

  sleep 10
done

# Bring the GUI to the front so the user can see the dashboard reacted.
open "/Applications/MacStream Host.app" 2>/dev/null || true

printf "${c_dim}Running full validation:${c_reset}\n\n"
exec "$ROOT/scripts/validate-runtime.sh"
