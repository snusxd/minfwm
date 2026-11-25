#!/bin/sh
# Create a stable self-signed code-signing identity in the login keychain.
# macOS TCC (Accessibility, Input Monitoring, Screen Recording) keys an ad-hoc
# signed binary by its cdhash, so every rebuild looks like a new app and the
# permission is asked again. A binary signed by a persistent certificate is
# keyed by its designated requirement (identifier + certificate) instead, so
# the grant survives rebuilds.
set -eu

NAME="${1:-minfwm Local Signing}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Identity '$NAME' already exists."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:minfwm 2>/dev/null \
  || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:minfwm
security import "$WORK/id.p12" -k "$KEYCHAIN" -P minfwm -T /usr/bin/codesign
echo "Created identity '$NAME'. Re-run cmake so the build signs with it."
