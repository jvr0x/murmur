#!/usr/bin/env bash
# One-time, INTERACTIVE setup of a self-signed code-signing identity for Murmur.
#
# Why this exists:
#   make-app.sh ad-hoc signs by default. That already pins a *stable* designated
#   requirement (DR) so TCC permission grants survive rebuilds — but an ad-hoc,
#   identifier-only DR is satisfied by ANY local binary that claims Murmur's
#   bundle identifier; there is no cryptographic anchor. Creating a real (though
#   self-signed) code-signing certificate makes make-app.sh instead produce a DR
#   of the form `identifier "..." and certificate leaf = H"..."`, which is both
#   stable across rebuilds AND anchored to this specific certificate.
#
# Run this ONCE, yourself, in a terminal. It is interactive on purpose: it needs
# your login-keychain password (so codesign can use the new key without a GUI
# prompt on every build), and macOS may show a trust-settings dialog. After it
# succeeds, make-app.sh auto-detects the identity — no further steps.
set -euo pipefail

# Certificate common-name / identity name. Must match make-app.sh's IDENTITY.
IDENTITY="${MURMUR_SIGN_IDENTITY:-Murmur Dev Signing}"
# User's login keychain (where the key + trust settings live).
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl not found in PATH." >&2; exit 1; }

# Idempotent: if the identity is already valid for code signing, do nothing.
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""; then
  echo "Code-signing identity '$IDENTITY' is already present and valid — nothing to do."
  exit 0
fi

echo "==> Creating a self-signed code-signing identity: $IDENTITY"

TMP="$(mktemp -d)"
cleanup() {
  # Plain rm/rmdir only (never rm -rf): wipe the on-disk key material as soon as
  # the key has been imported, so the private key does not linger on disk.
  rm -f "$TMP"/* 2>/dev/null || true
  rmdir "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

KEY="$TMP/key.pem"
CERT="$TMP/cert.pem"
P12="$TMP/identity.p12"
LOG="$TMP/openssl.log"
P12_PW="$(openssl rand -base64 18)"   # one-shot password, only used to move key+cert into the keychain

echo "    generating RSA-2048 key + certificate (valid 10 years)"
if ! openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY" -out "$CERT" -days 3650 \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE" 2>"$LOG"; then
  echo "ERROR: certificate generation failed:" >&2
  sed 's/^/    /' "$LOG" >&2
  exit 1
fi

# OpenSSL 3 defaults to an AES/PBKDF2 PKCS#12 that macOS `security import` can
# reject; -legacy emits the RC2/3DES + SHA1-MAC format Apple always reads.
# LibreSSL (the system /usr/bin/openssl) already emits that format and rejects
# the -legacy flag, so only pass it for OpenSSL 3.x.
P12_LEGACY=()
if openssl version | grep -qiE '^OpenSSL 3'; then
  P12_LEGACY=(-legacy)
fi
if ! openssl pkcs12 -export "${P12_LEGACY[@]}" \
    -inkey "$KEY" -in "$CERT" -out "$P12" \
    -name "$IDENTITY" -passout pass:"$P12_PW" 2>"$LOG"; then
  echo "ERROR: PKCS#12 export failed:" >&2
  sed 's/^/    /' "$LOG" >&2
  exit 1
fi

echo "==> Importing the identity into your login keychain"
# -T grants codesign/security access to the key's ACL (still gated by the
# partition list set below).
security import "$P12" -k "$LOGIN_KEYCHAIN" -f pkcs12 -P "$P12_PW" \
  -T /usr/bin/codesign -T /usr/bin/security

echo
echo "macOS needs your LOGIN keychain password (the password you type to log in"
echo "to this Mac) so codesign can use the new key WITHOUT a GUI prompt on every"
echo "build. It is read silently and passed only to the next command."
read -r -s -p "Login keychain password: " LOGIN_PW
echo
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$LOGIN_PW" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
  echo "ERROR: could not set the key partition list (wrong login password?)." >&2
  echo "       The key was imported; open Keychain Access, delete the '$IDENTITY'" >&2
  echo "       key/cert, then re-run this script." >&2
  exit 1
fi

echo
echo "==> Trusting the certificate for code signing"
echo "    macOS may now show a trust-settings confirmation dialog — approve it."
security add-trusted-cert -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$CERT"

echo
echo "==> Verifying"
if security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
  echo "    OK: '$IDENTITY' is now a valid code-signing identity"
else
  echo "ERROR: '$IDENTITY' did not become a valid code-signing identity." >&2
  echo "       Check the trust settings for it in Keychain Access, or re-run." >&2
  exit 1
fi

# Prove signing actually works end-to-end on a throwaway copy of a real binary.
TESTBIN="$TMP/testbin"
cp /bin/ls "$TESTBIN"
if codesign --force --timestamp=none --sign "$IDENTITY" "$TESTBIN" 2>/dev/null \
    && codesign --verify --strict "$TESTBIN" 2>/dev/null; then
  echo "    OK: a test binary signs and verifies with '$IDENTITY'"
  echo "    designated requirement it produces:"
  codesign -d -r- "$TESTBIN" 2>/dev/null | sed 's/^/      /'
else
  echo "ERROR: signing a test binary with '$IDENTITY' failed." >&2
  exit 1
fi

cat <<EOF

Done — '$IDENTITY' is ready to use.

Next steps:
  1. Rebuild the app:  ./Scripts/make-app.sh
     (it auto-detects the identity and signs with it — no flags needed).
  2. Expect ONE final permission re-grant. Switching from the old ad-hoc DR to
     the new certificate-anchored DR changes the designated requirement one last
     time, so macOS asks for Microphone / Accessibility / Input Monitoring once
     more. Grant them.
  3. After that, every rebuild keeps the same DR, so your grants persist.
EOF
