#!/usr/bin/env bash
# Creates ordino's free code-signing identity: a self-signed certificate
# ("ordino Self-Signed", valid 10 years) in a dedicated keychain.
#
# Why: macOS ties the Accessibility permission to the app's signature. Ad-hoc
# signatures change with every build, so users would have to re-grant access
# after every update. A stable certificate keeps the same signature identity.
#
# Why a separate keychain: it has its own password (stored next to it, 0600),
# so codesign can use the key from scripts and the launchd CI runner without a
# keychain prompt, and the login keychain is left alone.
#
#   scripts/setup-signing.sh            # create (does nothing if it exists)
#   scripts/setup-signing.sh --export   # print the cert as PEM (for backups)
set -euo pipefail

DIR="${ORDINO_SIGNING_DIR:-$HOME/.config/ordino}"
KEYCHAIN="$DIR/signing.keychain-db"
PASSFILE="$DIR/signing.keychain-password"
NAME="ordino Self-Signed"
mkdir -p "$DIR"
chmod 700 "$DIR"

if [ "${1:-}" = "--export" ]; then
  security find-certificate -c "$NAME" -p "$KEYCHAIN"
  exit 0
fi

if [ -f "$KEYCHAIN" ] && security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
  echo "Identity '$NAME' already exists in $KEYCHAIN"
  security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME"
  exit 0
fi

# macOS' own LibreSSL: Homebrew's OpenSSL 3 writes PKCS#12 files that
# `security import` can't read.
OPENSSL=/usr/bin/openssl

# A keychain left over from an interrupted run (no identity in it) is recreated.
if [ -f "$KEYCHAIN" ]; then
  echo "==> Removing incomplete keychain from an earlier run"
  security delete-keychain "$KEYCHAIN"
fi

WORK="$(mktemp -d)"
umask 077
"$OPENSSL" rand -base64 32 | tr -d '\n' > "$PASSFILE"
P12PASS="$("$OPENSSL" rand -hex 16)"

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = ordino
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

echo "==> Generating key and certificate"
"$OPENSSL" req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$WORK/identity.p12" -passout "pass:$P12PASS" 2>/dev/null

echo "==> Creating keychain $KEYCHAIN"
security create-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # no auto-lock timeout
security unlock-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat "$PASSFILE")" "$KEYCHAIN" >/dev/null

echo "==> Done"
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true
echo "Back up $DIR (keychain + password file) in your password manager."
