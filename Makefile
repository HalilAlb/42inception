# ---- Inception ---------------------------------------------------------------
# All container orchestration goes through `docker compose`. This Makefile is a
# thin wrapper that adds host-side prerequisites (data dirs) and convenience
# targets. Targets are .PHONY because they don't produce files at these names.

LOGIN         := malbayra
DATA_DIR      := /home/$(LOGIN)/data
WP_VOLUME     := $(DATA_DIR)/wordpress
DB_VOLUME     := $(DATA_DIR)/mariadb

COMPOSE_FILE  := srcs/docker-compose.yml
COMPOSE       := docker compose -f $(COMPOSE_FILE)

# ---- High-level --------------------------------------------------------------

.PHONY: all
all: prep up

.PHONY: up
up:
	@$(COMPOSE) up -d --build

.PHONY: down
down:
	@$(COMPOSE) down

.PHONY: stop
stop:
	@$(COMPOSE) stop

.PHONY: restart
restart: down up

# ---- Host preparation --------------------------------------------------------
# Named volumes back onto these host directories via the `local` driver with
# `o: bind`. They must exist before `up` or compose errors out.

.PHONY: prep
prep:
	@mkdir -p $(WP_VOLUME) $(DB_VOLUME)

# ---- Inspection --------------------------------------------------------------

.PHONY: ps
ps:
	@$(COMPOSE) ps

.PHONY: logs
logs:
	@$(COMPOSE) logs -f --tail=100

.PHONY: images
images:
	@$(COMPOSE) images

# ---- Cleanup -----------------------------------------------------------------
# clean : stop containers and remove volumes (host data dirs are wiped too,
#         otherwise mariadb refuses to re-init on top of an existing datadir).
# fclean: also drop every dangling image/network/volume on the host.
# re    : full rebuild from a clean slate.

.PHONY: clean
clean:
	@$(COMPOSE) down -v --remove-orphans
	@# sudo is needed: files inside the host bind dirs are owned by the
	@# container users (mysql, www-data) — not the host user — so a plain
	@# rm fails on restricted subdirs (e.g. mariadb's mysql/ schema dir).
	@sudo rm -rf $(WP_VOLUME) $(DB_VOLUME)

.PHONY: fclean
fclean: clean
	@docker system prune -af --volumes

.PHONY: re
re: fclean all

# ---- Help --------------------------------------------------------------------

.PHONY: help
help:
	@echo "Inception — common targets:"
	@echo "  make            build & start the whole stack (default)"
	@echo "  make down       stop and remove containers (volumes kept)"
	@echo "  make clean      down + wipe volumes and host data dirs"
	@echo "  make fclean     clean + docker system prune"
	@echo "  make re         fclean + rebuild from scratch"
	@echo "  make logs       follow logs from every service"
	@echo "  make ps         show container status"
