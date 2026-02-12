#!/usr/bin/env bash
# Setup stable development code signing to reduce keychain prompts.
set -euo pipefail

APP_NAME=${APP_NAME:-Shellporter}
CERT_NAME="${APP_NAME} Development"
P12_PASSWORD="shellporter-dev-cert"
KEY_FILE=$(mktemp /tmp/shellporter-dev-key.XXXXXX.pem)
CRT_FILE=$(mktemp /tmp/shellporter-dev-crt.XXXXXX.pem)
P12_FILE=$(mktemp /tmp/shellporter-dev-p12.XXXXXX.p12)

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "Certificate '$CERT_NAME' already exists."
  echo "Export this in your shell profile:"
  echo "  export APP_IDENTITY='$CERT_NAME'"
  exit 0
fi

echo "Creating self-signed certificate '$CERT_NAME'..."

TEMP_CONFIG=$(mktemp)
trap "rm -f \"$TEMP_CONFIG\" \"$KEY_FILE\" \"$CRT_FILE\" \"$P12_FILE\"" EXIT

cat > "$TEMP_CONFIG" <<EOFCONF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = $CERT_NAME
O = ${APP_NAME} Development
C = US

[ v3_req ]
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOFCONF

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
    -nodes -keyout "$KEY_FILE" -out "$CRT_FILE" \
    -config "$TEMP_CONFIG" >/dev/null 2>&1

build_pkcs12() {
  local mode="${1:-default}"
  if [[ "$mode" == "legacy" ]]; then
    openssl pkcs12 -export -legacy -out "$P12_FILE" \
      -inkey "$KEY_FILE" -in "$CRT_FILE" \
      -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1
  else
    openssl pkcs12 -export -out "$P12_FILE" \
      -inkey "$KEY_FILE" -in "$CRT_FILE" \
      -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1
  fi
}

import_pkcs12() {
  security import "$P12_FILE" -k ~/Library/Keychains/login.keychain-db \
    -P "${P12_PASSWORD}" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
}

build_pkcs12 default
if ! import_pkcs12; then
  echo "Default PKCS12 import failed. Retrying with legacy encoding..."
  build_pkcs12 legacy
  if ! import_pkcs12; then
    echo "Failed to import development certificate into keychain." >&2
    exit 1
  fi
fi

echo ""
echo "Trust this certificate for code signing in Keychain Access."
echo "Then export in your shell profile:"
echo "  export APP_IDENTITY='$CERT_NAME'"
