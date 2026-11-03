# Token Monitor + LiteLLM: все агенты и подписки в одном окне

LiteLLM видит только API-трафик. Claude Code, Codex, Cursor, Copilot, ChatGPT-подписки и другие локальные агенты не ходят через прокси. Чтобы закрыть эту дыру, мы используем **Token Monitor** как локальный коллектор и аналитику, а LiteLLM оставляем для API-прокси, точных цен и бюджетов.

```
┌──────────────────────────────┐
│ Claude Code / Codex / Cursor │──┐
│ Copilot / OpenCode / ...     │  │  локальные логи и квоты
└──────────────────────────────┘  │
                                  ▼
                       ┌─────────────────────┐
                       │ Token Monitor.app   │  менюбар + дашборд
                       │  локальный коллектор│  сессии, проекты, лимиты
                       │  + Hub :17321       │
                       └──────────▲──────────┘
                                  │ POST /api/ingest
                       ┌──────────┴──────────┐
                       │ litellm_bridge.py   │  нормализация spend logs
                       └──────────▲──────────┘
                                  │ GET /spend/logs/v2
                       ┌──────────┴──────────┐
                       │ LiteLLM :4000       │  API-прокси, цены, бюджеты
                       └──────────▲──────────┘
                                  │
                       OpenAI / Anthropic / OpenRouter / ...
```

## Что это даёт

- **Все агенты**: Token Monitor читает локальные логи 48+ инструментов, включая Claude Code, Codex, Cursor, Copilot, OpenCode, Antigravity, Cline, Kimi, Qwen, Goose, Zed, Kiro и другие.
- **Подписки и лимиты**: Token Monitor показывает 5-часовые/недельные/месячные окна, кредиты и балансы провайдеров. Это то, чего не видит LiteLLM.
- **API-трафик**: LiteLLM считает точные токены и деньги по прайсу модели, умеет кастомные цены и жёсткие бюджеты на ключи/пользователей/команды.
- **Задачи и сессии**: Token Monitor группирует по сессиям и проектам. Bridge кладёт `project`/`task` из metadata LiteLLM в `projectLabel`, поэтому в Projects видно, какая задача сколько съела.
- **Аналитика**: heatmap, тренды, stacked bars, K-line, разбивка по инструментам/моделям/сессиям/проектам/устройствам.
- **Статусбар**: у Token Monitor есть менюбар, notch, edge dock и виджеты macOS.
- **Мультиустройство**: Hub синхронизирует несколько машин; bridge выглядит как ещё одно устройство.

## Установка

### 1. Token Monitor

```bash
brew install --cask token-monitor
```

Запустите приложение. В **Settings → Multi-device Sync** выберите **Host** (встроенный Hub) или **Client** (внешний Hub). Для одной машины проще Host:

- Host слушает `http://127.0.0.1:17321`;
- секрет показан в настройках (кнопка копирования);
- этот секрет понадобится bridge.

Если нужен отдельный Node Hub (например, для нескольких машин):

```bash
git clone https://github.com/Javis603/token-monitor.git ~/tools/token-monitor
cd ~/tools/token-monitor
npm ci
TOKEN_MONITOR_PORT=17321 \
TOKEN_MONITOR_HOST=127.0.0.1 \
TOKEN_MONITOR_SECRET='придумайте-секрет' \
npm run hub
```

### 2. Bridge

Bridge не требует зависимостей — только Python 3.9+ из Command Line Tools.

```bash
cd ~/llm-spend-bar
export LITELLM_MASTER_KEY="$(grep '^LITELLM_MASTER_KEY=' .env | cut -d= -f2-)"
export TOKEN_MONITOR_HUB_URL="http://127.0.0.1:17321"
export TOKEN_MONITOR_SECRET="секрет-из-настроек-Token-Monitor"

# один пробный прогон
python3 bridge/litellm_bridge.py --once

# постоянная работа
python3 bridge/litellm_bridge.py --loop
```

Или через обёртку:

```bash
./scripts/bridge.sh --once
./scripts/bridge.sh
```

Автозапуск через launchd (рекомендуется для постоянного аудита):

```bash
./scripts/install-bridge-service.sh
# лог: ~/Library/Logs/LLM Spend Bar/bridge.log
# снять: ./scripts/install-bridge-service.sh --uninstall
```

Проверить, что данные дошли:

```bash
curl -s http://127.0.0.1:17321/api/stats \
  -H "Authorization: Bearer $TOKEN_MONITOR_SECRET" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print([x['deviceId'] for x in d['devices']])"
```

В Token Monitor должен появиться инструмент `litellm` (или ваш `client`, если вы его передали) и устройство `litellm-proxy`.

