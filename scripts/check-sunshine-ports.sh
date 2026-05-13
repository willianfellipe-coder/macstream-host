#!/usr/bin/env bash
set -u

echo "Checking common Sunshine ports without opening or changing ports"
echo

check_tcp_port() {
  local name="$1"
  local port="$2"

  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[listening] TCP $port $name"
  else
    echo "[closed]    TCP $port $name"
  fi
}

check_udp_port() {
  local name="$1"
  local port="$2"

  if lsof -nP -iUDP:"$port" >/dev/null 2>&1; then
    echo "[in use]    UDP $port $name"
  else
    echo "[unknown]   UDP $port $name"
  fi
}

check_tcp_port "HTTPS/nvhttp" 47984
check_tcp_port "HTTP" 47989
check_tcp_port "Web UI" 47990
check_tcp_port "RTSP" 48010
check_udp_port "Video" 47998
check_udp_port "Control" 47999
check_udp_port "Audio" 48000
check_udp_port "Microphone" 48002
