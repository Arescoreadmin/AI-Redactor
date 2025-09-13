SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(CURDIR)
DC := docker compose --env-file infra/.env -f infra/docker-compose.yml

JOBS ?= doc audio video
JOB  ?= doc

HEALTH_TIMEOUT ?= 120
TIMEOUT        ?= 120
AUTO_UP        ?= 1

.PHONY: smoke smoke-% smoke-all up down down-v ps logs

smoke:
	@echo "==> smoke $(JOB)"
	AUTO_UP=$(AUTO_UP) HEALTH_TIMEOUT=$(HEALTH_TIMEOUT) TIMEOUT=$(TIMEOUT) JOB_TYPE=$(JOB) bash ./scripts/smoke.sh

smoke-%:
	@echo "==> smoke $*"
	AUTO_UP=$(AUTO_UP) HEALTH_TIMEOUT=$(HEALTH_TIMEOUT) TIMEOUT=$(TIMEOUT) JOB_TYPE=$* bash ./scripts/smoke.sh

smoke-all:
	@rc=0; for j in $(JOBS); do \
	  echo ""; echo "===== $$j ====="; \
	  AUTO_UP=$(AUTO_UP) HEALTH_TIMEOUT=$(HEALTH_TIMEOUT) TIMEOUT=$(TIMEOUT) JOB_TYPE=$$j bash ./scripts/smoke.sh || rc=1; \
	done; exit $$rc

up:
	$(DC) up -d

down:
	$(DC) down

down-v:
	$(DC) down -v

ps:
	$(DC) ps

logs:
	$(DC) logs --tail=${TAIL:-200} $(SVC)
