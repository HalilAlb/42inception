#!/bin/bash
set -euo pipefail

DATADIR=/var/lib/mysql
INIT_SOCKET=/tmp/mariadb-init.sock

read_secret() {
    local path="/run/secrets/$1"
    if [[ ! -f "$path" ]]; then
        echo "FATAL: secret '$1' missing at $path" >&2
        exit 1
    fi
    tr -d '\n' < "$path"
}

MARKER="$DATADIR/.inception_initialised"

mkdir -p /var/run/mysqld "$DATADIR"
chown -R mysql:mysql /var/run/mysqld "$DATADIR"

if [[ ! -f "$MARKER" && -n "${MYSQL_DATABASE:-}" && -d "$DATADIR/$MYSQL_DATABASE" ]]; then
    touch "$MARKER"
fi

if [[ ! -f "$MARKER" ]]; then
    echo "[mariadb] datadir not initialised, bootstrapping…"

    find "$DATADIR" -mindepth 1 -delete

    MYSQL_ROOT_PASSWORD=$(read_secret db_root_password)
    MYSQL_PASSWORD=$(read_secret db_password)
    : "${MYSQL_DATABASE:?must be set via .env}"
    : "${MYSQL_USER:?must be set via .env}"

    mariadb-install-db \
        --user=mysql \
        --datadir="$DATADIR" \
        --skip-test-db \
        --auth-root-authentication-method=normal >/dev/null

    mariadbd --user=mysql \
             --skip-networking \
             --socket="$INIT_SOCKET" \
             --pid-file=/tmp/init.pid &
    pid=$!

    for _ in {1..30}; do
        if mariadb-admin --socket="$INIT_SOCKET" ping >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    if ! mariadb-admin --socket="$INIT_SOCKET" ping >/dev/null 2>&1; then
        echo "FATAL: temp mariadbd never came up" >&2
        exit 1
    fi

    mariadb --socket="$INIT_SOCKET" <<-SQL
        SET @@SESSION.SQL_LOG_BIN = 0;

        ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
        DELETE FROM mysql.global_priv WHERE User = '';
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db = 'test' OR Db = 'test\\_%';

        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`
            CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';

        FLUSH PRIVILEGES;
SQL

    mariadb-admin --socket="$INIT_SOCKET" \
                  -uroot -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait "$pid"

    touch "$MARKER"
    chown mysql:mysql "$MARKER"
    echo "[mariadb] datadir ready."
else
    echo "[mariadb] datadir already initialised, skipping bootstrap."
fi

exec "$@"
