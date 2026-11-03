#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="$(grep -E '^LITELLM_PORT=' .env 2>/dev/null | cut -d= -f2- || true)"
PORT="${PORT:-4000}"
MASTER="$(grep -E '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
MODEL="${1:-}"

if [[ -z "$MODEL" ]]; then
  echo "Использование: $0 <model-name>" >&2
  echo "Список моделей: curl -s http://127.0.0.1:${PORT}/v1/models -H 'Authorization: Bearer \$MASTER'" >&2
  exit 1
fi

curl -sS "http://127.0.0.1:${PORT}/v1/chat/completions" \
  -H "Authorization: Bearer ${MASTER}" \
  -H 'Content-Type: application/json' \
  -H 'x-litellm-trace-id: test-session-'"$(date +%s)" \
  -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in five words.\"}],\"max_tokens\":32}" \
  | python3 -m json.tool
