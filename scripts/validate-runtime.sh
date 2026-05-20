#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# End-to-end runtime validation for MacStream Host. Exercises everything
# that can break end-to-end Moonlight streaming and prints a structured
# pass/fail report. Designed to be safe to run while the engine is live —
# the only side effect is sending one `startRemoteWork` command to the
# agent if no engine is currently running.
#
# Usage:
#   ./scripts/validate-runtime.sh
#
# Exit code: 0 if all critical checks pass, 1 otherwise. Warnings are
# tolerated (they indicate manual permission grants the user still needs
# to perform).

set -uo pipefail

APP_BUNDLE="/Applications/MacStream Host.app"
AGENT_BINARY="$APP_BUNDLE/Contents/MacOS/macstream-agent"
ENGINE_APP="$APP_BUNDLE/Contents/Resources/sunshine/Sunshine.app"
ENGINE_BINARY="$ENGINE_APP/Contents/MacOS/Sunshine"
GUI_BINARY="$APP_BUNDLE/Contents/MacOS/MacStream Host"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.macstream.host.agent.plist"
AGENT_STATUS_FILE="$HOME/Library/Application Support/MacStreamHost/Agent/status.json"
AGENT_COMMAND_FILE="$HOME/Library/Application Support/MacStreamHost/Agent/command.json"
OWNERSHIP_FILE="$HOME/Library/Application Support/MacStreamHost/run/sunshine-owned-process.json"
IDENTITY_FILE="$HOME/Library/Application Support/MacStreamHost/identity.json"
SUNSHINE_STATE="$HOME/.config/sunshine/sunshine_state.json"
SUNSHINE_LOG="$HOME/.config/sunshine/sunshine.log"

PASS=0
FAIL=0
WARN=0
declare -a FAIL_LINES=()
declare -a WARN_LINES=()

c_green='\033[1;32m'
c_yellow='\033[1;33m'
c_red='\033[1;31m'
c_dim='\033[2m'
c_reset='\033[0m'

pass()  { printf "  ${c_green}✓${c_reset} %s\n" "$1"; PASS=$((PASS+1)); }
fail()  { printf "  ${c_red}✗${c_reset} %s\n" "$1"; FAIL=$((FAIL+1)); FAIL_LINES+=("$1"); }
warn()  { printf "  ${c_yellow}!${c_reset} %s\n" "$1"; WARN=$((WARN+1)); WARN_LINES+=("$1"); }
note()  { printf "  ${c_dim}·${c_reset} %s\n" "$1"; }
section(){ printf "\n${c_dim}== %s ==${c_reset}\n" "$1"; }