## Как подписывать задачи

Bridge читает `metadata.spend_logs_metadata` из LiteLLM. Передавайте туда `project`, `task` и `title`:

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-..." \
  -H "Content-Type: application/json" \
  -H "x-litellm-trace-id: task-42" \
  -H 'x-litellm-spend-logs-metadata: {"project":"billing","task":"refactor checkout","title":"Checkout refactor"}' \
  -d '{"model":"gpt-5.1","messages":[{"role":"user","content":"..."}]}'
```

В Token Monitor:

- `project` попадёт в **Projects**;
- `task`/`title` станут `projectLabel` сессии;
- `x-litellm-trace-id` станет `sessionId` и сгруппирует запросы одной задачи.

Для OpenCode/Claude Code/Codex, которые ходят через LiteLLM, можно добавить заголовок в конфиг провайдера. Для локальных агентов, которые не ходят через LiteLLM, Token Monitor и так читает их сессии и проекты.

## Бюджеты

- **API**: настройте `max_budget` у virtual key/user/team в LiteLLM. Это жёсткий лимит: запросы сверх бюджета будут отклонены. Наш менюбар `LLM Spend Bar` показывает расход к локальным дневным/недельным/месячным бюджетам.
- **Подписки**: Token Monitor показывает лимиты провайдера (5h/week/month/credits). Это не наш бюджет, а квота провайдера; жёстко ограничить её нельзя, можно только следить и получать алерты.
- **Bridge**: сейчас передаёт расход/токены, но не добавляет отдельный `litellm` limit provider. Token Monitor принимает только известные ему provider id. Если нужен отдельный «бюджет LiteLLM» в его Limits view, это небольшой патч в Token Monitor (добавить провайдера в `src/shared/limits/providers.js` и модуль). Можно сделать отдельным PR.

## OpenUsage как альтернатива

[OpenUsage](https://github.com/janekbaraniewski/openusage) — Go-бинарник, terminal-first. Он тоже читает локальные логи 37 провайдеров, хранит события в SQLite (`usage_events`), умеет `daily/weekly/monthly/session/blocks`, экспорт JSON/CSV и Hub.

Когда он лучше:

- нужен **headless** коллектор для сервера/SSH;
- нужен **Prometheus/Grafana**-пайплайн (можно читать SQLite или добавить экспортёр);
- вы готовы сами делать менюбар/дашборд.

Когда Token Monitor лучше:

- нужен готовый красивый дашборд, менюбар, notch, виджеты;
- нужны подписки/лимиты и мультиустройство «из коробки»;
- не хочется писать UI.

Мы можем позже добавить второй bridge `openusage -> Token Monitor` или `openusage -> Grafana`, если понадобится.

## LangGraph, LangSmith и Langfuse

LangGraph — это оркестратор агентов, а не система аудита. Он не видит Claude Code/ChatGPT-подписки. Для трассировки **своих** LangGraph-приложений есть два варианта:

- **LangSmith** — SaaS от LangChain, run tree, токены/стоимость, но подписка и per-seat цена.
- **Langfuse** — open-source, self-hosted, OpenTelemetry, токены/стоимость, дашборды. Хорошо сочетается с LiteLLM: LiteLLM умеет отправлять логи в Langfuse.

Рекомендация:

- для **всех локальных агентов и подписок** — Token Monitor;
- для **API-трафика и бюджетов** — LiteLLM;
- для **per-node/per-task трассировки собственных LangGraph-приложений** — Langfuse (опционально), а не LangGraph сам по себе.

LiteLLM умеет отправлять логи в Langfuse:

```yaml
# litellm/config.yaml
litellm_settings:
  success_callback: ["langfuse"]
```

```env
LANGFUSE_PUBLIC_KEY=pk-...
LANGFUSE_SECRET_KEY=sk-...
LANGFUSE_HOST=http://127.0.0.1:3000
```

Тогда в Langfuse будет дерево вызовов (run/node/tool), а в Token Monitor — общая картина по всем агентам и подпискам. Это разные уровни детализации, они дополняют друг друга.

## Ограничения

- Token Monitor читает только то, что агент оставил на диске. Если инструмент не пишет логи или хранит их в облаке, его не будет.
- Bridge обновляет данные раз в `--interval` секунд (по умолчанию 60). Token Monitor обновляет локальные данные чаще.
- Названия сессий из LiteLLM по умолчанию не синхронизируются (Token Monitor скрывает тексты). Для задач используйте `projectLabel`/Projects.
- `litellm` отображается как отдельный инструмент с техническим именем. Красивую иконку/лейбл можно добавить в Token Monitor отдельным PR.
