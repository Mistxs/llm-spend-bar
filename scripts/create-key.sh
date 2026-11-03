#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="$(grep -E '^LITELLM_PORT=' .env 2>/dev/null | cut -d= -f2- || true)"
PORT="${PORT:-4000}"
MASTER="$(grep -E '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
ALIAS="${1:-llm-spend-bar}"

echo "==> Создаю virtual key с alias '$ALIAS'"
RESPONSE="$(curl -fsS -X POST "http://127.0.0.1:${PORT}/key/generate" \
  -H "Authorization: Bearer ${MASTER}" \
  -H 'Content-Type: application/json' \
  -d "{\"key_alias\":\"${ALIAS}\",\"models\":[]}")"

python3 - "$RESPONSE" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
key = payload.get("key") or payload.get("token")
if not key:
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    raise SystemExit("Не удалось найти key в ответе")
print(key)
PY

echo
echo "Используйте этот ключ как OPENAI_API_KEY / ANTHROPIC_AUTH_TOKEN для агентов."
echo "Master key нужен только приложению LLM Spend Bar для чтения spend logs."