# ----------------------------------------------------------------------
section "1. App bundle integrity"
if [[ -d "$APP_BUNDLE" ]]; then
  pass "Bundle exists at $APP_BUNDLE"
  for binary in "$GUI_BINARY" "$ENGINE_BINARY" "$AGENT_BINARY" \
                "$APP_BUNDLE/Contents/MacOS/macstreamctl"; do
    if [[ -x "$binary" ]]; then
      pass "Executable: $(basename "$binary")"
    else
      fail "Missing executable: $binary"
    fi
  done

  # Bundle should NOT contain dependencies/ — BlackHole was removed
  if [[ -d "$APP_BUNDLE/Contents/Resources/dependencies" ]]; then
    fail "Bundle still ships Contents/Resources/dependencies (BlackHole) — should have been removed"
  else
    pass "No BlackHole .pkg in bundle (Tap API path confirmed)"
  fi

  # Codesign sanity
  if codesign --verify --verbose=2 "$APP_BUNDLE" >/dev/null 2>&1; then
    pass "codesign --verify succeeds on the bundle"
  else
    fail "codesign --verify FAILED on the bundle"
  fi

  if [[ -e "$APP_BUNDLE/Contents/MacOS/MacStreamEngine" ]]; then
    fail "Legacy flat engine exists at Contents/MacOS/MacStreamEngine — packaging regression"
  else
    pass "No legacy flat MacStreamEngine in Contents/MacOS"
  fi

  if [[ -d "$ENGINE_APP" ]]; then
    pass "Nested Sunshine.app exists"
  else
    fail "Missing nested Sunshine.app at $ENGINE_APP"
  fi

  # Codesign / identity sanity
  app_auth=$(codesign -dvv "$GUI_BINARY" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')
  eng_auth=$(codesign -dvv "$ENGINE_BINARY" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')
  if [[ -z "$app_auth" && -z "$eng_auth" ]]; then
    warn "Signed ad-hoc — every rebuild invalidates Screen Recording / Accessibility grants"
  elif [[ "$app_auth" == "$eng_auth" ]]; then
    pass "App and engine share Authority: '$app_auth'"
    if [[ "$app_auth" == "MacStream Local Dev" ]] || [[ "$app_auth" == Developer\ ID* ]]; then
      pass "Signed with stable identity (TCC grants will survive rebuilds)"
    fi
  else
    fail "App authority '$app_auth' ≠ engine authority '$eng_auth' — TCC will treat them as separate apps"
  fi

  # Engine identifier is intentionally separate: it is a nested app TCC subject.
  eng_id=$(codesign -dvv "$ENGINE_BINARY" 2>&1 | awk -F= '/^Identifier=/{print $2; exit}')
  if [[ "$eng_id" == "org.macstream.host.engine.sunshine" ]]; then
    pass "Engine identifier is org.macstream.host.engine.sunshine"
  else
    fail "Engine identifier is '$eng_id' (expected org.macstream.host.engine.sunshine)"
  fi
else
  fail "Bundle missing at $APP_BUNDLE"
fi

# ----------------------------------------------------------------------
section "2. LaunchAgent + agent process"
if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
  pass "LaunchAgent plist installed"
else
  fail "LaunchAgent plist missing at $LAUNCH_AGENT_PLIST"
fi

if launchctl list 2>/dev/null | grep -q com.macstream.host.agent; then
  pass "LaunchAgent loaded into launchctl"
else
  warn "LaunchAgent not loaded — run: launchctl load $LAUNCH_AGENT_PLIST"
fi

agent_pids=$(pgrep -f "MacStream Host\.app/Contents/MacOS/macstream-agent" 2>/dev/null || true)
agent_count=$(printf '%s\n' $agent_pids | grep -c . || true)
if [[ "$agent_count" -eq 1 ]]; then
  pass "Exactly one macstream-agent running (pid $agent_pids)"
elif [[ "$agent_count" -eq 0 ]]; then
  warn "No macstream-agent process — engine won't auto-start"
else
  fail "$agent_count macstream-agent processes (expected 1) — duplicate spawn"
fi

# ----------------------------------------------------------------------
section "3. Engine process + RTSP port"
engine_pids=$(pgrep -f "MacStream Host\.app/Contents/Resources/sunshine/Sunshine\.app/Contents/MacOS/Sunshine" 2>/dev/null || true)
engine_count=$(printf '%s\n' $engine_pids | grep -c . || true)

# If no engine is running and we have an agent, ask the agent to spawn one
# so the rest of the checks have something to look at.
if [[ "$engine_count" -eq 0 && "$agent_count" -ge 1 ]]; then
  note "No engine running — sending startRemoteWork to the agent..."
  uuid=$(uuidgen)
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AGENT_COMMAND_FILE" <<JSON
{"createdAt":"$now","id":"$uuid","kind":"startRemoteWork"}
JSON
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    engine_pids=$(pgrep -f "MacStream Host\.app/Contents/Resources/sunshine/Sunshine\.app/Contents/MacOS/Sunshine" 2>/dev/null || true)
    engine_count=$(printf '%s\n' $engine_pids | grep -c . || true)
    [[ "$engine_count" -ge 1 ]] && break
  done
fi

if [[ "$engine_count" -eq 1 ]]; then
  pass "Exactly one Sunshine engine running (pid $engine_pids)"
elif [[ "$engine_count" -eq 0 ]]; then
  fail "No Sunshine engine process (couldn't be spawned)"
else
  fail "$engine_count Sunshine engine processes (expected 1) — race in DefaultSunshineManager.start"
fi

# RTSP port 48010 must be bound by OUR engine (not stale)
port_owner_pid=$(lsof -nP -i:48010 2>/dev/null | awk 'NR>1 && $1 ~ /^(Sunshine|MacStream)/{print $2; exit}')
if [[ -n "$port_owner_pid" ]]; then
  if [[ -n "$engine_pids" ]] && printf '%s\n' $engine_pids | grep -q "^${port_owner_pid}\$"; then
    pass "Port 48010 (RTSP) bound by current engine"
  else
    fail "Port 48010 bound by pid $port_owner_pid, but that's not the current engine"
  fi
else
  fail "Port 48010 (RTSP) not listening"
fi

# Web UI must respond
http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 https://localhost:47990/ 2>/dev/null || echo 000)
if [[ "$http_code" -ge 200 && "$http_code" -lt 500 ]]; then
  pass "Web UI reachable on https://localhost:47990 (HTTP $http_code)"
else
  fail "Web UI not responding (HTTP $http_code)"
fi

# ----------------------------------------------------------------------
section "4. Sunshine identity stability"
if [[ -f "$IDENTITY_FILE" ]]; then
  pass "MacStream identity file present"
else
  warn "identity.json not yet generated — first engine start will create it"
fi
if [[ -f "$SUNSHINE_STATE" ]]; then
  uniqueid=$(python3 -c "import json,sys; d=json.load(open('$SUNSHINE_STATE')); print(d.get('root',{}).get('uniqueid','(none)'))" 2>/dev/null || echo "(parse failed)")
  if [[ "$uniqueid" != "(none)" && "$uniqueid" != "(parse failed)" ]]; then
    pass "Sunshine state has stable uniqueid: $uniqueid"
  else
    warn "Sunshine state.json exists but has no uniqueid"
  fi
else
  warn "Sunshine state.json missing — identity will be generated on next engine start"
fi

# ----------------------------------------------------------------------
section "5. mDNS announcement"
# Browse for _nvstream._tcp on the local domain, count unique instances
# macOS doesn't ship GNU `timeout`. Background dns-sd, give it 6 seconds,
# then kill so its accumulated output is captured.
dns_tmp=$(mktemp)
dns-sd -B _nvstream._tcp local >"$dns_tmp" 2>&1 &
DPID=$!
sleep 6
kill "$DPID" 2>/dev/null || true
wait "$DPID" 2>/dev/null || true
dns_browse_output=$(cat "$dns_tmp")
rm -f "$dns_tmp"
instances=$(echo "$dns_browse_output" \
  | awk '/Add/{ for(i=7;i<=NF;i++) printf "%s ", $i; printf "\n" }' \
  | sed 's/[[:space:]]*$//' \
  | sort -u \
  | grep -v '^$' || true)
instance_count=0
[[ -n "$instances" ]] && instance_count=$(printf '%s\n' "$instances" | wc -l | tr -d ' ')
if [[ "$instance_count" -ge 1 ]]; then
  pass "mDNS service _nvstream._tcp is announced ($instance_count unique instance(s))"
  while IFS= read -r line; do [[ -z "$line" ]] || note "  → $line"; done <<<"$instances"
else
  warn "mDNS announcement not visible — Moonlight clients may need manual Add Host"
fi

# ----------------------------------------------------------------------
section "6. Engine health (log analysis)"
if [[ -f "$SUNSHINE_LOG" ]]; then
  # Last engine boot timestamp
  last_boot=$(grep -a -n "Sunshine version" "$SUNSHINE_LOG" | tail -1 || true)
  if [[ -n "$last_boot" ]]; then
    pass "Engine boot logged: $(echo "$last_boot" | sed 's/^[0-9]*://' | head -c 100)..."
  else
    warn "No Sunshine boot banner found in log"
  fi

  # Look for TCC failures since last boot
  if grep -a "No screen capture permission" "$SUNSHINE_LOG" | tail -1 | grep -q ":"; then
    last_tcc_fail=$(grep -a -n "No screen capture permission" "$SUNSHINE_LOG" | tail -1)
    last_boot_line=$(grep -a -n "Sunshine version" "$SUNSHINE_LOG" | tail -1 | cut -d: -f1)
    tcc_line=$(echo "$last_tcc_fail" | cut -d: -f1)
    if [[ "$tcc_line" -gt "$last_boot_line" ]]; then
      fail "Screen Recording denied since last boot — re-grant in System Settings > Privacy & Security > Screen Recording"
    else
      pass "Screen Recording grant active (no TCC denial since last boot)"
    fi
  else
    pass "No Screen Recording TCC failures recorded"
  fi

  # Encoder detection
  if grep -a "Found H.264 encoder" "$SUNSHINE_LOG" | tail -1 | grep -q "videotoolbox"; then
    pass "VideoToolbox H.264 encoder found"
  else
    fail "VideoToolbox H.264 encoder not detected"
  fi
  if grep -a "Found HEVC encoder" "$SUNSHINE_LOG" | tail -1 | grep -q "videotoolbox"; then
    pass "VideoToolbox HEVC encoder found"
  else
    warn "VideoToolbox HEVC encoder not detected (H.264-only stream will still work)"
  fi

  # Display detection
  if grep -a "Detected display" "$SUNSHINE_LOG" | tail -1 | grep -q "connected: true"; then
    pass "Display detected by engine"
  else
    fail "No display detected — Moonlight will not stream video"
  fi

  # RTSP collision (count just lines, single command, no spurious echoes)
  rtsp_fails=$(grep -ac "Couldn't bind RTSP" "$SUNSHINE_LOG" 2>/dev/null)
  rtsp_fails=${rtsp_fails:-0}
  if [[ "$rtsp_fails" -eq 0 ]]; then
    pass "No RTSP port collisions recorded"
  else
    warn "$rtsp_fails RTSP collision(s) in the log history (may be stale)"
  fi
else
  warn "Sunshine log not found at $SUNSHINE_LOG"
fi

# ----------------------------------------------------------------------
section "7. Audio capture path"
if [[ -d /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver ]]; then
  warn "BlackHole driver still installed — Tap API validation won't be conclusive"
else
  pass "BlackHole driver absent (Tap API is the active capture path)"
fi
audio_sink=$(awk -F= '/^audio_sink/{print $2}' "$HOME/Library/Application Support/MacStreamHost/sunshine/sunshine.conf" 2>/dev/null | xargs || echo "")
if [[ -z "$audio_sink" ]]; then
  pass "sunshine.conf audio_sink is empty (engine will use Tap API on macOS 14.2+)"
else
  warn "sunshine.conf audio_sink = '$audio_sink' (not native Tap API)"
fi

# ----------------------------------------------------------------------
section "8. Accessibility (input forwarding)"
# Sunshine injects keyboard/mouse via CGEventPost — that requires Accessibility
# TCC for the process posting events. macstreamctl ships with the
# `axprobe` subcommand which calls AXIsProcessTrusted() for the
# MacStream Host identity and prints AX_TRUSTED=true|false. If video
# starts but input fails, also grant Accessibility to the nested
# MacStream Video Engine.
MACSTREAMCTL="$APP_BUNDLE/Contents/MacOS/macstreamctl"
if [[ -x "$MACSTREAMCTL" ]]; then
  ax_probe_output=$("$MACSTREAMCTL" axprobe 2>&1 || true)
  case "$ax_probe_output" in
    AX_TRUSTED=true)
      pass "AXIsProcessTrusted=true for org.macstream.host (keyboard/mouse should reach the Mac)"
      ;;
    AX_TRUSTED=false)
      fail "AXIsProcessTrusted=false — add MacStream Host to System Settings > Privacy & Security > Accessibility (input from Moonlight will be silently dropped)"
      ;;
    *)
      warn "axprobe gave unexpected output: $ax_probe_output"
      ;;
  esac
