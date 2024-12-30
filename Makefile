COMPOSE_DIR = deploy/docker-compose
COMPOSE_FILE_NAME = docker-compose.yaml
COMPOSE_PATH = $(COMPOSE_DIR)/$(COMPOSE_FILE_NAME)
SRC_DIR = ./src
BUILD_DIR = $(COMPOSE_DIR)/_build

docker_compose_up:
	@if [ ! -e "$(COMPOSE_PATH)" ]; then \
		cp $(COMPOSE_PATH).example $(COMPOSE_PATH) ; \
		echo "Created $(COMPOSE_PATH) out of template." ; fi
	mkdir -p $(BUILD_DIR)
	rsync -avz $(SRC_DIR) $(BUILD_DIR)
	cd $(COMPOSE_DIR) ; docker compose -f $(COMPOSE_FILE_NAME) up --build --detach

docker_compose_ps:
	docker compose -f $(COMPOSE_PATH) ps

docker_compose_down:
	cd $(COMPOSE_DIR) ; docker compose -f $(COMPOSE_FILE_NAME) down
