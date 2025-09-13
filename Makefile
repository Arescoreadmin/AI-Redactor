.PHONY: up down logs seed
up:
	cd infra && docker compose --env-file .env up -d --build
down:
	cd infra && docker compose --env-file .env down -v
logs:
	cd infra && docker compose logs -f --tail=200
seed:
	ENV_FILE=infra/.env python3 scripts/load_fixtures.py
