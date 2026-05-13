#!/usr/bin/env bash
set -u

echo "Checking for Sunshine without modifying the system"

found=0
candidates=(
  "$(command -v sunshine 2>/dev/null || true)"
  "/Applications/Sunshine.app/Contents/MacOS/sunshine"
  "/Applications/MacStream Host.app/Contents/Resources/sunshine/bin/sunshine"
  "$HOME/Applications/Sunshine.app/Contents/MacOS/sunshine"
)

for candidate in "${candidates[@]}"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    echo "Found executable: $candidate"
    echo "Version check skipped to avoid invoking Sunshine or printing local user configuration."
    found=1
  fi
done

if [[ "$found" -eq 1 ]]; then
  echo "Result: Sunshine candidate found"
  exit 0
fi

echo "Result: Sunshine not found"
exit 1
