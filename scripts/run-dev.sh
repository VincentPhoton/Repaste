#!/bin/bash
# Repaste 开发启动工具：先结束正在运行的 Repaste，再重新编译（禁用签名），
# 去掉隔离属性后启动本地构建，让你立刻看到最新改动。
#
# 用法： ./scripts/run-dev.sh
# 说明： 本机若无开发者证书，用 CODE_SIGNING_ALLOWED=NO 编译（应用未签名，
#        启动前用 xattr -cr 去掉可能存在的 quarantine，避免 Gatekeeper 拦截）。
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "== 1/4 结束正在运行的 Repaste =="
# 可能同时存在旧版 /Applications 与本地构建（同 bundle id），统一结束，避免双份监听剪贴板
pkill -x Repaste 2>/dev/null && sleep 1 || echo "   （没有正在运行的 Repaste）"

echo "== 2/4 重新编译（禁用签名）=="
xcodebuild \
  -project Repaste/Repaste.xcodeproj \
  -scheme Repaste \
  -configuration Debug \
  -derivedDataPath ./build \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build > /tmp/repaste-build.log 2>&1 \
  || { echo "  ❌ 编译失败，日志："; tail -30 /tmp/repaste-build.log; exit 1; }
echo "   ✅ 编译成功"

echo "== 3/4 去掉隔离属性（未签名应用）=="
xattr -cr "build/Build/Products/Debug/Repaste.app" 2>/dev/null || true

echo "== 4/4 启动本地构建 =="
open "build/Build/Products/Debug/Repaste.app"
echo "   ✅ 已启动：build/Build/Products/Debug/Repaste.app"

# 启动后短暂等待，确认进程存在
sleep 2
if pgrep -x Repaste >/dev/null; then
  echo "   ✅ 确认 Repaste 进程正在运行"
else
  echo "   ⚠️ 未检测到 Repaste 进程（可能被 Gatekeeper 拦截，尝试手动 open 或重新运行）"
fi
