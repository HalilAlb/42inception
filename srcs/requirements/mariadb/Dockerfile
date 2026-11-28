FROM debian:bookworm-slim

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
    CMD bash -c ':> /dev/tcp/127.0.0.1/3306' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mariadbd", "--user=mysql"]
