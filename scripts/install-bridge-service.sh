#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="dev.llmspendbar.bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/LLM Spend Bar"
UID_VALUE="$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$UID_VALUE/$LABEL" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "==> Автозапуск bridge удалён"
  exit 0
fi

if [[ ! -f .bridge.env ]]; then
  echo "Нет .bridge.env. Скопируйте .bridge.env.example и вставьте секрет из Token Monitor." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "Нет .env. Сначала запустите ./scripts/setup.sh." >&2
  exit 1
fi

echo "==> Проверяю bridge одним прогоном"
./scripts/bridge.sh --once >/dev/null

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$PWD/scripts/bridge.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/bridge.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/bridge.log</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$UID_VALUE/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST"
launchctl enable "gui/$UID_VALUE/$LABEL" >/dev/null 2>&1 || true

echo "==> Автозапуск bridge установлен"
echo "    plist: $PLIST"
echo "    лог:   $LOG_DIR/bridge.log"
echo "    снять: ./scripts/install-bridge-service.sh --uninstall"
