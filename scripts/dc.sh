#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec docker compose -p infra \
  -f "$root/infra/docker-compose.yml" \
  --env-file "$root/infra/.env" "$@"
