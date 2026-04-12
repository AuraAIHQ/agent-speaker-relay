# Agent Speaker Relay 部署指南

> 多种部署方式对比，选择最适合你的方案

---

## 📊 部署方案对比

| 方案 | 适用场景 | 优点 | 缺点 | 复杂度 |
|------|---------|------|------|--------|
| **A. Docker Compose + 现有 Tunnel** | 已有 Cloudflare Tunnel | 复用配置，统一管理 | 需编辑 YAML | ⭐⭐ |
| **B. Docker Compose + 新建 Tunnel** | 无现有 Tunnel | 隔离配置，独立管理 | Tunnel 数量增多 | ⭐⭐⭐ |
| **C. 裸机部署** | 无 Docker | 资源占用低 | 配置复杂 | ⭐⭐⭐⭐ |
| **D. VPS 直连** | 有公网 IP | 简单直接 | 暴露端口 | ⭐ |

---

## 🔍 诊断：你的 Cloudflared 是如何运行的？

在部署之前，先确定你当前的 cloudflared 是如何管理的：

```bash
# 运行诊断脚本
curl -fsSL -o find-cloudflared.sh \
  https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/find-cloudflared.sh
chmod +x find-cloudflared.sh
./find-cloudflared.sh
```

### 常见情况

| 情况 | 现象 | 解决方案 |
|------|------|---------|
| **A. LaunchAgent (plist)** | `launchctl list` 显示服务 | `launchctl unload/load` 重启 |
| **B. 手动运行** | `ps aux` 显示，但无 plist | `kill` 后重新运行 |
| **C. Homebrew 服务** | `brew services list` 显示 | `brew services restart` |
| **D. Docker 运行** | `docker ps` 显示容器 | `docker restart` |

---

## 方案 A：复用现有 Tunnel（推荐）

### 1. 确定当前配置

```bash
# 列出所有 tunnel
cloudflared tunnel list

# 找到配置文件
ls ~/.cloudflared/config.yml
ls ~/.cloudflared/*.yml

# 查看当前 ingress
cloudflared tunnel ingress rule https://relay.aastar.io 2>/dev/null || echo "规则不存在"
```

### 2. 修改配置添加 Relay

编辑 `~/.cloudflared/config.yml`：

```yaml
tunnel: c545ff0c-6114-42e1-bea4-241836c85511
credentials-file: /Users/nicolasshuaishuai/.cloudflared/c545ff0c-6114-42e1-bea4-241836c85511.json

ingress:
  # 你现有的服务...
  - hostname: app.aastar.io
    service: http://localhost:3000
  
  # ✅ 添加 Agent Relay
  - hostname: relay.aastar.io
    service: http://localhost:7777
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
  
  # 默认规则（必须最后）
  - service: http_status:404
```

### 3. 添加 DNS

```bash
cloudflared tunnel route dns aastar-relay relay.aastar.io
```

### 4. 准备 Relay 目录

```bash
mkdir -p ~/agent-relay && cd ~/agent-relay

# 下载配置文件
curl -O https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/strfry.aastar.conf
curl -O https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/docker-compose.aastar.yml

# 创建数据目录
mkdir -p data logs

# 创建控制脚本
cat > restart-all.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🔄 Restarting services..."

# 1. 重启 Relay
echo "  ↻ Relay..."
docker-compose -f docker-compose.aastar.yml down
docker-compose -f docker-compose.aastar.yml up -d

# 2. 重启 Tunnel（优雅方式）
echo "  ↻ Tunnel..."

# 方法 A: 如果是 LaunchAgent
if launchctl list | grep -q com.cloudflared; then
    launchctl unload ~/Library/LaunchAgents/com.cloudflared.cloudflared.plist 2>/dev/null || \
    launchctl unload ~/Library/LaunchAgents/com.cloudflared.plist 2>/dev/null || true
    sleep 2
    launchctl load ~/Library/LaunchAgents/com.cloudflared.cloudflared.plist 2>/dev/null || \
    launchctl load ~/Library/LaunchAgents/com.cloudflared.plist 2>/dev/null || true
    echo "    ✓ Via LaunchAgent"

# 方法 B: 如果是 Homebrew 服务
elif brew services list | grep -q cloudflared; then
    brew services restart cloudflared
    echo "    ✓ Via Homebrew"

# 方法 C: 手动重启
else
    pkill cloudflared 2>/dev/null || true
    sleep 2
    nohup cloudflared tunnel run aastar-relay > ./logs/tunnel.log 2>&1 &
    echo "    ✓ Manual restart"
fi

echo "✅ Done! wss://relay.aastar.io"
EOF

chmod +x restart-all.sh
```

