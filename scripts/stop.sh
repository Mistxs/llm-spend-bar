#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down
echo "LiteLLM остановлен. Данные Postgres сохранены в volume."
