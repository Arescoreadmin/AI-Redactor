#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cp -n infra/.env.example infra/.env || true
echo "Bootstrap complete. Use: cd infra && docker compose --env-file .env up -d --build"
