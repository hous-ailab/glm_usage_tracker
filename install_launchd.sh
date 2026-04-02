#!/bin/bash
set -e

PLIST_NAME="com.zai.usage-tracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PLIST_SRC="$SCRIPT_DIR/$PLIST_NAME.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "🔧 安装 Z.ai 用量追踪开机自启服务..."

if [ ! -f "$PROJECT_DIR/build/ZaiUsageTracker" ]; then
    echo "🔨 编译应用..."
    mkdir -p "$PROJECT_DIR/build"
    swiftc -o "$PROJECT_DIR/build/ZaiUsageTracker" \
        -target arm64-apple-macos14.0 \
        -framework Cocoa \
        -framework SwiftUI \
        -framework ServiceManagement \
        -parse-as-library \
        "$PROJECT_DIR/ZaiMenuBarApp.swift"
    echo "✅ 编译完成"
fi

# 复制 API key 配置文件到 build 目录，确保 Bundle 中包含配置文件
if [ -f "$PROJECT_DIR/.zai_apikey.json" ]; then
    cp "$PROJECT_DIR/.zai_apikey.json" "$PROJECT_DIR/build/.zai_apikey.json"
    echo "📋 已复制 API key 配置文件到 build 目录"
else
    echo "⚠️  警告: .zai_apikey.json 不存在，请先配置 API key"
fi

mkdir -p "$HOME/Library/LaunchAgents"

sed "s|__PROJECT_DIR__|$PROJECT_DIR|g" "$PLIST_SRC" > "$PLIST_DST"

pkill -f ZaiUsageTracker 2>/dev/null || true
sleep 1

launchctl bootout gui/$(id -u) "$PLIST_DST" 2>/dev/null || true
sleep 0.5

launchctl bootstrap gui/$(id -u) "$PLIST_DST"

echo "✅ 开机自启已配置！应用已启动。"
echo ""
echo "📋 常用命令："
echo "   停止服务:  launchctl bootout gui/\$(id -u) $PLIST_DST"
echo "   启动服务:  launchctl bootstrap gui/\$(id -u) $PLIST_DST"
echo "   查看日志:  cat /tmp/zai-usage-tracker.log"
echo "   卸载服务:  launchctl bootout gui/\$(id -u) $PLIST_DST && rm $PLIST_DST"
