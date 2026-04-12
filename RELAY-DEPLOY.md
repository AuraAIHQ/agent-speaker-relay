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

## 方案 A：复用现有 Tunnel（推荐）

如果你已经有 Cloudflare Tunnel，**推荐复用**。

### 1. 查看现有 Tunnel

```bash
# 列出所有 tunnel
cloudflared tunnel list

# 输出示例：
# ID                    NAME           CREATED              CONNECTIONS
# c545ff0c-...          aastar-relay   2024-01-15 10:00:00  1xSJC, 1xHKG
# xxxx-xxxx-xxxx-xxxx   other-app      2024-01-10 09:00:00  2xSJC
```

### 2. 查看现有配置

```bash
# 找到所有配置文件
ls ~/.cloudflared/*.yml ~/.cloudflared/config.yml 2>/dev/null

# 查看现有 ingress 规则
cat ~/.cloudflared/config.yml
```

### 3. 添加 Agent Relay 到现有 Tunnel

编辑你的主配置文件（通常是 `~/.cloudflared/config.yml`）：

```yaml
tunnel: c545ff0c-6114-42e1-bea4-241836c85511
credentials-file: /Users/nicolasshuaishuai/.cloudflared/c545ff0c-6114-42e1-bea4-241836c85511.json

ingress:
  # 你现有的其他服务
  - hostname: app.aastar.io
    service: http://localhost:3000
  
  # ✅ 新增：Agent Relay（插入到默认规则之前）
  - hostname: relay.aastar.io
    service: http://localhost:7777
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
  
  # 默认规则（必须最后）
  - service: http_status:404
```

### 4. 添加 DNS 记录

```bash
# 复用同一个 tunnel 添加域名
cloudflared tunnel route dns aastar-relay relay.aastar.io
```

### 5. 准备 Relay 目录和配置

```bash
# 创建工作目录
mkdir -p ~/agent-relay && cd ~/agent-relay

# 下载配置文件
curl -O https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/strfry.aastar.conf
curl -O https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/docker-compose.aastar.yml

# 创建数据目录
mkdir -p data logs
```

### 6. 启动 Relay（Docker Compose）

```bash
# 启动 relay（使用 docker-compose）
docker-compose -f docker-compose.aastar.yml up -d

# 查看状态
docker-compose -f docker-compose.aastar.yml ps
docker logs -f aastar-relay
```

### 7. 优雅重启所有 Tunnel

```bash
# 方式 1：如果有 LaunchDaemon 配置
launchctl unload ~/Library/LaunchAgents/com.cloudflared.plist 2>/dev/null || true
sleep 2
launchctl load ~/Library/LaunchAgents/com.cloudflared.plist

# 方式 2：手动进程管理（找到所有 cloudflared 进程并重启）
# 先停止所有
echo "Stopping all cloudflared processes..."
killall cloudflared 2>/dev/null || true
sleep 2

# 重新启动（加载新配置）
echo "Starting cloudflared with updated config..."
cloudflared tunnel run aastar-relay &

# 方式 3：使用 systemd（Linux）或 LaunchDaemon（推荐用于生产）
# 见下面的 "开机自启" 章节
```

### 8. 验证

```bash
# 本地测试
curl http://localhost:7777

# 公网测试（等 10-30 秒 DNS 生效）
curl https://relay.aastar.io

# WebSocket 测试
wscat -c wss://relay.aastar.io
```

---

## 开机自启配置（推荐）

### macOS LaunchDaemon（管理所有 Tunnel）

创建统一的 LaunchDaemon 来管理所有服务：

```bash
# 创建 plist 文件
cat > ~/Library/LaunchAgents/com.aastar.services.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aastar.services</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>
            # Start Docker Compose services
            cd /Users/nicolasshuaishuai/agent-relay && /usr/local/bin/docker-compose -f docker-compose.aastar.yml up -d;
            # Start Cloudflare Tunnel
            /opt/homebrew/bin/cloudflared tunnel run aastar-relay
        </string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    
    <key>StandardOutPath</key>
    <string>/Users/nicolasshuaishuai/agent-relay/logs/service.log</string>
    
    <key>StandardErrorPath</key>
    <string>/Users/nicolasshuaishuai/agent-relay/logs/service.error.log</string>
    
    <key>WorkingDirectory</key>
    <string>/Users/nicolasshuaishuai/agent-relay</string>
</dict>
</plist>
EOF

# 加载
launchctl load ~/Library/LaunchAgents/com.aastar.services.plist

# 验证
launchctl list | grep aastar
```

