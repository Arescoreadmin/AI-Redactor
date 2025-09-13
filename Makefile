SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(CURDIR)
DC   := docker compose --env-file $(ROOT)/infra/.env -f $(ROOT)/infra/docker-compose.yml

JOBS ?= doc audio video
JOB  ?= doc

HEALTH_TIMEOUT ?= 120
TIMEOUT        ?= 120
AUTO_UP        ?= 1
TAIL          ?= 200
SVC           ?=

# default goal shows a help menu
.DEFAULT_GOAL := help

.PHONY: help smoke smoke-% smoke-all up down down-v ps logs

help: ## Show available targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*##/{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

smoke: ## Run smoke for JOB (default: doc)
	@echo "==> smoke $(JOB)"
	AUTO_UP=$(AUTO_UP) HEALTH_TIMEOUT=$(HEALTH_TIMEOUT) TIMEOUT=$(TIMEOUT) JOB_TYPE=$(JOB) bash ./scripts/smoke.sh

smoke-%: ## Run smoke for a specific job type (doc|audio|video)
	@echo "==> smoke $*"
	AUTO_UP=$(AUTO_UP) HEALTH_TIMEOUT=$(HEALTH_TIMEOUT) TIMEOUT=$(TIMEOUT) JOB_TYPE=$* bash ./scripts/smoke.sh

smoke-all: ## Run smoke for doc, audio, video
	@rc=0; for j in $(JOBS); do \
	  echo ""; echo "===== $$j ====="; \
	  AUTO_UP=$(AUTO_UP) HEALTH_TIMEOUT=$(HEALTH_TIMEOUT) TIMEOUT=$(TIMEOUT) JOB_TYPE=$$j bash ./scripts/smoke.sh || rc=1; \
	done; exit $$rc

up: ## docker compose up -d
	$(DC) up -d

down: ## docker compose down
	$(DC) down

down-v: ## docker compose down -v (wipe volumes)
	$(DC) down -v

ps: ## docker compose ps
	$(DC) ps

logs: ## docker compose logs (env: SVC=api_gateway, TAIL=200)
	$(DC) logs --tail=$(TAIL) $(SVC)
