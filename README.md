*This project has been created as part of the 42 curriculum by malbayra.*

# Inception

A small WordPress stack running in containers on a single VM. Three
services — NGINX, WordPress (php-fpm), MariaDB — wired together with
`docker compose` and a top-level `Makefile`. Everything is built from a
Debian Bookworm base; nothing is pulled ready-made from Docker Hub
except the OS image itself.

## Description

The brief is short and the rules are strict, so most of the work is in
reading the rules carefully and not cutting corners. The interesting
parts of the project, for me, were:

- Writing entrypoints that actually behave like daemons. PID 1 has to
  receive signals so `docker stop` does the right thing, which means
  no `tail -f` shims, no detached `mysqld_safe`, and `exec` at the end
  of every entrypoint script.
- Getting MariaDB to do a one-shot first-run bootstrap from secret
  files, without leaving the temporary socket reachable from outside
  the container during init.
- Persuading WordPress to install non-interactively from `wp-cli` while
  reading credentials from `/run/secrets/*` rather than environment
  variables.

The whole stack lives behind a single TLS-terminating nginx on `:443`
(self-signed, TLSv1.2 / 1.3 only). NGINX speaks FastCGI to WordPress on
`:9000`, and WordPress talks to MariaDB on `:3306`. Nothing on the host
sees the database or the php-fpm pool directly.

```
host:443 ──TLS──▶ nginx ──fastcgi:9000──▶ wordpress (php-fpm) ──mysql:3306──▶ mariadb
                    │                          │                                 │
                    └── reads (ro) ── wp_files ◀── writes ──┘            db_data ◀─┘
```

## Instructions

You need a Linux host (a VM is fine — that's what the subject asks
for) with `docker` and `docker compose` installed, and you need to
hold `sudo` for one step: adding the domain to `/etc/hosts`.

```sh
# one-time prep
echo "127.0.0.1 malbayra.42.fr" | sudo tee -a /etc/hosts

# build & launch the whole stack
make
```

That's it. After about 30 seconds the WordPress site is at
<https://malbayra.42.fr/> (browser will warn about the self-signed
cert — accept it). The admin login goes to
<https://malbayra.42.fr/wp-admin/>; credentials are mirrored in
`secrets/credentials.txt` for the defense.

Useful Makefile targets:

| target        | what it does                                                      |
| ------------- | ----------------------------------------------------------------- |
| `make`        | create host data dirs, build, start (default)                     |
| `make down`   | stop and remove containers; volumes are kept                      |
| `make clean`  | `down` + drop volumes + wipe `/home/malbayra/data/`          |
| `make fclean` | `clean` + `docker system prune -af --volumes`                     |
| `make re`     | `fclean` then full rebuild                                        |
| `make logs`   | follow logs from every service                                    |

`USER_DOC.md` covers day-to-day operation; `DEV_DOC.md` covers setting
the project up from a fresh clone.

## Layout

```
.
├── Makefile
├── README.md  USER_DOC.md  DEV_DOC.md
├── secrets/                       # password-per-file, gitignored
└── srcs/
    ├── .env                       # non-secret config, gitignored
    ├── docker-compose.yml
    └── requirements/
        ├── nginx/      { Dockerfile, conf/inception.conf, tools/entrypoint.sh }
        ├── wordpress/  { Dockerfile, tools/entrypoint.sh }
        └── mariadb/    { Dockerfile, conf/inception.cnf,  tools/entrypoint.sh }
```

Every service directory follows the same shape: `Dockerfile`,
`conf/<file>` for any config that gets copied in, and `tools/` for
the shell entrypoint.

## Project description

### How Docker is used here

Each service is its own image, built from `debian:bookworm-slim` by a
Dockerfile I wrote; the package (nginx, php-fpm, mariadb-server) is
installed with `apt` inside that Dockerfile. `docker-compose.yml`
declares the three services, one user-defined bridge network, two
named volumes and four secrets; the `Makefile` is a thin wrapper that
creates the host data directories and calls `docker compose`.

Main design choices:

- **One process per container, running as PID 1.** Every entrypoint
  does its one-shot setup and then `exec`s the real daemon
  (`nginx -g 'daemon off;'`, `php-fpm8.2 -F`, `mariadbd`).
- **Setup is idempotent.** MariaDB only bootstraps when its datadir is
  empty; WordPress only installs when the volume has no `wp-load.php`.
  Restarting a container never re-runs a destructive step.
- **The WordPress release and wp-cli are downloaded at build time**,
  version-pinned, so the containers need no internet access at runtime.
- **Passwords never touch an image or an env var.** They are read from
  `/run/secrets/<name>` by the entrypoints.
- **Startup order is enforced by a healthcheck**, not by sleeps:
  `wordpress` waits for `mariadb` to report healthy, then additionally
  verifies its own credentials in a bounded loop before running wp-cli.

