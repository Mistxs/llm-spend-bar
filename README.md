# LLM Spend Bar

<img src="docs/app-icon.png" width="128" alt="Иконка приложения">

Маленькое macOS-приложение для аудита расходов на LLM: показывает траты за день, неделю и месяц прямо в строке меню. Под капотом — [LiteLLM Proxy](https://docs.litellm.ai/docs/simple_proxy): он принимает запросы от агентов, считает токены и стоимость по прайсу модели и складывает всё в Postgres. Приложение читает spend logs через API LiteLLM.

![Иконка в строке меню](docs/menubar.png)

```
LLM Spend  ·  LiteLLM
Сегодня  ███░░░░░░░  34%   $3.42 / $10.00   1.3M tok
Неделя   ████░░░░░░  37%   $18.73 / $50.00  5.4M tok
Месяц    ███░░░░░░░  32%   $64.21 / $200.00 19M tok
---
Сессии сегодня
  opencode · auth refactor      $1.12  418k tok  14 запр.
  ChatGPT · SQL review          $0.72  267k tok   9 запр.
  Claude Code · payments        $0.91  352k tok  10 запр.
---
Модели сегодня
  gpt-5.1                       $1.84  796k tok  18 запр.
  claude-sonnet-4.5             $1.21  380k tok  12 запр.
---
● LiteLLM  http://127.0.0.1:4000
обновлено в 13:44:17
```

## Что умеет

- **Прокси для агентов.** LiteLLM даёт один OpenAI-совместимый endpoint для OpenAI, Anthropic, Google, OpenRouter, DeepSeek и ещё сотен провайдеров. Меняете `base_url` у агента — и весь трафик проходит через аудит.
- **Токены и деньги.** LiteLLM сам считает `prompt_tokens`, `completion_tokens`, cache-токены и стоимость по модели. Встроенный прайс-лист покрывает 4500+ моделей; свои цены задаются в конфиге или UI.
- **Сессии.** Запросы группируются по `session_id` из LiteLLM (`x-litellm-trace-id` или `x-*-session-id`). В меню видно, сколько потратил каждый диалог/агент.
- **Бюджеты.** В настройках приложения задаются дневной, недельный и месячный лимиты. Полоски в строке меню показывают долю израсходованного бюджета и меняют цвет.
- **Локально.** LiteLLM слушает только `127.0.0.1`, данные лежат в локальном Postgres. Приложение не отправляет ничего наружу.
- **Почти без зависимостей.** Приложение — Objective-C + AppKit, собирается `clang` из Command Line Tools. LiteLLM запускается в Docker.

## Архитектура

```
┌──────────────┐   OpenAI / Anthropic API   ┌─────────────────────┐
│ OpenCode     │───────────────────────────▶│ LiteLLM Proxy :4000 │
│ Claude Code  │                            │  routing · pricing  │
│ Codex / SDK  │◀───────────────────────────│  spend logs         │
└──────────────┘                            └──────────┬──────────┘
                                                       │ Postgres
                                            ┌──────────▼──────────┐
                                            │ LLM Spend Bar.app   │
                                            │ NSStatusItem        │
                                            │ GET /spend/logs/v2  │
                                            └─────────────────────┘
```

LiteLLM — единственный источник истины по токенам и деньгам. Приложение только читает его spend logs и агрегирует их по периодам, моделям и сессиям.

## Быстрый старт

Нужны macOS 13+, Docker (Docker Desktop или OrbStack) и Command Line Tools.

```bash
git clone <repo> llm-spend-bar
cd llm-spend-bar

./scripts/setup.sh          # создаст .env, поднимет LiteLLM + Postgres
./build.sh --install        # соберёт и установит приложение
```

`setup.sh` напечатает master key. Не удаляйте `.env`: смена `LITELLM_SALT_KEY` делает сохранённые в Postgres ключи провайдеров нечитаемыми. Дальше:

1. Откройте `http://127.0.0.1:4000/ui` (логин `admin`, пароль — master key).
2. **Models + Endpoints → Add Model**: добавьте нужные модели и ключи провайдеров. Либо положите ключи в `.env` (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, ...) и добавьте модели в `litellm/config.yaml`.
3. Нажмите на иконку в строке меню → **Настройки…** → вставьте master key → **Проверить подключение** → **Сохранить**.
4. Создайте virtual key для агентов:
   ```bash
   ./scripts/create-key.sh
   ```
   Master key нужен только приложению для чтения spend logs. Агентам лучше давать отдельный virtual key.

Проверить, что запросы доходят:

```bash
./scripts/test-request.sh gpt-5.1
```

Управление стеком:

```bash
./scripts/start.sh    # поднять LiteLLM снова
./scripts/stop.sh     # остановить (данные сохраняются)
./scripts/logs.sh     # смотреть логи LiteLLM
```

## Подключение агентов

Все агенты ходят в LiteLLM как в обычный OpenAI-совместимый API:

```bash
export OPENAI_BASE_URL=http://127.0.0.1:4000/v1
export OPENAI_API_KEY=sk-...          # virtual key из ./scripts/create-key.sh

# Anthropic-совместимые клиенты
export ANTHROPIC_BASE_URL=http://127.0.0.1:4000
export ANTHROPIC_AUTH_TOKEN=sk-...
```

### OpenCode

В `~/.config/opencode/opencode.json` (или в конфиге провайдера):

```json
{
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "sk-...",
        "headers": {
          "x-litellm-trace-id": "opencode-session"
        }
      },
      "models": {
        "gpt-5.1": { "name": "GPT-5.1" },
        "claude-sonnet-4.5": { "name": "Claude Sonnet 4.5" }
      }
    }
  }
}
```

`x-litellm-trace-id` можно подставлять динамически, если клиент умеет менять заголовки на каждый диалог. Если нет — LiteLLM сгруппирует запросы по `x-*-session-id`, `user` или `request_id`.

### OpenAI Python SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:4000/v1",
    api_key="sk-...",
    default_headers={"x-litellm-trace-id": "my-session-42"},
)
```

### curl

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-..." \
  -H "x-litellm-trace-id: my-session-42" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.1","messages":[{"role":"user","content":"hello"}]}'
```

