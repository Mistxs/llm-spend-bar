#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose up -d
PORT="$(grep -E '^LITELLM_PORT=' .env 2>/dev/null | cut -d= -f2- || true)"
PORT="${PORT:-4000}"
echo "LiteLLM: http://127.0.0.1:${PORT}/ui"