### Virtual Machines vs Docker

A VM gives you a full OS-level boundary — kernel and all — which is
great for hostile multi-tenant isolation and terrible for spinning up
several services on a laptop. Each service would need its own guest
kernel, init system and memory budget.

Docker containers share the host kernel, so they start in
milliseconds, weigh tens of MB instead of hundreds, and can be torn
down and rebuilt on every push. The trade-off is a weaker isolation
boundary (a kernel exploit hops between containers; it doesn't hop
between VMs), so containers are for *deployment*, not for *running
untrusted code*.

For this project, the right mental model is: one VM (the host the
subject mandates) holding three cooperating processes that happen to
be packaged as containers.

### Secrets vs Environment Variables

Both end up as data inside the container; the difference is who can
read them and where they live on disk.

Environment variables are visible to anyone who runs `docker inspect`
on the container, anyone with read access to the compose file, any
child process via `/proc/<pid>/environ`, and they end up in container
log lines if a misbehaving program prints its environment. Fine for a
domain name. Bad for a database password.

Docker secrets are tmpfs-mounted at `/run/secrets/<name>` inside the
container, sourced from a file on the host. They never appear in
`docker inspect`, they never enter the container env, and the host
file can be kept out of git. In this project, every password (DB root,
WP DB user, WP admin, WP second user) lives in a separate
`secrets/*.txt` file; the only things in `.env` are the domain, the
DB name and usernames — everything you'd be willing to commit if
`.env` weren't gitignored anyway.

### Docker Network vs Host Network

`network: host` collapses the container's network namespace into the
host's. The container's services bind directly on the host's
interfaces — there's no NAT, no port mapping, no DNS-by-service-name.
Faster (no network namespace overhead), but every service has to pick
a unique port on the host, port conflicts become real, and you've
basically given up the abstraction.

A user-defined bridge network (which this project uses, named
`inception`) puts every container on a private subnet and gives you
DNS resolution by service name: `wordpress` resolves to the WP
container's IP from inside nginx. The host only sees what you
explicitly publish with `ports:`. nginx publishes `:443`; MariaDB and
php-fpm stay completely off the host network — they're only reachable
from inside the bridge. That's the security win.

### Docker Volumes vs Bind Mounts

A bind mount is a path on the host directly exposed as a path in the
container. Convenient for development (edit a file on the host, the
container sees the change instantly), but the lifecycle is entirely
yours — Docker doesn't manage it, and you have to remember to copy /
back up / clean up the host path yourself.

A named volume is Docker-managed: Docker owns the path, knows its
lifecycle, and exposes it via `docker volume` commands. You can list
it, inspect it, prune it.

The subject pins the two required volumes (WP files, MariaDB datadir)
to `/home/malbayra/data/` on the host, which sounds like a bind
mount. The trick the subject is asking for is the `local` driver with
`type: none, o: bind, device: …`: it's *declared* as a named volume
in compose, so `docker volume ls` shows it and `make clean` can drop
it via `down -v`, but it's *physically* backed by a host directory we
control. Best of both: managed lifecycle, predictable host location.

## Resources

References I actually leaned on, in roughly decreasing order of usefulness:

- [Docker docs — Compose specification](https://docs.docker.com/compose/compose-file/)
  for `pull_policy`, `depends_on: condition: service_healthy`,
  secrets and the `local` volume driver options.
- [Docker docs — Dockerfile best practices](https://docs.docker.com/build/building/best-practices/)
  for single-RUN layers, `ENTRYPOINT` + `CMD`, and PID 1 behaviour.
- [nginx pitfalls and good practices](https://www.nginx.com/resources/wiki/start/topics/tutorials/config_pitfalls/)
  for the `try_files` + `fastcgi_pass` pattern.
- [WordPress — `wp-cli` core install](https://developer.wordpress.org/cli/commands/core/install/)
  for the non-interactive setup arguments.
- The MariaDB official Docker image entrypoint
  ([`docker-entrypoint.sh`](https://github.com/MariaDB/mariadb-docker))
  as a reference for the bootstrap dance, especially `--skip-networking`
  during init.

### Use of AI

I used Claude as a pair-programmer for two things specifically:

1. Drafting the MariaDB bootstrap SQL and the WordPress entrypoint
   skeleton. The structure and order of operations (init datadir →
   temp `--skip-networking` instance → grant queries → clean shutdown;
   copy release → `wp config create` → `wp core install` → second
   user) came from a conversation; I checked each step against the
   MariaDB / wp-cli docs and the official image's reference entrypoint
   before keeping it.
2. Writing the per-comparison paragraphs above (VM vs Docker, etc.).
   I wrote the structure and the framing, asked for a second pass on
   wording, and edited the result down.

The Dockerfiles, the nginx vhost and the compose file were written and
debugged by hand so I can defend them line by line.