## Как считаются сессии

LiteLLM пишет в `LiteLLM_SpendLogs` поле `session_id`. Источники по приоритету:

1. `x-litellm-trace-id` — рекомендуемый способ;
2. заголовок вида `x-<tool>-session-id`, например `x-claude-code-session-id`;
3. `session_id` в metadata запроса;
4. `request_id` — если ничего не передано, каждый запрос будет отдельной «сессией».

Чтобы LiteLLM писал `session_id` в логи, в `litellm/config.yaml` включено:

```yaml
litellm_settings:
  request_correlation_in_logs: true
```

Название сессии можно передать в metadata:

```json
{
  "metadata": {
    "session_id": "my-session-42",
    "title": "Рефакторинг оплаты"
  }
}
```

или заголовком:

```bash
-H 'x-litellm-spend-logs-metadata: {"session_id":"my-session-42","title":"Рефакторинг оплаты"}'
```

## Цены и бюджеты

LiteLLM уже знает цены большинства моделей. Если модели нет в прайс-листе или у вас особый тариф, задайте цену за **один токен**:

```yaml
model_list:
  - model_name: my-model
    litellm_params:
      model: openai/my-model
      api_key: os.environ/OPENAI_API_KEY
    model_info:
      input_cost_per_token: 0.00000125          # $1.25 / 1M
      output_cost_per_token: 0.00001            # $10 / 1M
      cache_read_input_token_cost: 0.000000125  # $0.125 / 1M
      cache_creation_input_token_cost: 0.0000015625
```

То же самое можно сделать в LiteLLM UI при редактировании модели. После изменения цен новые запросы будут считаться по новым тарифам; старые spend logs не пересчитываются.

