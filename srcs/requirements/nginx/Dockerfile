# syntax=docker/dockerfile:1
# NGINX — the only ingress to the stack. Terminates TLS (1.2 / 1.3 only,
# self-signed) on :443 and proxies PHP requests over FastCGI to the
# WordPress container on :9000.

FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="inception-nginx" \
      org.opencontainers.image.source="https://github.com/halilalbayrak/42inception" \
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
    # Route access/error logs to docker (stdout/stderr) by replacing the
    # files nginx writes to with fd symlinks. The package creates them as
    # regular files during install, hence the rm + ln.
    rm -f /var/log/nginx/access.log /var/log/nginx/error.log; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    mkdir -p /etc/nginx/ssl /var/www/html; \
    chown -R www-data:www-data /var/www/html

# Drop in the site config. Debian's package ships a default file in
# sites-enabled that would clash with ours — remove it.
RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
COPY conf/inception.conf       /etc/nginx/conf.d/inception.conf

COPY tools/entrypoint.sh       /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 443

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
    CMD curl -ksS https://localhost/ -o /dev/null || exit 1
# Note: no `-f` flag, so a 502 (WordPress still installing) still counts as
# "nginx is up". We only care that nginx is listening on 443 and serving
# TLS; the upstream readiness is the wordpress container's concern.

# The entrypoint generates the self-signed cert on first start (so the
# secret material isn't baked into the image), then execs nginx.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