### 5. 启动 Relay

```bash
# 只启动 relay（tunnel 由系统管理）
docker-compose -f docker-compose.aastar.yml up -d
```

### 6. 重启 Tunnel 加载新配置

```bash
# 根据你的情况选择：

# 情况 A: LaunchAgent（plist 存在）
launchctl unload ~/Library/LaunchAgents/com.cloudflared.cloudflared.plist
sleep 2
launchctl load ~/Library/LaunchAgents/com.cloudflared.cloudflared.plist

# 情况 B: Homebrew 服务
brew services restart cloudflared

# 情况 C: 手动运行
pkill cloudflared
sleep 2
cloudflared tunnel run aastar-relay &
```

### 7. 验证

```bash
# 本地
curl http://localhost:7777

# 公网（等 30 秒）
curl https://relay.aastar.io

# WebSocket
wscat -c wss://relay.aastar.io
```

---

## 🔧 不同管理方式的重启方法

### 方法 A: LaunchAgent（你的情况）

```bash
# 找到 plist
find ~/Library/LaunchAgents -name "*cloudflared*"

# 通常是：
# ~/Library/LaunchAgents/com.cloudflared.cloudflared.plist

# 重启
launchctl unload ~/Library/LaunchAgents/com.cloudflared.cloudflared.plist
sleep 2
launchctl load ~/Library/LaunchAgents/com.cloudflared.cloudflared.plist

# 验证
launchctl list | grep cloudflared
```

### 方法 B: Homebrew 服务

```bash
# 查看状态
brew services list | grep cloudflared

# 重启
brew services restart cloudflared
```

### 方法 C: Docker 运行

```bash
# 查看容器
docker ps | grep cloudflared

# 重启
docker restart <container-id>
```

### 方法 D: 手动运行

```bash
# 找到进程
pgrep cloudflared

# 优雅停止
kill -TERM <pid>
# 或强制
kill -9 <pid>

# 重新运行
cloudflared tunnel run aastar-relay &
```

---

## 方案 B：新建独立 Tunnel

如果你想完全隔离：

```bash
# 下载自动部署脚本
curl -fsSL -o deploy-aastar.sh \
  https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/deploy-aastar.sh
chmod +x deploy-aastar.sh
./deploy-aastar.sh
```

---

## 🐛 故障排查

### 找不到 plist 文件

```bash
# 搜索所有可能的 plist
sudo find / -name "*cloudflared*.plist" 2>/dev/null

# 或者查看 launchctl 配置
launchctl dumpstate | grep -A 5 cloudflared
```

### Tunnel 启动失败

```bash
# 查看日志
tail -f ~/agent-relay/logs/tunnel.log

# 测试配置
cloudflared tunnel --config ~/.cloudflared/config.yml ingress validate

# 手动运行看错误
cloudflared tunnel run aastar-relay
```

### Relay 连接不上

```bash
# 检查端口
lsof -i :7777
netstat -an | grep 7777

# 检查 Docker
docker logs aastar-relay
docker-compose -f docker-compose.aastar.yml ps
```

---

## 🎯 你的具体情况

你说 `launchctl list` 显示了 `com.cloudflared.cloudflared`，说明：

1. **是用 LaunchAgent 管理的** ✅
2. **plist 文件可能在**：
   - `~/Library/LaunchAgents/com.cloudflared.cloudflared.plist`
   - `/Library/LaunchAgents/com.cloudflared.cloudflared.plist`

### 正确的重启命令

```bash
# 1. 找到 plist
PLIST=$(find ~/Library/LaunchAgents /Library/LaunchAgents -name "*cloudflared*.plist" 2>/dev/null | head -1)
echo "Found: $PLIST"

# 2. 修改 config.yml 后，重启
launchctl unload "$PLIST"
sleep 2
launchctl load "$PLIST"

# 3. 验证
launchctl list | grep cloudflared
```

明白了吗？需要我根据你的具体情况调整吗？
