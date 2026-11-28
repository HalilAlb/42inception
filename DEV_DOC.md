# Inception — Developer documentation

How to take the repository from a fresh clone to a running stack, and
where to look when you need to change something.

## Prerequisites

A Linux host (the subject mandates a VM; in practice any Debian /
Ubuntu / Fedora that can run modern docker works). On macOS or Windows
the bind-backed volumes won't behave the same way — develop on Linux.

Install:

- `docker` (24.x or newer)
- `docker compose` plugin (v2.20+ — older versions don't honour
  `pull_policy: never` and will try to pull `mariadb:42` from Docker Hub)
- `make`, `git`, `openssl` (for sanity-checking the TLS cert from the
  host)
- `sudo` rights, once, to edit `/etc/hosts`, and for `make clean`
  (container-owned files under `/home/malbayra/data`)

Verify:

```sh
docker --version           # Docker version 24.x or newer
docker compose version     # Docker Compose version v2.20.x or newer
```

## Setup from a fresh clone

```sh
git clone <repo-url> 42inception
cd 42inception

# 1. Tell the host where malbayra.42.fr resolves.
echo "127.0.0.1 malbayra.42.fr" | sudo tee -a /etc/hosts

# 2. Create the secrets. Each file holds a single password; trailing
#    newlines are stripped by the entrypoints. Pick your own values.
mkdir -p secrets
printf '%s' 'pickARootPassword'   > secrets/db_root_password.txt
printf '%s' 'pickADbPassword'     > secrets/db_password.txt
printf '%s' 'pickAnAdminPassword' > secrets/wp_admin_password.txt
printf '%s' 'pickAUserPassword'   > secrets/wp_user_password.txt
chmod 600 secrets/*.txt

# 3. Create srcs/.env (gitignored). Minimal content:
cat > srcs/.env <<'ENV'
DOMAIN_NAME=malbayra.42.fr
CERT_CN=malbayra.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
WP_URL=https://malbayra.42.fr
WP_TITLE=Inception
WP_ADMIN_USER=malbayra
WP_ADMIN_EMAIL=malbayra@malbayra.42.fr
WP_USER=visitor
WP_USER_EMAIL=visitor@malbayra.42.fr
WP_LOCALE=en_US
ENV
#    The admin username MUST NOT contain "admin" or "administrator" in
#    any casing — the WordPress entrypoint refuses to boot if it does.

# 4. Build and start everything.
make
```

`make prep` (called automatically by `make`) creates the two host
data directories:

- `/home/malbayra/data/wordpress` — WP files volume
- `/home/malbayra/data/mariadb` — DB datadir

These paths are the literal `device:` for the `local` driver in
`docker-compose.yml`. Compose will not `mkdir` them for you; if they
don't exist before `up`, you'll see a `mount: no such file or
directory` error.

## Building and launching

Everything goes through `docker compose -f srcs/docker-compose.yml`,
wrapped by the Makefile.

```sh
make            # prep + build + up -d
make up         # build + up -d (skip prep)
make down       # stop and remove containers, keep volumes
make restart    # down + up
make re         # fclean + full rebuild
```

