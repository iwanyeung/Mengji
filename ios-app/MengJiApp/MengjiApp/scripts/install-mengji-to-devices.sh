#!/usr/bin/env bash
# 真机：先装 iPhone 梦悸，再单独装嵌套的 MengjiWatch.app 到配对手表。
# 用法：./scripts/install-mengji-to-devices.sh <iPhone设备ID> <AppleWatch设备ID>
set -euo pipefail

IPHONE_ID="${1:-}"
WATCH_ID="${2:-}"

if [[ -z "$IPHONE_ID" || -z "$WATCH_ID" ]]; then
  echo "用法: $0 <iPhone设备ID> <AppleWatch设备ID>"
  echo "ID 见 Xcode → Window → Devices and Simulators"
  exit 1
fi

APP="$(find ~/Library/Developer/Xcode/DerivedData/MengjiApp-*/Build/Products/Debug-iphoneos/MengjiApp.app -maxdepth 0 2>/dev/null | head -1)"
WATCH_APP="${APP}/Watch/MengjiWatch.app"

if [[ ! -d "$APP" ]]; then
  echo "未找到 Debug-iphoneos/MengjiApp.app，请先在 Xcode 对真机 ⌘R 或 Build 一次。"
  exit 1
fi
if [[ ! -d "$WATCH_APP" ]]; then
  echo "iPhone 包内无 Watch/MengjiWatch.app，请检查 Embed Watch Content + CodeSignOnCopy。"
  exit 1
fi

echo "→ 安装 iPhone App: $APP"
xcrun devicectl device install app --device "$IPHONE_ID" "$APP"

echo "→ 安装 Watch App: $WATCH_APP"
xcrun devicectl device install app --device "$WATCH_ID" "$WATCH_APP"

echo "→ 验证手表已安装："
xcrun devicectl device info apps --device "$WATCH_ID" 2>&1 | grep -i mengji || echo "(未 grep 到 mengji，请在手表主屏查看图标)"
