#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
NAME="Keylapse Local Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

umask 077
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/keylapse-signing.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
# Reuse the certificate, including after an interrupted trust confirmation.
if security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$TEMP/cert.pem" 2>/dev/null; then
    IDENTITIES="$(security find-identity -v -p codesigning "$KEYCHAIN")"
    if [[ "$IDENTITIES" == *'"Keylapse Local Development"'* ]]; then
        printf 'Local signing identity is ready.\n'
        exit 0
    fi
else
    export KEYLAPSE_P12_PASSWORD="$(openssl rand -hex 32)"
    openssl req -new -newkey rsa:3072 -x509 -sha256 -days 3650 -nodes \
        -config "$ROOT/scripts/local-signing.cnf" \
        -keyout "$TEMP/key.pem" -out "$TEMP/cert.pem"
    # Explicit algorithms work with Apple's importer and OpenSSL 3.
    openssl pkcs12 -export -name "$NAME" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -inkey "$TEMP/key.pem" -in "$TEMP/cert.pem" \
        -out "$TEMP/identity.p12" -passout env:KEYLAPSE_P12_PASSWORD
    security import "$TEMP/identity.p12" -k "$KEYCHAIN" \
        -P "$KEYLAPSE_P12_PASSWORD" -T /usr/bin/codesign
    unset KEYLAPSE_P12_PASSWORD
fi
# User-domain trust is limited to code signing, not TLS or other policies.
# macOS may request authentication here.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TEMP/cert.pem"
security find-identity -v -p codesigning "$KEYCHAIN"
printf 'Local signing identity installed in the login keychain.\n'
