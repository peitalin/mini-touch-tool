#!/bin/bash
set -euo pipefail
umask 077

app_dir="$1"
signing_dir="$HOME/Library/Application Support/Mini Touch Tool Signing"
keychain_path="$signing_dir/signing.keychain-db"
password_path="$signing_dir/keychain-password"
certificate_path="$signing_dir/certificate.pem"
identity_name="Mini Touch Tool Local Signing"
created_identity=false

if [ ! -d "$signing_dir" ]; then
    created_identity=true
    mkdir -m 700 "$signing_dir"
    /usr/bin/openssl rand -base64 32 > "$password_path"
    keychain_password="$(cat "$password_path")"
    security create-keychain -p "$keychain_password" "$keychain_path"
    security unlock-keychain -p "$keychain_password" "$keychain_path"

    temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/mini-touch-signing.XXXXXX")"
    trap 'rm -rf "$temporary_dir"' EXIT
    cat > "$temporary_dir/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = subject
prompt = no
x509_extensions = extensions

[subject]
CN = Mini Touch Tool Local Signing

[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
    /usr/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
        -out "$temporary_dir/private-key.pem" 2> /dev/null
    /usr/bin/openssl req -new -x509 -sha256 -days 3650 \
        -key "$temporary_dir/private-key.pem" -config "$temporary_dir/certificate.cnf" \
        -out "$certificate_path"
    security import "$temporary_dir/private-key.pem" -k "$keychain_path" -t priv -x -T /usr/bin/codesign
    security import "$certificate_path" -k "$keychain_path" -t cert
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$keychain_password" "$keychain_path" > /dev/null
    printf '%s\n' 'Created the persistent local signing identity.'
fi

if [ ! -f "$keychain_path" ] || [ ! -f "$password_path" ] || [ ! -f "$certificate_path" ]; then
    printf '%s\n' "The signing identity is incomplete at: $signing_dir" >&2
    printf '%s\n' 'Restore this identity to preserve permission grants across updates.' >&2
    exit 1
fi

keychain_password="$(cat "$password_path")"
security unlock-keychain -p "$keychain_password" "$keychain_path"
registered=false
keychains=()
keychain_list="$(security list-keychains -d user)"
while IFS= read -r keychain; do
    keychains+=("$keychain")
    if [ "$keychain" = "$keychain_path" ]; then
        registered=true
    fi
done < <(printf '%s\n' "$keychain_list" | sed -E 's/^[[:space:]]*"//; s/"$//')
if [ "$registered" = false ]; then
    security list-keychains -d user -s "${keychains[@]}" "$keychain_path"
fi
if [ "$created_identity" = true ]; then
    security add-trusted-cert -r trustRoot -p codeSign -a /usr/bin/codesign "$certificate_path"
fi
certificate_hash="$(/usr/bin/openssl x509 -in "$certificate_path" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
requirement="designated => identifier \"com.peitalin.MiniTouchTool\" and certificate leaf = H\"$certificate_hash\""
codesign --force --sign "$identity_name" --keychain "$keychain_path" --timestamp=none \
    --identifier com.peitalin.MiniTouchTool --requirements "=$requirement" "$app_dir"
codesign --verify --strict "$app_dir"
