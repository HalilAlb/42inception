#!/bin/bash
set -euo pipefail

SSL_DIR=/etc/nginx/ssl
CERT="$SSL_DIR/inception.crt"
KEY="$SSL_DIR/inception.key"
CN="${CERT_CN:-${DOMAIN_NAME:-localhost}}"

if [[ ! -s "$CERT" || ! -s "$KEY" ]]; then
    echo "[nginx] generating self-signed TLS cert for CN=${CN}"
    mkdir -p "$SSL_DIR"
    openssl req -x509 -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout "$KEY" \
        -out    "$CERT" \
        -subj   "/C=TR/ST=Istanbul/L=Istanbul/O=42/OU=inception/CN=${CN}" \
        >/dev/null 2>&1
    chmod 600 "$KEY"
fi

nginx -t

exec "$@"
