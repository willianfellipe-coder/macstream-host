#!/usr/bin/env bash
set -u

echo "Checking for BlackHole without modifying the system"

found=0
hal_candidates=(
  "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
  "/Library/Audio/Plug-Ins/HAL/BlackHole.driver"
  "$HOME/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
  "$HOME/Library/Audio/Plug-Ins/HAL/BlackHole.driver"
)

for candidate in "${hal_candidates[@]}"; do
  if [[ -e "$candidate" ]]; then
    echo "Found HAL candidate: $candidate"
    found=1
  fi
done

if command -v system_profiler >/dev/null 2>&1; then
  if system_profiler SPAudioDataType 2>/dev/null | grep -qi "BlackHole"; then
    echo "Found BlackHole in system_profiler audio data"
    found=1
  fi
fi

if [[ "$found" -eq 1 ]]; then
  echo "Result: BlackHole candidate found"
  exit 0
fi

echo "Result: BlackHole not found"
exit 1
