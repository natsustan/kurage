#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
if [[ $# -gt 0 ]]; then shift; fi
case "$MODE" in
    run|--verify|--debug|--logs|--telemetry) ;;
    *) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry] [app arguments]" >&2; exit 2 ;;
esac

APP="$ROOT/build/Mac/Build/Products/Debug/KurageMac.app"
if pgrep -x KurageMac >/dev/null; then
    osascript -e 'tell application id "com.spike.kurage.macos" to quit'
fi
xcodebuild -project "$ROOT/Kurage.xcodeproj" -scheme KurageMac \
    -destination 'platform=macOS' -derivedDataPath "$ROOT/build/Mac" build

if [[ "$MODE" == --debug ]]; then
    exec lldb -- "$APP/Contents/MacOS/KurageMac" "$@"
fi
open -n "$APP" --args "$@"
case "$MODE" in
    --verify) sleep 2; pgrep -x KurageMac >/dev/null ;;
    --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "KurageMac"' ;;
    --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.spike.kurage.macos"' ;;
esac
