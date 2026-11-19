#!/bin/bash
# MariaDB entrypoint. On first start (empty datadir) it initialises the
# system tables, creates the WordPress database + user, sets the root
# password, and removes the anonymous/test rows. On every start it then
# `exec`s mariadbd so the daemon takes PID 1.
#
# Why not `mysqld_safe`? It forks and complicates signal handling. A single
# `exec mariadbd --user=mysql` is the clean way to run a daemon as PID 1.
set -euo pipefail

DATADIR=/var/lib/mysql
INIT_SOCKET=/tmp/mariadb-init.sock

# --- Helpers --------------------------------------------------------------

# Read a docker secret file and strip the trailing newline that text
# editors (and our Write tool) tend to add. wp-cli / mariadb don't like
# a literal \n in passwords.
read_secret() {
    local path="/run/secrets/$1"
    if [[ ! -f "$path" ]]; then
        echo "FATAL: secret '$1' missing at $path" >&2
        exit 1
    fi
    tr -d '\n' < "$path"
}

# --- First-run initialisation --------------------------------------------

if [[ ! -d "$DATADIR/mysql" ]]; then
    echo "[mariadb] empty datadir, initialising…"

    MYSQL_ROOT_PASSWORD=$(read_secret db_root_password)
    MYSQL_PASSWORD=$(read_secret db_password)
    : "${MYSQL_DATABASE:?must be set via .env}"
    : "${MYSQL_USER:?must be set via .env}"

    # Lay down the system tables.
    mariadb-install-db \
        --user=mysql \
        --datadir="$DATADIR" \
        --skip-test-db \
        --auth-root-authentication-method=normal >/dev/null

    # Start a throwaway server with no TCP, just a unix socket, so the
    # init queries can't be reached from outside the container.
    mariadbd --user=mysql \
             --skip-networking \
             --socket="$INIT_SOCKET" \
             --pid-file=/tmp/init.pid &
    pid=$!

    # Wait for the temp instance to accept connections.
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

    # SQL_LOG_BIN=0 keeps the bootstrap statements out of the binlog
    # (defensive — we don't enable binlog, but if a peer enables it later
    # this avoids leaking the root password to a replica).
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

    # Shut the temp instance down cleanly.
    mariadb-admin --socket="$INIT_SOCKET" \
                  -uroot -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait "$pid"

    echo "[mariadb] datadir ready."
else
    echo "[mariadb] datadir already initialised, skipping bootstrap."
fi

# Hand off to the daemon as PID 1.
exec "$@"
