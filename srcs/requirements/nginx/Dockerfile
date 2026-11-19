FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="inception-nginx" \
      org.opencontainers.image.source="https://github.com/HalilAlb/42inception" \
      org.opencontainers.image.description="nginx 1.22 + openssl on Debian 12"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        nginx \
        openssl \
        ca-certificates \
        curl \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /var/log/nginx/access.log /var/log/nginx/error.log; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    mkdir -p /etc/nginx/ssl /var/www/html; \
    chown -R www-data:www-data /var/www/html

RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
COPY conf/inception.conf       /etc/nginx/conf.d/inception.conf

COPY tools/entrypoint.sh       /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 443

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
    CMD curl -ksS https://localhost/ -o /dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