Targeted rebuilds (faster when you're iterating on one service):

```sh
# Rebuild just the wordpress image and recreate the container.
docker compose -f srcs/docker-compose.yml up -d --build wordpress

# Shell into a running container for diagnostics.
docker compose -f srcs/docker-compose.yml exec wordpress bash
```

Compose's `pull_policy: never` is set on every service, so `up` will
never silently pull a stale `mariadb:42` from Docker Hub if the local
image happens to be missing — it builds it instead.

## Managing containers and volumes

```sh
make ps                                            # status snapshot
make logs                                          # follow everything
docker compose -f srcs/docker-compose.yml logs nginx --tail=200   # one service

docker volume ls --filter name=^(db_data|wp_files)$
docker volume inspect wp_files                     # shows the host device path
docker network inspect inception                   # three containers attached
docker exec -it mariadb mariadb -u root -p"$(cat secrets/db_root_password.txt)"
```

Each container exposes only what it has to:

| container   | exposed (host) | internal       |
| ----------- | -------------- | -------------- |
| nginx       | 443            | —              |
| wordpress   | —              | 9000 (FastCGI) |
| mariadb     | —              | 3306           |

`:443` is the only ingress into the infrastructure.

## Where the data lives

Two volumes, both backed by host directories under
`/home/malbayra/data/`. This is the trick the subject is asking
for: declared as docker named volumes (so `docker volume ls` sees
them and `docker compose down -v` removes them) but physically rooted
on the host via the `local` driver's `o: bind`.

| volume     | host path                            | container path   | written by                  |
| ---------- | ------------------------------------ | ---------------- | --------------------------- |
| `db_data`  | `/home/malbayra/data/mariadb`   | `/var/lib/mysql` | mariadb                     |
| `wp_files` | `/home/malbayra/data/wordpress` | `/var/www/html`  | wordpress (rw), nginx (ro)  |

What survives what:

- `docker compose stop` / `docker compose down` / a VM reboot —
  everything persists; the containers come back with
  `restart: unless-stopped` and skip their bootstrap because the data
  is already there.
- `make clean` — wipes the two host data directories. WordPress will
  do a full fresh install on the next `up`.
- Editing a `secrets/*.txt` file — does **not** retroactively change
  passwords already burned into the DB. To pick up new secrets, you
  need a fresh datadir: `make clean && make`.

## How each container starts

- **mariadb** — `tools/entrypoint.sh`: if `/var/lib/mysql/mysql` is
  missing, run `mariadb-install-db`, start a temporary `mariadbd
  --skip-networking` on a unix socket, apply the SQL (root password,
  drop anonymous users, create DB + user from secrets), shut it down;
  then `exec mariadbd --user=mysql`.
- **wordpress** — `tools/entrypoint.sh`: refuse a forbidden admin
  name, wait (bounded) until the DB accepts `wp_user`, copy the
  release from `/usr/src/wordpress` if the volume is empty, `wp config
  create`, `wp core install`, `wp user create`, `chown`; then
  `exec php-fpm8.2 -F`.
- **nginx** — `tools/entrypoint.sh`: generate a self-signed cert into
  `/etc/nginx/ssl` if missing, `nginx -t`; then `exec nginx -g
  'daemon off;'`.

## Troubleshooting

- **`mount: /home/malbayra/data/...: no such file or directory`** —
  you ran `up` directly instead of `make`. Either run `make prep` or
  just `make`.
- **WordPress container stuck in a restart loop, logs say "FATAL:
  WP_ADMIN_USER=... is forbidden"** — `.env` has an admin username
  matching `*admin*`. Change it.
- **`mariadb` healthy but `wordpress` logs "never became reachable"** —
  the `wp_user` password in `secrets/db_password.txt` was changed
  *after* MariaDB first initialised. The DB still has the old hash.
  `make clean && make`.
- **Browser shows "ERR_SSL_PROTOCOL_ERROR"** — usually a stale browser
  TLS cache for the self-signed cert. Hard-reload or test with
  `curl -kI https://malbayra.42.fr/`.
- **`docker compose` warns about `pull_policy` being unknown** —
  your compose plugin is older than v2.20. Upgrade it.

## Layout cheat-sheet

```
srcs/
├── docker-compose.yml      ── orchestration; one place to read what runs where
├── .env                    ── non-secret config (domain, usernames)
└── requirements/
    ├── nginx/
    │   ├── Dockerfile
    │   ├── conf/inception.conf       ── vhost: TLS 1.2/1.3, FastCGI to wordpress
    │   └── tools/entrypoint.sh       ── self-signs the cert on first start
    ├── wordpress/
    │   ├── Dockerfile                ── php-fpm 8.2 + wp-cli + WP release, version-pinned
    │   └── tools/entrypoint.sh       ── installs WP + creates 2 users
    └── mariadb/
        ├── Dockerfile
        ├── conf/inception.cnf        ── overrides 50-server.cnf
        └── tools/entrypoint.sh       ── temp `--skip-networking` bootstrap
```
