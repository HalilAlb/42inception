LOGIN         := malbayra
DATA_DIR      := /home/$(LOGIN)/data
WP_VOLUME     := $(DATA_DIR)/wordpress
DB_VOLUME     := $(DATA_DIR)/mariadb

COMPOSE_FILE  := srcs/docker-compose.yml
COMPOSE       := docker compose -f $(COMPOSE_FILE)

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

.PHONY: prep
prep:
	@mkdir -p $(WP_VOLUME) $(DB_VOLUME)

.PHONY: ps
ps:
	@$(COMPOSE) ps

.PHONY: logs
logs:
	@$(COMPOSE) logs -f --tail=100

.PHONY: images
images:
	@$(COMPOSE) images

.PHONY: clean
clean:
	@$(COMPOSE) down -v --remove-orphans
	@sudo rm -rf $(WP_VOLUME) $(DB_VOLUME)

.PHONY: fclean
fclean: clean
	@docker system prune -af --volumes

.PHONY: re
re: fclean all

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