> При добавлении модели через API `/model/new` цены нужно класть в `litellm_params`, а не в `model_info` — иначе LiteLLM их проигнорирует. В `config.yaml` и UI используется `model_info`.

Бюджеты в приложении — это **локальные пороги отображения**, а не блокировка запросов. Если нужен жёсткий лимит, настройте budget у virtual key/user/team в LiteLLM. Приложение покажет расход относительно ваших дневного, недельного и месячного бюджетов.

## Строка меню

- **Три полоски** — расход к бюджету за день / неделю / месяц. Зелёный < 50 %, оранжевый < 80 %, красный ≥ 80 %.
- **Доллары за сегодня** — сумма за текущий день.
- **Токены за сегодня** — суммарные токены за день.
- Клик по сессии копирует её `session_id` и открывает LiteLLM UI.
- **Настройки…** — URL LiteLLM, master key (хранится в Keychain), бюджеты, интервал обновления, вид иконки, путь к конфигу.

## Автозапуск

Меню → **Запускать при входе**. Чтобы регистрация сработала, приложение должно лежать в `~/Applications` или `/Applications` (используйте `./build.sh --install`). Сборка из `build/` может не зарегистрироваться.

## Сборка и отладка

```bash
./build.sh                     # собрать под текущую архитектуру
UNIVERSAL=1 ./build.sh         # universal: Intel + Apple Silicon
./build.sh --run               # собрать и запустить
./build.sh --install           # скопировать в ~/Applications и запустить
./build.sh --probe             # проверить подключение и напечатать сводку
./build.sh --dump-menu         # напечатать меню
./build.sh --demo              # запустить с демо-данными (без LiteLLM)
./build.sh --demo-menu         # напечатать демо-меню
./build.sh --self-test         # прогнать парсер на tests/fixtures/spend_logs.json
```

Для разработки без Docker есть mock-сервер:

```bash
python3 tools/mock_litellm.py --port 4010
LSB_BASE_URL=http://127.0.0.1:4010 LSB_MASTER_KEY=sk-test ./build.sh --probe
```

`--probe` печатает источник настроек, health-check, суммы за день/неделю/месяц, сессии и модели.

## Ограничения

- **Это аудит API-трафика, а не подписки ChatGPT.** Запросы ChatGPT Plus/Pro/Team через веб-интерфейс и десктопное приложение не проходят через LiteLLM и не видны приложению. Чтобы аудировать именно API-расходы, направьте агентов/скрипты на `http://127.0.0.1:4000`. Для лимитов подписки нужен отдельный источник (консоль провайдера).
- **LiteLLM должен быть запущен.** Приложение показывает `LLM ?`, если не может подключиться.
- **Данные в Postgres.** `docker compose down` сохраняет volume; `docker compose down -v` удаляет историю.
- **Master key — это root-доступ к LiteLLM.** Не давайте его агентам; используйте virtual keys.

## Troubleshooting

**`LiteLLM не запущен или недоступен`**
```bash
docker compose ps
./scripts/logs.sh
curl -i http://127.0.0.1:4000/health/liveliness
```

**`LiteLLM отклонил ключ (HTTP 401)`**
В настройках приложения указан не master key, а virtual key. Для чтения `/spend/logs/v2` нужен master key (или ключ с правами на spend-роуты).

**Пустые сессии**
Проверьте, что клиент отправляет `x-litellm-trace-id`. Без него LiteLLM группирует по `request_id`, и каждая запись будет отдельной сессией.

**Расход $0**
Модель отсутствует в прайс-листе LiteLLM или у неё не заданы `input_cost_per_token` / `output_cost_per_token`. Добавьте `model_info` в конфиг или UI.

**Порт 4000 занят**
Поменяйте `LITELLM_PORT` в `.env`, перезапустите `docker compose up -d` и укажите новый URL в настройках приложения.

## Лицензия

MIT. См. [LICENSE](LICENSE).
