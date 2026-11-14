#!/bin/bash
# One-time: create a self-signed code-signing identity in your login keychain.
# Signing with a stable identity keeps macOS privacy grants (Accessibility,
# Microphone, Screen Recording) across rebuilds. Ad-hoc signatures change every
# build, so macOS silently revokes every grant each time.
set -euo pipefail
NAME="${POINT_SIGN_ID:-Point Dev}"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "'$NAME' already exists."; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" 2>/dev/null
LEGACY=""; openssl version | grep -q "^OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/id.p12" -passout pass:tmp
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign
echo "Created '$NAME'. (CSSMERR_TP_NOT_TRUSTED in find-identity is expected and fine.)"
echo ""
echo "To stop codesign asking for your keychain password on every build, run once:"
echo "  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l \"$NAME\" ~/Library/Keychains/login.keychain-db"
