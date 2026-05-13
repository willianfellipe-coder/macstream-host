#!/usr/bin/env bash
set -u

echo "MacStream Host environment check"
echo

echo "macOS:"
sw_vers
echo

echo "Architecture:"
uname -m
echo

echo "Swift:"
if command -v swift >/dev/null 2>&1; then
  swift --version
else
  echo "swift not found"
fi
echo

echo "Xcode path:"
if command -v xcode-select >/dev/null 2>&1; then
  xcode-select -p
else
  echo "xcode-select not found"
fi
