# Inception — User documentation

This document is written for someone who wants to *use* the stack, not
modify it. It explains what is running, how to turn it on and off,
how to reach the site, and where the passwords live.

## What the stack provides

After `make`, three containers are running on the host.

| service     | role                               | reachable from host                      |
| ----------- | ---------------------------------- | ---------------------------------------- |
| `nginx`     | TLS-terminating reverse proxy      | `https://malbayra.42.fr` (port 443) |
| `wordpress` | php-fpm worker, the WordPress site | only via nginx                           |
| `mariadb`   | database for WordPress             | only from other containers               |

Only nginx is reachable from outside; the other two live exclusively
on the private `inception` docker network.

## Starting and stopping

Both happen from the repository root.

```sh
# start everything (builds images on first run)
make

# stop everything; volumes and host data are kept
make down

# stop and wipe all persistent data (DB + WP files)
make clean

# scorched earth: clean + prune every dangling docker object
make fclean
```

`make` is idempotent — running it again on an already-running stack is
a no-op. If you change a Dockerfile, `make re` rebuilds from scratch.

## Reaching the site and the admin panel

The hostname `malbayra.42.fr` has to resolve to the host running
the stack. On the same machine as the containers, the one-time setup is:

```sh
echo "127.0.0.1 malbayra.42.fr" | sudo tee -a /etc/hosts
```

Once that's in place:

- **WordPress site** — <https://malbayra.42.fr/>
- **WordPress admin panel** — <https://malbayra.42.fr/wp-admin/>
  Log in with the administrator account (see below).

The TLS cert is self-signed; the browser will ask you to confirm the
exception on first visit. That's expected. Plain `http://` and any
port other than 443 are deliberately not served.

## Where the credentials live

Two places, and they have to agree.

1. **`secrets/*.txt`** — one password per file. These are mounted into
   the containers as docker secrets at `/run/secrets/<name>`. They
   are gitignored. If you change one, you have to `make clean && make`
   for the database and WordPress to re-bootstrap with the new value —
   both only read them on first init.
2. **`secrets/credentials.txt`** — a plain human-readable summary of
   the two WordPress users. Mirrors the per-file secrets. This is the
   file to glance at when someone asks "what's the WP admin password"
   during defense.

| credential                 | file                            |
| -------------------------- | ------------------------------- |
| MariaDB root               | `secrets/db_root_password.txt`  |
| MariaDB `wp_user`          | `secrets/db_password.txt`       |
| WP admin (`malbayra`)    | `secrets/wp_admin_password.txt` |
| WP second user (`visitor`) | `secrets/wp_user_password.txt`  |

Non-secret config (domain, usernames, DB name, site title) is in
`srcs/.env`. To change the admin username, edit `WP_ADMIN_USER` there —
it must not contain "admin" or "administrator" in any casing, the
WordPress container refuses to start otherwise.

## Checking that everything is healthy

```sh
make ps          # docker compose ps — every service should say "Up" / "healthy"
make logs        # follow all logs; ctrl+C to stop
```

Quick TLS sanity check:

```sh
curl -kI https://malbayra.42.fr/
# expect: HTTP/2 200 (or 301/302 if WordPress redirects)
```

Quick "TLS 1.1 must be refused" check (the subject explicitly forbids
older protocols):

```sh
openssl s_client -connect malbayra.42.fr:443 -tls1_1 </dev/null
# expect: handshake failure / no protocols available
```

Database reachable and populated:

```sh
docker exec -it mariadb mariadb -u root -p"$(cat secrets/db_root_password.txt)" \
    -e "SELECT user_login FROM wordpress.wp_users;"
# expect: malbayra and visitor
```

If any container is in a restart loop, `docker logs <name>` is the
quickest way to see why. Common first-time culprits are:

- `/home/malbayra/data/{wordpress,mariadb}` doesn't exist —
  `make prep` (or `make`) creates them.
- `/etc/hosts` not updated — the site loads but the browser shows the
  wrong cert, or WordPress redirects to a hostname that doesn't resolve.
- A previous run left a half-initialised MariaDB datadir — `make
  clean` and start over.
