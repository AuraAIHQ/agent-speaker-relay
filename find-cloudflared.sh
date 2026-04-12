#!/bin/bash
# 诊断脚本：找到 cloudflared 的实际配置

echo "=== Cloudflared 诊断 ==="
echo ""

# 1. 找到 plist 文件
echo "1. 查找 plist 文件..."
find ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons -name "*cloudflared*" 2>/dev/null

# 2. 查看 launchctl 状态
echo ""
echo "2. Launchctl 状态..."
launchctl list | grep cloudflared

# 3. 找到运行中的进程
echo ""
echo "3. 运行中的进程..."
ps aux | grep cloudflared | grep -v grep

# 4. 找到 config.yml
echo ""
echo "4. 查找配置文件..."
find ~/.cloudflared -name "*.yml" -o -name "config.yml" 2>/dev/null | head -5

# 5. 查看 plist 内容（如果找到了）
echo ""
echo "5. Plist 内容..."
PLIST=$(find ~/Library/LaunchAgents /Library/LaunchAgents -name "*cloudflared*" 2>/dev/null | head -1)
if [ -n "$PLIST" ]; then
    echo "找到: $PLIST"
    cat "$PLIST"
else
    echo "未找到 plist 文件"
fi

# 6. 显示当前 ingress
echo ""
echo "6. 当前 ingress 配置..."
CONFIG=$(find ~/.cloudflared -name "config.yml" 2>/dev/null | head -1)
if [ -n "$CONFIG" ]; then
    echo "配置文件: $CONFIG"
    grep -A 1 "hostname:" "$CONFIG" 2>/dev/null || echo "无法读取配置"
else
    echo "未找到 config.yml"
fi
