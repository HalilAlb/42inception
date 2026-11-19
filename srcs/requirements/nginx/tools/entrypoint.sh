#!/bin/bash
# Generate a self-signed cert on first boot if one isn't there yet, then
# `exec nginx`. Cert generation is at runtime (not build time) so the key
# material never ends up in the image layer cache.
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

# Fail loudly on a broken config before handing off to nginx as PID 1.
nginx -t

exec "$@"