else
  warn "macstreamctl not found at $MACSTREAMCTL — cannot probe Accessibility"
fi

# ----------------------------------------------------------------------
section "9. Agent status report"
if [[ -f "$AGENT_STATUS_FILE" ]]; then
  # Pretty print key fields
  python3 - <<PY
import json
try:
    d = json.load(open("$AGENT_STATUS_FILE"))
    print(f"  state    : {d.get('state')}")
    print(f"  blockers : {d.get('blockers')}")
    print(f"  warnings : {d.get('warnings')}")
    for c in d.get('engineStatus', {}).get('components', []):
        print(f"  {c['id']:8} {c['status']:8} {c.get('detail','')}")
except Exception as e:
    print(f"  (failed to parse: {e})")
PY
  state=$(python3 -c "import json; print(json.load(open('$AGENT_STATUS_FILE')).get('state',''))" 2>/dev/null)
  case "$state" in
    running)  pass "Agent reports state=running" ;;
    degraded) warn "Agent reports state=degraded (often just waiting for client validation)" ;;
    blocked)  fail "Agent reports state=blocked" ;;
    *)        warn "Agent state=$state" ;;
  esac
else
  fail "Agent status file missing"
fi

# ----------------------------------------------------------------------
section "Summary"
total=$((PASS+WARN+FAIL))
printf "  ${c_green}%d passed${c_reset}, ${c_yellow}%d warning(s)${c_reset}, ${c_red}%d failure(s)${c_reset} of %d checks\n" \
  "$PASS" "$WARN" "$FAIL" "$total"

if [[ "$FAIL" -gt 0 ]]; then
  printf "\n${c_red}Failures:${c_reset}\n"
  for line in "${FAIL_LINES[@]}"; do printf "  • %s\n" "$line"; done
fi
if [[ "$WARN" -gt 0 ]]; then
  printf "\n${c_yellow}Warnings:${c_reset}\n"
  for line in "${WARN_LINES[@]}"; do printf "  • %s\n" "$line"; done
fi

[[ "$FAIL" -eq 0 ]]
