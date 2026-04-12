# Build Guide - Agent Speaker Relay

> 从源码构建自定义 Relay

## 快速开始

```bash
# 1. Clone 我们的仓库
git clone https://github.com/MushroomDAO/agent-speaker-relay.git
cd agent-speaker-relay

# 2. 构建 Docker 镜像
docker build -f Dockerfile.agent-speaker -t mushroomdao/agent-speaker-relay:latest .

# 3. 准备配置
mkdir -p data logs
cp strfry.aastar.conf strfry.conf  # 或编辑你自己的配置

# 4. 启动
docker-compose -f docker-compose.aastar.yml up -d

# 5. 验证
curl http://localhost:7777
```

## 目录结构

```
agent-speaker-relay/
├── Dockerfile.agent-speaker    # Docker 构建文件
├── docker-compose.aastar.yml   # Docker Compose 配置
├── strfry.aastar.conf          # 默认配置模板
├── strfry.conf                 # 你的实际配置（gitignore）
├── data/                       # 数据目录（gitignore）
└── logs/                       # 日志目录（gitignore）
```

## 本地开发构建

```bash
# 开发模式（不缓存）
docker build --no-cache -f Dockerfile.agent-speaker -t mushroomdao/agent-speaker-relay:dev .

# 带详细日志
docker build --progress=plain -f Dockerfile.agent-speaker -t mushroomdao/agent-speaker-relay:latest .
```

## 与上游同步更新

```bash
# 拉取上游 strfry 更新
git fetch upstream
git checkout main
git merge upstream/master
git push origin main

# 然后合并到我们的 agent-speaker 分支
git checkout agent-speaker
git merge main

# 重新构建
docker build -f Dockerfile.agent-speaker -t mushroomdao/agent-speaker-relay:latest .
```

## 自定义配置

### 修改配置

```bash
# 复制模板
cp strfry.aastar.conf strfry.conf

# 编辑你自己的配置
nano strfry.conf
```

### 修改后重启

```bash
docker-compose -f docker-compose.aastar.yml restart
```

## 常用命令

```bash
# 构建并启动
docker-compose -f docker-compose.aastar.yml up --build -d

# 查看日志
docker-compose -f docker-compose.aastar.yml logs -f

# 停止
docker-compose -f docker-compose.aastar.yml down

# 完全重建（清除数据）
docker-compose -f docker-compose.aastar.yml down -v
docker-compose -f docker-compose.aastar.yml up --build -d
```
