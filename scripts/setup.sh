#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1; then
  echo "Нужен Docker Desktop / OrbStack: https://www.docker.com/products/docker-desktop/" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker не запущен. Запустите Docker Desktop / OrbStack и повторите." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  umask 077
  MASTER="sk-$(openssl rand -hex 32)"
  SALT="sk-$(openssl rand -hex 32)"
  PGPASS="$(openssl rand -hex 16)"
  cat > .env <<EOF
LITELLM_MASTER_KEY=$MASTER
LITELLM_SALT_KEY=$SALT
POSTGRES_PASSWORD=$PGPASS
LITELLM_PORT=4000
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
OPENROUTER_API_KEY=
DEEPSEEK_API_KEY=
EOF
  echo "==> Создан .env со случайными ключами"
else
  echo "==> .env уже существует, не трогаю"
fi

PORT="$(grep -E '^LITELLM_PORT=' .env | cut -d= -f2- || true)"
PORT="${PORT:-4000}"

echo "==> Запускаю LiteLLM + Postgres (первый запуск может скачать образ)"
docker compose up -d

echo "==> Жду health-check на http://127.0.0.1:${PORT}/health/liveliness"
for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${PORT}/health/liveliness" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:${PORT}/health/liveliness" >/dev/null 2>&1; then
  echo "LiteLLM не поднялся. Логи:" >&2
  docker compose logs --tail=80 litellm >&2 || true
  exit 1
fi

MASTER="$(grep -E '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
echo
echo "==> Готово."
echo "    UI:        http://127.0.0.1:${PORT}/ui  (логин admin, пароль = master key)"
echo "    Master key: ${MASTER}"
echo
echo "Дальше:"
echo "  1. Откройте UI и добавьте модели (Models + Endpoints -> Add Model)."
echo "  2. Запустите приложение: ./build.sh --install"
echo "  3. В настройках приложения вставьте master key выше."
echo
echo "Ключи провайдеров можно положить в .env (OPENAI_API_KEY, ANTHROPIC_API_KEY, ...)"
echo "или добавить прямо в UI."
