# Agent Speaker Relay 部署指南

> 多种部署方式对比，选择最适合你的方案

---

## 📊 部署方案对比

| 方案 | 适用场景 | 优点 | 缺点 | 复杂度 |
|------|---------|------|------|--------|
| **A. Docker + 现有 Tunnel** | 已有 Cloudflare Tunnel | 复用配置，统一管理 | 需编辑 YAML | ⭐⭐ |
| **B. Docker + 新建 Tunnel** | 无现有 Tunnel | 隔离配置，独立管理 | Tunnel 数量增多 | ⭐⭐⭐ |
| **C. 裸机部署** | 无 Docker | 资源占用低 | 配置复杂 | ⭐⭐⭐⭐ |
| **D. VPS 直连** | 有公网 IP | 简单直接 | 暴露端口 | ⭐ |

---

## 方案 A：复用现有 Tunnel（推荐）

如果你已经有 Cloudflare Tunnel（如图中 `c545ff0c-...`），**推荐复用**。

### 查看现有 Tunnel

```bash
# 列出所有 tunnel
cloudflared tunnel list

# 输出示例：
# ID                    NAME           CREATED              CONNECTIONS
# c545ff0c-...          aastar-relay   2024-01-15 10:00:00  1xSJC, 1xHKG
# xxxx-xxxx-xxxx-xxxx   my-other-app   2024-01-10 09:00:00  2xSJC
```

### 找到配置文件

```bash
# 查看 tunnel 配置位置（通常是 ~/.cloudflared/）
ls ~/.cloudflared/*.yml ~/.cloudflared/config.yml 2>/dev/null

# 或者找到特定 tunnel 的凭证
cat ~/.cloudflared/c545ff0c-6114-42e1-bea4-241836c85511.json | jq '.TunnelID'
```

### 添加 Agent Relay 到现有 Tunnel

编辑现有 `config.yml`：

```bash
# 找到并编辑配置文件
nano ~/.cloudflared/config.yml
```

在 `ingress:` 部分**添加新的规则**（注意顺序，默认规则放最后）：

```yaml
tunnel: c545ff0c-6114-42e1-bea4-241836c85511
credentials-file: /Users/nicolasshuaishuai/.cloudflared/c545ff0c-6114-42e1-bea4-241836c85511.json

ingress:
  # 你现有的服务
  - hostname: app.aastar.io
    service: http://localhost:3000
  
  # ✅ 新增：Agent Relay
  - hostname: relay.aastar.io
    service: http://localhost:7777
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
  
  # 默认规则（必须最后）
  - service: http_status:404
```

### 添加 DNS 记录

```bash
# 复用同一个 tunnel 添加域名
cloudflared tunnel route dns aastar-relay relay.aastar.io
```

### 重启 Tunnel

```bash
# 找到并重启 tunnel 进程
# 方式 1：如果手动运行
Ctrl+C  # 停止现有
cloudflared tunnel run aastar-relay  # 重新运行

# 方式 2：如果是服务
launchctl unload ~/Library/LaunchAgents/com.cloudflared.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.cloudflared.plist

# 方式 3：强制重启
killall cloudflared
cloudflared tunnel run aastar-relay
```

### 验证

```bash
# 测试本地 relay
curl http://localhost:7777

# 测试公网地址
curl https://relay.aastar.io

# WebSocket 测试
wscat -c wss://relay.aastar.io
```

---

## 方案 B：新建独立 Tunnel

如果你想让 Agent Relay 有独立的 Tunnel ID：

```bash
# 使用我们的自动部署脚本
curl -fsSL -o deploy-aastar.sh \
  https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/deploy-aastar.sh
chmod +x deploy-aastar.sh
./deploy-aastar.sh
```

这会创建新的 tunnel `aastar-relay`。

---

## 方案 C：裸机部署（无 Docker）

适用于资源受限或不想用 Docker 的场景。

### 1. 安装依赖

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

# 安装
sudo make install
```

### 2. 配置并运行

```bash
# 下载我们的配置
curl -O https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/strfry.aastar.conf
mv strfry.aastar.conf /usr/local/etc/strfry.conf

# 运行
strfry --config /usr/local/etc/strfry.conf relay
```

---

## 方案 D：VPS 直连（公网 IP）

适用于有公网 IP 的服务器，最简单：

```bash
# 直接暴露端口
docker run -d \
  --name agent-relay \
  -p 7777:7777 \
  -v ~/relay-data:/app/strfry-db \
  hoytech/strfry:latest

# 访问 wss://your-vps-ip:7777
```

**注意**：需要防火墙开放 7777 端口。

---

## 🔧 配置文件详解

### strfry.aastar.conf 关键配置

```ini
[relay.network]
bind = "127.0.0.1"  # 只绑定 localhost，安全
port = 7777

[limits]
eventsPerSecond = 5      # 限制事件频率
maxConnsPerIp = 3        # 限制单 IP 连接数

[retention]
maxAge = 2592000         # 30天消息保留

[db]
maxSize = 536870912      # 500MB 数据库限制
```

### 多 Tunnel 管理建议

如果你有多个 tunnel，建议统一配置：

```yaml
# ~/.cloudflared/config.yml
tunnel: <你的主-tunnel-id>
credentials-file: ~/.cloudflared/<id>.json

ingress:
  # 网站
  - hostname: aastar.io
    service: http://localhost:3000
  
  # API
  - hostname: api.aastar.io
    service: http://localhost:8080
  
  # ✅ Agent Relay
  - hostname: relay.aastar.io
    service: http://localhost:7777
    originRequest:
      noTLSVerify: true
  
  # 其他服务...
  - hostname: xxx.aastar.io
    service: http://localhost:xxxx
  
  # 默认
  - service: http_status:404
```

---

## 🐛 故障排查

### Tunnel 连接失败

```bash
# 检查 tunnel 状态
cloudflared tunnel info <tunnel-id>

# 查看日志
cloudflared tunnel run <tunnel-name> --log-level debug

# 检查 DNS
nslookup relay.aastar.io
```

### Relay 无法启动

```bash
# 检查端口占用
lsof -i :7777

# 查看日志
docker logs aastar-relay

# 检查配置语法
cat strfry.aastar.conf | grep -v "^#" | grep -v "^$"
```

### 客户端连不上

```bash
# 本地测试
curl http://localhost:7777

# Tunnel 测试
curl https://relay.aastar.io

# WebSocket 测试
wscat -c wss://relay.aastar.io
```

---

## 📋 快速检查清单

- [ ] Tunnel 配置文件已更新
- [ ] DNS 记录已添加
- [ ] relay.aastar.io 可解析
- [ ] Docker 容器运行中
- [ ] 本地端口 7777 可访问
- [ ] 公网 wss://relay.aastar.io 可访问
- [ ] 客户端可发送/接收消息

---

## 💡 推荐做法总结

1. **已有 Tunnel** → **方案 A**（复用，统一管理）
2. **无 Tunnel** → **方案 B**（自动化脚本）
3. **资源受限** → **方案 C**（裸机编译）
4. **有公网 IP** → **方案 D**（最简单）

你的情况（已有 Tunnel）→ **推荐方案 A**
