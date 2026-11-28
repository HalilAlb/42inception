FROM debian:bookworm-slim

ENV WP_VERSION=6.7.2 \
    WP_CLI_VERSION=2.11.0 \
    WP_PATH=/var/www/html

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl less \
        mariadb-client \
        php8.2-fpm \
        php8.2-cli \
        php8.2-mysql \
        php8.2-curl \
        php8.2-gd \
        php8.2-mbstring \
        php8.2-xml \
        php8.2-zip \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /run/php "$WP_PATH"; \
    chown -R www-data:www-data /run/php "$WP_PATH"

RUN set -eux; \
    curl -fsSL -o /usr/local/bin/wp \
        "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar"; \
    chmod +x /usr/local/bin/wp; \
    wp --version --allow-root

RUN set -eux; \
    curl -fsSL -o /tmp/wordpress.tar.gz \
        "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz"; \
    mkdir -p /usr/src; \
    tar -xzf /tmp/wordpress.tar.gz -C /usr/src; \
    rm -f /tmp/wordpress.tar.gz; \
    chown -R www-data:www-data /usr/src/wordpress

RUN set -eux; \
    sed -ri \
        -e 's|^listen =.*|listen = 0.0.0.0:9000|' \
        /etc/php/8.2/fpm/pool.d/www.conf; \
    sed -ri \
        -e 's|^error_log =.*|error_log = /proc/self/fd/2|' \
        /etc/php/8.2/fpm/php-fpm.conf

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR ${WP_PATH}
EXPOSE 9000
VOLUME ["/var/www/html"]

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
    CMD php-fpm8.2 -t >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm8.2", "-F"]