### 控制脚本

创建统一的管理脚本：

```bash
# start-all.sh
cat > ~/agent-relay/start-all.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# Start Relay
echo "Starting Relay..."
docker-compose -f docker-compose.aastar.yml up -d

# Start Tunnel
echo "Starting Cloudflare Tunnel..."
killall cloudflared 2>/dev/null || true
sleep 2
nohup cloudflared tunnel run aastar-relay > ./logs/tunnel.log 2>&1 &

echo "All services started!"
echo "Relay: http://localhost:7777"
echo "Public: wss://relay.aastar.io"
EOF

chmod +x ~/agent-relay/start-all.sh

# stop-all.sh
cat > ~/agent-relay/stop-all.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "Stopping Relay..."
docker-compose -f docker-compose.aastar.yml down

echo "Stopping Tunnel..."
killall cloudflared 2>/dev/null || true

echo "All services stopped!"
EOF

chmod +x ~/agent-relay/stop-all.sh

# restart-all.sh
cat > ~/agent-relay/restart-all.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./stop-all.sh
sleep 2
./start-all.sh
EOF

chmod +x ~/agent-relay/restart-all.sh
```

---

## 方案 B：新建独立 Tunnel

如果你想完全隔离（不推荐，除非有特殊需求）：

```bash
# 使用自动部署脚本
curl -fsSL -o deploy-aastar.sh \
  https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/deploy-aastar.sh
chmod +x deploy-aastar.sh
./deploy-aastar.sh
```

这会创建新的 tunnel `aastar-relay`。

---

## 方案 C：裸机部署（无 Docker）

```bash
# macOS
brew install cmake pkg-config lmdb secp256k1 openssl zlib

# 编译 strfry
git clone https://github.com/hoytech/strfry.git
cd strfry
git submodule update --init
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
sudo make install

# 运行
strfry --config ~/strfry.aastar.conf relay
```

---

## 方案 D：VPS 直连（公网 IP）

最简单，但有公网 IP 暴露风险：

```bash
docker run -d \
  --name agent-relay \
  -p 7777:7777 \
  -v ~/relay-data:/app/strfry-db \
  hoytech/strfry:latest
```

---

## 🔧 多 Tunnel 管理建议

如果你有多个 tunnel，建议**合并到一个统一的配置**中：

```yaml
# ~/.cloudflared/config.yml（单一入口）
tunnel: <你的主-tunnel-id>
credentials-file: ~/.cloudflared/<id>.json

ingress:
  # 网站
  - hostname: aastar.io
    service: http://localhost:3000
  
  # API
  - hostname: api.aastar.io
    service: http://localhost:8080
  
  # Agent Relay
  - hostname: relay.aastar.io
    service: http://localhost:7777
    originRequest:
      noTLSVerify: true
  
  # 其他服务...
  
  # 默认规则
  - service: http_status:404
```

然后只运行一个 tunnel 进程管理所有服务。

---

## 🐛 故障排查

### 查看所有 Tunnel 状态

```bash
cloudflared tunnel list
cloudflared tunnel info <id>
```

### 优雅重启所有服务

```bash
# 1. 停止
docker-compose -f docker-compose.aastar.yml down
killall cloudflared

# 2. 等待
sleep 3

# 3. 启动
docker-compose -f docker-compose.aastar.yml up -d
cloudflared tunnel run <tunnel-name> &
```

### 检查端口占用

```bash
lsof -i :7777
netstat -an | grep 7777
```

---

## 📋 快速检查清单

- [ ] Tunnel 配置文件已更新（添加 relay.aastar.io）
- [ ] DNS 记录已添加
- [ ] relay.aastar.io 可解析（`nslookup relay.aastar.io`）
- [ ] Docker Compose 文件已下载
- [ ] Relay 容器运行中（`docker-compose ps`）
- [ ] 本地端口 7777 可访问（`curl localhost:7777`）
- [ ] 公网可访问（`curl https://relay.aastar.io`）
- [ ] WebSocket 可连接（`wscat -c wss://relay.aastar.io`）

---

## 💡 推荐做法（你的情况）

1. **使用现有的 `aastar-relay` tunnel**
2. **编辑现有 `~/.cloudflared/config.yml`** 添加 relay 规则
3. **使用 Docker Compose** 启动 relay（不是裸命令）
4. **优雅重启**：先停所有，再启动所有
5. **配置 LaunchDaemon** 实现开机自启

**不要**新建 tunnel ID，复用现有的即可。
