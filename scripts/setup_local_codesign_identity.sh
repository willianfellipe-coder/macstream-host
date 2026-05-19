#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Creates a persistent self-signed code signing identity named "MacStream
# Local Dev" in the developer's login keychain. Subsequent package_dmg.sh
# runs sign all binaries with the same identity, producing a stable
# designated requirement so Screen Recording / Accessibility / Microphone
# grants survive every `swift build` cycle.
#
# Why this is needed: ad-hoc signing (`codesign --sign -`) generates a fresh
# cdhash on every rebuild. macOS TCC keys those grants by cdhash, so the
# user has to re-add MacStream Host + MacStream Video Engine to System
# Settings after every package_dmg.sh. With a real self-signed cert,
# the leaf cert hash stays constant across rebuilds even when the binary
# content changes — TCC stores the requirement once and keeps honoring it.
#
# Implementation notes:
#
# 1. Generate RSA 2048 key + self-signed X.509 cert with codeSigning EKU
#    via OpenSSL 3 (Homebrew).
# 2. Import the private key into the login keychain as DER-encoded PKCS#8.
#    (`security import` rejects PEM PKCS#8 with "Unknown format in import";
#    rejects PKCS#12 bundles wholesale with "MAC verification failed"; only
#    accepts the raw DER form.)
# 3. Import the certificate separately.
# 4. Update the partition list so /usr/bin/codesign can use the key without
#    prompting on first use.
#
# Verification gotcha: `security find-identity -v -p codesigning` only lists
# identities chained to roots Apple already trusts for code signing. Our
# self-signed cert won't show there even when fully functional. We verify
# by attempting a real signing operation against a throwaway binary, which
# is the only test that matches what package_dmg.sh actually does.
#
# Idempotent. Safe to re-run. Emits the identity name on stdout when done.
#
# Usage:
#   ./scripts/setup_local_codesign_identity.sh
#   IDENTITY=$(./scripts/setup_local_codesign_identity.sh) ./scripts/package_dmg.sh
#   # OR: package_dmg.sh autoresolves the identity if it's already in the keychain

set -euo pipefail

IDENTITY_NAME="MacStream Local Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# Locate an OpenSSL 3 install — macOS ships LibreSSL which uses incompatible
# PKCS#8 defaults and refuses some of the legacy options we need.
OPENSSL_CMD=""
for candidate in /opt/homebrew/bin/openssl /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/bin/openssl; do
  if [[ -x "$candidate" ]] && "$candidate" version 2>/dev/null | grep -q "OpenSSL 3"; then
    OPENSSL_CMD="$candidate"
    break
  fi
done
if [[ -z "$OPENSSL_CMD" ]]; then
  echo "ERROR: OpenSSL 3 is required. Install with: brew install openssl@3" >&2
  exit 2
fi

# grep -q matches early and closes the upstream pipe, which under `set -o
# pipefail` makes `codesign -dvv | grep -q ...` return SIGPIPE (141) even
# on a successful match. Capture the verify output first and grep against
# the buffer to keep pipefail honest.
verify_signed_with_identity() {
  local bin="$1"
  local output
  output="$(/usr/bin/codesign -dvv "$bin" 2>&1)"
  [[ "$output" == *"Authority=$IDENTITY_NAME"* ]]
}

# Probe: can codesign already sign with this identity? If yes, we're done.
PROBE_DIR="$(mktemp -d)"
trap 'rm -rf "$PROBE_DIR"' EXIT
PROBE_BIN="$PROBE_DIR/probe"
printf '#!/bin/sh\nexit 0\n' > "$PROBE_BIN"
chmod +x "$PROBE_BIN"

if /usr/bin/codesign --force --sign "$IDENTITY_NAME" "$PROBE_BIN" 2>/dev/null \
   && verify_signed_with_identity "$PROBE_BIN"; then
  echo "Identity '$IDENTITY_NAME' already usable for codesigning." >&2
  echo "$IDENTITY_NAME"
  exit 0
fi

echo "Creating self-signed code signing identity: $IDENTITY_NAME" >&2
echo "Using $OPENSSL_CMD" >&2

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$PROBE_DIR" "$WORK_DIR"' EXIT

# 1. Generate RSA 2048 private key
"$OPENSSL_CMD" genrsa -out "$WORK_DIR/key.pem" 2048 2>/dev/null

# 2. Generate self-signed cert with codeSigning EKU
cat > "$WORK_DIR/ext.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
[ dn ]
CN = $IDENTITY_NAME
O = MacStream
[ ext ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL_CMD" req -new -x509 \
  -key "$WORK_DIR/key.pem" \
  -out "$WORK_DIR/cert.pem" \
  -days 3650 \
  -config "$WORK_DIR/ext.cnf" \
  -extensions ext \
  2>/dev/null

# 3. Convert key to DER PKCS#8 (security only accepts this for -t priv)
"$OPENSSL_CMD" pkcs8 -topk8 -inform PEM -outform DER \
  -in "$WORK_DIR/key.pem" \
  -out "$WORK_DIR/key.p8.der" \
  -nocrypt 2>/dev/null

# 4. Clean any prior incomplete state (best-effort)
/usr/bin/security delete-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1 || true

# 5. Import private key
/usr/bin/security import "$WORK_DIR/key.p8.der" \
  -k "$KEYCHAIN" \
  -t priv \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null

# 6. Import certificate
/usr/bin/security import "$WORK_DIR/cert.pem" \
  -k "$KEYCHAIN" \
  -t cert \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null

# 7. Open partition list so codesign can use the key non-interactively
/usr/bin/security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "" \
  "$KEYCHAIN" \
  >/dev/null 2>&1 || true

# 8. Functional verification: actually sign a throwaway binary.
SIGN_OUTPUT=$(/usr/bin/codesign --force --sign "$IDENTITY_NAME" "$PROBE_BIN" 2>&1) || {
  echo "ERROR: codesign refused to use '$IDENTITY_NAME':" >&2
  echo "$SIGN_OUTPUT" >&2
  exit 1
}
if verify_signed_with_identity "$PROBE_BIN"; then
  echo "Identity '$IDENTITY_NAME' imported and verified by signing a test binary." >&2
  echo "$IDENTITY_NAME"
else
  echo "ERROR: signed with '$IDENTITY_NAME' but Authority line is missing:" >&2
  /usr/bin/codesign -dvv "$PROBE_BIN" >&2 2>&1
  exit 1
fi
