#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ⚠ STATUS: WORK IN PROGRESS — see "Known bug" below before relying on this.
#
# Creates a persistent self-signed code signing identity named "MacStream
# Local Dev" in the developer's login keychain. Subsequent package_dmg.sh
# runs use this identity to produce a stable cdhash across rebuilds, so a
# Screen Recording grant survives every `swift build`.
#
# Known bug (as of 2026-05-14, macOS 26.5.0 Tahoe):
#   `security import` of the PKCS#12 produced here imports the certificate
#   but does not pair it with the private key, so `security find-identity
#   -v -p codesigning` returns 0 entries afterwards even though the cert is
#   visible via `security find-certificate -c "MacStream Local Dev"`. Tried
#   several PKCS#12 variants (-legacy, -keypbe PBE-SHA1-3DES, -macalg sha1,
#   -iter 2048) — all the same outcome. The next iteration will likely
#   bypass PKCS#12 entirely and use the Swift Security framework
#   (SecKeyCreateRandomKey + a hand-rolled cert via swift-certificates +
#   SecItemAdd) so the keypair is born inside the keychain.
#
# Until that lands, package_dmg.sh falls back to ad-hoc signing and the
# user must re-grant Screen Recording / Accessibility after every rebuild.
#
# Without this:
#   - codesign falls back to ad-hoc (`-`).
#   - Each rebuild gets a new cdhash.
#   - TCC keys Screen Recording grants by cdhash for ad-hoc apps.
#   - User has to re-grant permission every build cycle.
#
# With this:
#   - Both MacStream Host and MacStreamEngine sign with the same identity.
#   - The "designated requirement" stored by TCC becomes anchor-based instead
#     of cdhash-based, so it survives binary changes that don't affect the
#     cert chain.
#   - One grant covers both binaries inside the bundle (same identifier +
#     same anchor cert).
#
# Idempotent. Safe to re-run. Prints the identity name on stdout when done.
#
# Usage:
#   ./scripts/setup_local_codesign_identity.sh
#   IDENTITY=$(./scripts/setup_local_codesign_identity.sh) ./scripts/package_dmg.sh

set -euo pipefail

IDENTITY_NAME="MacStream Local Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# macOS ships LibreSSL whose PKCS#12 exports use a MAC algorithm the Keychain
# tools no longer accept (PBKDF2-HMAC-SHA256). Prefer OpenSSL 3 from Homebrew
# (or wherever it lives) which has `-legacy` to produce a compatible bundle.
OPENSSL_CMD=""
for candidate in /opt/homebrew/bin/openssl /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/bin/openssl; do
  if [[ -x "$candidate" ]] && "$candidate" version 2>/dev/null | grep -q "OpenSSL 3"; then
    OPENSSL_CMD="$candidate"
    break
  fi
done
if [[ -z "$OPENSSL_CMD" ]]; then
  echo "ERROR: OpenSSL 3 is required for PKCS#12 export compatible with macOS Keychain." >&2
  echo "Install Homebrew OpenSSL: brew install openssl@3" >&2
  exit 2
fi

if ! /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | grep -q "$IDENTITY_NAME"; then

  echo "Creating self-signed code signing identity: $IDENTITY_NAME" >&2
  echo "Using $OPENSSL_CMD" >&2

  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT

  "$OPENSSL_CMD" genrsa -out "$WORK_DIR/key.pem" 2048 2>/dev/null

  # X.509 extension profile required by macOS for code signing certificates:
  #   - basicConstraints: not a CA
  #   - keyUsage: digitalSignature
  #   - extendedKeyUsage: 1.3.6.1.5.5.7.3.3 (codeSigning)
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

  # Force every PKCS12 layer to algorithms that macOS Keychain accepts:
  #   - keypbe / certpbe: PBE-SHA1-3DES (legacy PKCS12 encryption)
  #   - macalg: SHA1 (legacy MAC, what macOS verifies)
  #   - iter: 2048 (Apple's minimum)
  # Without `-legacy` AND explicit `-macalg sha1`, OpenSSL 3 still writes a
  # PBMAC1 (PBKDF2-SHA256) header that macOS rejects with "MAC verification
  # failed".
  P12_PASSWORD="macstream-local-dev"
  "$OPENSSL_CMD" pkcs12 -export \
    -inkey "$WORK_DIR/key.pem" \
    -in "$WORK_DIR/cert.pem" \
    -name "$IDENTITY_NAME" \
    -out "$WORK_DIR/identity.p12" \
    -passout "pass:$P12_PASSWORD" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    -iter 2048 \
    -legacy

  /usr/bin/security import "$WORK_DIR/identity.p12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null

  # `import -A` allows any app to access the key, but on macOS 10.12+ the
  # Keychain partition list still gates access on first use with a GUI prompt
  # — even when the key is supposed to be open. Updating the partition list
  # explicitly lets codesign use it non-interactively.
  /usr/bin/security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "" \
    "$KEYCHAIN" \
    >/dev/null 2>&1 || true

  echo "Identity '$IDENTITY_NAME' imported into login keychain." >&2
else
  echo "Identity '$IDENTITY_NAME' already exists in login keychain." >&2
fi

# Verify it works for code signing
if ! /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | grep -q "$IDENTITY_NAME"; then
  echo "ERROR: '$IDENTITY_NAME' is not usable for codesigning. Check Keychain Access." >&2
  exit 1
fi

# Emit the identity name on stdout so callers can capture it.
echo "$IDENTITY_NAME"
