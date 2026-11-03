#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LLM Spend Bar"
APP="build/$APP_NAME.app"
MIN_MACOS="13.0"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(-arch arm64 -arch x86_64)
  ARCH_LABEL="universal"
else
  ARCH_FLAGS=(-arch "$(uname -m)")
  ARCH_LABEL="$(uname -m)"
fi

echo "==> Сборка $APP_NAME ($ARCH_LABEL, macOS $MIN_MACOS+)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

clang \
  -fobjc-arc \
  -O2 \
  "${ARCH_FLAGS[@]}" \
  -mmacosx-version-min="${MIN_MACOS}" \
  -framework Cocoa \
  -framework ServiceManagement \
  -framework WebKit \
  -lsqlite3 \
  Sources/*.m \
  -o "$APP/Contents/MacOS/LLMSpendBar"

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f Resources/pricing.json ]]; then
  cp Resources/pricing.json "$APP/Contents/Resources/pricing.json"
fi
if [[ -d Resources/dashboard ]]; then
  cp -R Resources/dashboard "$APP/Contents/Resources/dashboard"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -n "${APP_VERSION:-}" ]]; then
  VERSION="${APP_VERSION#v}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"
  echo "==> Версия $VERSION"
fi

codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "==> Готово: $APP"

case "${1:-}" in
  --run)
    open "$APP"
    ;;
  --install)
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$APP" "$HOME/Applications/$APP_NAME.app"
    echo "==> Установлено: $HOME/Applications/$APP_NAME.app"
    open "$HOME/Applications/$APP_NAME.app"
    ;;
  --scan)
    "$APP/Contents/MacOS/LLMSpendBar" --scan
    ;;
  --dashboard-json)
    "$APP/Contents/MacOS/LLMSpendBar" --dashboard-json "${2:-/tmp/llm-spend-dashboard.json}"
    ;;
  --dump-menu)
    "$APP/Contents/MacOS/LLMSpendBar" --dump-menu
    ;;
  --demo)
    LSB_DEMO=1 "$APP/Contents/MacOS/LLMSpendBar"
    ;;
  --settings)
    "$APP/Contents/MacOS/LLMSpendBar" --settings
    ;;
  --dashboard)
    "$APP/Contents/MacOS/LLMSpendBar" --dashboard
    ;;
  --demo-menu)
    LSB_DEMO=1 "$APP/Contents/MacOS/LLMSpendBar" --dump-menu
    ;;
  --self-test)
    "$APP/Contents/MacOS/LLMSpendBar" --self-test "${2:-tests/fixtures/spend_logs.json}"
    ;;
esac
