#!/bin/bash
set -euo pipefail

WP_PATH="${WP_PATH:-/var/www/html}"
WP_SRC=/usr/src/wordpress
DB_HOST="${MYSQL_HOST:-mariadb}"

read_secret() {
    local path="/run/secrets/$1"
    if [[ ! -f "$path" ]]; then
        echo "FATAL: secret '$1' missing at $path" >&2
        exit 1
    fi
    tr -d '\n' < "$path"
}

: "${MYSQL_DATABASE:?must be set via .env}"
: "${MYSQL_USER:?must be set via .env}"
: "${WP_URL:?must be set via .env}"
: "${WP_TITLE:?must be set via .env}"
: "${WP_ADMIN_USER:?must be set via .env}"
: "${WP_ADMIN_EMAIL:?must be set via .env}"
: "${WP_USER:?must be set via .env}"
: "${WP_USER_EMAIL:?must be set via .env}"

if [[ "${WP_ADMIN_USER,,}" == *admin* ]]; then
    echo "FATAL: WP_ADMIN_USER='${WP_ADMIN_USER}' is forbidden by the subject (contains 'admin')" >&2
    exit 1
fi

DB_PASSWORD=$(read_secret db_password)
WP_ADMIN_PASSWORD=$(read_secret wp_admin_password)
WP_USER_PASSWORD=$(read_secret wp_user_password)

echo "[wordpress] waiting for mariadb at ${DB_HOST}:3306…"
ready=0
for _ in $(seq 1 60); do
    if mariadb --host="$DB_HOST" --user="$MYSQL_USER" --password="$DB_PASSWORD" \
               --skip-ssl "$MYSQL_DATABASE" -e 'SELECT 1' >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [[ "$ready" -ne 1 ]]; then
    echo "FATAL: mariadb never became reachable with the configured credentials" >&2
    exit 1
fi
echo "[wordpress] mariadb is up."

cd "$WP_PATH"

if [[ ! -f "$WP_PATH/wp-load.php" ]]; then
    echo "[wordpress] empty volume, copying WordPress ${WP_VERSION} into ${WP_PATH}"
    cp -a "$WP_SRC/." "$WP_PATH/"
fi

if [[ ! -f "$WP_PATH/wp-config.php" ]]; then
    echo "[wordpress] generating wp-config.php"
    wp config create --allow-root \
        --dbname="$MYSQL_DATABASE" \
        --dbuser="$MYSQL_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="$DB_HOST" \
        --dbcharset="utf8mb4" \
        --skip-check
fi

if ! wp core is-installed --allow-root >/dev/null 2>&1; then
    echo "[wordpress] installing site '${WP_TITLE}' at ${WP_URL}"
    wp core install --allow-root \
        --url="$WP_URL" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email
fi

if ! wp user get "$WP_USER" --allow-root >/dev/null 2>&1; then
    echo "[wordpress] creating user '${WP_USER}' (role: author)"
    wp user create --allow-root \
        "$WP_USER" "$WP_USER_EMAIL" \
        --role=author \
        --user_pass="$WP_USER_PASSWORD"
fi

chown -R www-data:www-data "$WP_PATH"

echo "[wordpress] setup done, starting php-fpm."

exec "$@"
