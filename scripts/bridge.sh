#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# LiteLLM master key and port live in .env (created by scripts/setup.sh).
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# Optional bridge-only settings. Keep this file out of git.
if [[ -f .bridge.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .bridge.env
  set +a
fi

if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  echo "LITELLM_MASTER_KEY не задан. Запустите ./scripts/setup.sh или добавьте ключ в .env." >&2
  exit 1
fi

if [[ -z "${TOKEN_MONITOR_SECRET:-}" ]]; then
  echo "TOKEN_MONITOR_SECRET не задан." >&2
  echo "Скопируйте секрет из Token Monitor → Settings → Multi-device Sync и положите в .bridge.env:" >&2
  echo "  TOKEN_MONITOR_HUB_URL=http://127.0.0.1:17321" >&2
  echo "  TOKEN_MONITOR_SECRET=..." >&2
  exit 1
fi

case "${1:-}" in
  --once)
    shift
    exec python3 bridge/litellm_bridge.py --once "$@"
    ;;
  --stats)
    shift
    exec python3 bridge/litellm_bridge.py --print-stats "$@"
    ;;
  *)
    exec python3 bridge/litellm_bridge.py --loop "$@"
    ;;
esac
