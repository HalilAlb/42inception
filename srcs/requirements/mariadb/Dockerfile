# syntax=docker/dockerfile:1
# MariaDB — service container for the WordPress database.
# Debian bookworm-slim ships MariaDB 10.11 (LTS), which is the penultimate
# stable Debian's blessed version. We don't pull any DB image, only the OS.

FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="inception-mariadb" \
      org.opencontainers.image.source="https://github.com/halilalbayrak/42inception" \
      org.opencontainers.image.description="MariaDB 10.11 on Debian 12 for the 42 Inception project"

# --- Install --------------------------------------------------------------
# Single RUN layer, no recommends, apt lists wiped — keeps the image small
# and reproducible-ish for the lifetime of bookworm.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mariadb-server \
        mariadb-client \
        ca-certificates \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    # Runtime dirs that the package post-install doesn't always create
    # when the image is rebuilt cold.
    mkdir -p /var/run/mysqld; \
    chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

# --- Config & entrypoint --------------------------------------------------
COPY conf/inception.cnf       /etc/mysql/mariadb.conf.d/99-inception.cnf
COPY tools/entrypoint.sh      /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3306
VOLUME ["/var/lib/mysql"]

# Healthcheck lets compose's `depends_on: condition: service_healthy` work
# for the wordpress entrypoint, so WP doesn't race the DB on cold start.
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
    CMD bash -c ':> /dev/tcp/localhost/3306' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# `mariadbd --user=mysql` becomes PID 1 via `exec` in the entrypoint, so
# signals (SIGTERM from `docker stop`) reach the daemon directly.
CMD ["mariadbd", "--user=mysql"]
