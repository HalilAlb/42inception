#!/bin/bash
# WordPress entrypoint. On first start (empty volume) it copies the
# pinned WordPress release into /var/www/html, writes wp-config.php,
# installs the site and creates the two required users with wp-cli.
# On every start it then `exec`s php-fpm so the daemon takes PID 1.
#
# Nothing here loops forever: the DB wait is bounded (60 tries) and the
# script either finishes the one-shot setup or exits non-zero, in which
# case `restart: unless-stopped` brings the container back to retry.
set -euo pipefail

WP_PATH="${WP_PATH:-/var/www/html}"
WP_SRC=/usr/src/wordpress
DB_HOST="${MYSQL_HOST:-mariadb}"

# --- Helpers --------------------------------------------------------------

# Read a docker secret file and strip the trailing newline that text
# editors tend to add — wp-cli and mariadb would treat it as part of the
# password.
read_secret() {
    local path="/run/secrets/$1"
    if [[ ! -f "$path" ]]; then
        echo "FATAL: secret '$1' missing at $path" >&2
        exit 1
    fi
    tr -d '\n' < "$path"
}

# --- Config sanity --------------------------------------------------------

: "${MYSQL_DATABASE:?must be set via .env}"
: "${MYSQL_USER:?must be set via .env}"
: "${WP_URL:?must be set via .env}"
: "${WP_TITLE:?must be set via .env}"
: "${WP_ADMIN_USER:?must be set via .env}"
: "${WP_ADMIN_EMAIL:?must be set via .env}"
: "${WP_USER:?must be set via .env}"
: "${WP_USER_EMAIL:?must be set via .env}"

# Subject: the administrator's login must not contain "admin" or
# "administrator" in any casing ("administrator" contains "admin", so a
# single case-insensitive test covers both).
if [[ "${WP_ADMIN_USER,,}" == *admin* ]]; then
    echo "FATAL: WP_ADMIN_USER='${WP_ADMIN_USER}' is forbidden by the subject (contains 'admin')" >&2
    exit 1
fi

DB_PASSWORD=$(read_secret db_password)
WP_ADMIN_PASSWORD=$(read_secret wp_admin_password)
WP_USER_PASSWORD=$(read_secret wp_user_password)

# --- Wait for MariaDB -----------------------------------------------------
# compose's depends_on + healthcheck already gates us on the port being
# open; this double-checks that our *credentials* work before wp-cli
# tries to use them. Bounded loop: 60 x 2s = 2 minutes max.

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

# --- First-run installation -----------------------------------------------

cd "$WP_PATH"

# 1. WordPress files. The volume is empty on a fresh `make`; copy the
#    release that was downloaded at image build time.
if [[ ! -f "$WP_PATH/wp-load.php" ]]; then
    echo "[wordpress] empty volume, copying WordPress ${WP_VERSION} into ${WP_PATH}"
    cp -a "$WP_SRC/." "$WP_PATH/"
fi

# 2. wp-config.php — DB credentials + fresh salts. The DB password is
#    passed on the command line to wp-cli, which writes it into the
#    file inside the volume; it never lands in the image or the env.
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

# 3. Site install + administrator (user #1).
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

# 4. Second user (subject requires exactly two users in the DB).
if ! wp user get "$WP_USER" --allow-root >/dev/null 2>&1; then
    echo "[wordpress] creating user '${WP_USER}' (role: author)"
    wp user create --allow-root \
        "$WP_USER" "$WP_USER_EMAIL" \
        --role=author \
        --user_pass="$WP_USER_PASSWORD"
fi

# php-fpm workers run as www-data; make sure everything we just wrote
# (as root) is theirs so uploads/updates work from the admin panel.
chown -R www-data:www-data "$WP_PATH"

echo "[wordpress] setup done, starting php-fpm."

# Hand off to the daemon as PID 1.
exec "$@"
