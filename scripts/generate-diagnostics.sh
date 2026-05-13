#!/usr/bin/env bash
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_section() {
  local title="$1"
  local script="$2"

  echo
  echo "## $title"
  "$script_dir/$script" || true
}

echo "MacStream Host local diagnostics"
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

run_section "Environment" "check-environment.sh"
run_section "macOS Version" "check-macos-version.sh"
run_section "Sunshine" "check-sunshine-installed.sh"
run_section "BlackHole" "check-blackhole-installed.sh"
run_section "Sunshine Ports" "check-sunshine-ports.sh"

echo
echo "No system changes were made."
