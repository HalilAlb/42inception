FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="inception-mariadb" \
      org.opencontainers.image.source="https://github.com/HalilAlb/42inception" \
      org.opencontainers.image.description="MariaDB 10.11 on Debian 12 for the 42 Inception project"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mariadb-server \
        mariadb-client \
        ca-certificates \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/run/mysqld; \
    chown -R mysql:mysql /var/run/mysqld /var/lib/mysql

COPY conf/inception.cnf       /etc/mysql/mariadb.conf.d/99-inception.cnf
COPY tools/entrypoint.sh      /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3306
VOLUME ["/var/lib/mysql"]

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
    CMD bash -c ':> /dev/tcp/localhost/3306' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mariadbd", "--user=mysql"]
