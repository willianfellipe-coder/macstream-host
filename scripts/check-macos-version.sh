#!/usr/bin/env bash
set -u

required_major=14
required_minor=2
version="$(sw_vers -productVersion)"
IFS=. read -r major minor patch <<< "$version"
minor="${minor:-0}"
patch="${patch:-0}"

echo "Detected macOS: $version"
echo "Required macOS: ${required_major}.${required_minor}+"

if (( major > required_major )) || (( major == required_major && minor >= required_minor )); then
  echo "Result: OK"
  exit 0
fi

echo "Result: unsupported for the initial target"
exit 1
