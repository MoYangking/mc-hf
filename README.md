# Minecraft Server with FRP and Web Monitor

一个集成了 Minecraft 服务器、FRP 内网穿透和精美 Web 监控面板的 Docker 容器。

## 功能特性

- ✅ Minecraft 服务器（基于 itzg/minecraft-server）
- ✅ FRP 内网穿透（支持官方 frpc 和 sakura-frpc）
- ✅ 实时 Web 监控面板（端口 7860）
- ✅ Supervisor 进程管理
- ✅ 精美的响应式界面

## 快速开始

### 构建镜像

```bash
docker build -t mc-hf:latest .
```

### 运行容器

#### 使用官方 FRP

```bash
docker run -d \
  -p 25565:25565 \
  -p 7860:7860 \
  -e EULA=TRUE \
  -e FRPS_SERVER_ADDR=your-frp-server.com \
  -e FRP_TOKEN=your-token \
  -v ./data:/data \
  --name mc-hf \
  mc-hf:latest
```

#### 使用 Sakura FRP

```bash
docker run -d \
  -p 25565:25565 \
  -p 7860:7860 \
  -e EULA=TRUE \
  -e FRP_IMPL=sakura \
  -e FRP_AUTH=token:nodeid \
  -v ./data:/data \
  --name mc-hf \
  mc-hf:latest
```

## Web 监控面板

访问 `http://your-server:7860` 查看实时服务器状态：

- 💻 CPU 使用率
- 🧠 内存使用情况
- 💾 磁盘使用情况
- 🌐 网络流量统计
- ⏱️ 系统运行时间
- ⚙️ 服务状态（Minecraft、FRP、Supervisor）

## 环境变量

### Minecraft 相关
- `EULA`: 接受 Minecraft EULA（必须设置为 TRUE）
- 其他变量参考 [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server)

### FRP 相关
- `FRP_IMPL`: FRP 实现类型（`frpc` 或 `sakura`，默认 `frpc`）
- `FRPS_SERVER_ADDR`: FRP 服务器地址（官方 frpc 使用）
- `FRP_TOKEN`: FRP 认证令牌（官方 frpc 使用）
- `FRP_AUTH`: Sakura FRP 认证（格式：`token:nodeid`）
- `FRP_ARGS`: 额外的 FRP 参数（可选）

## 项目结构

```
mc-hf/
├── Dockerfile              # Docker 镜像定义
├── supervisord.conf        # Supervisor 配置
├── frp-entry.sh           # FRP 启动脚本
├── frpc.toml.template     # FRP 配置模板
├── requirements.txt       # Python 依赖
├── web/                   # Web 监控应用
│   ├── app.py            # Flask 后端
│   └── templates/
│       └── index.html    # 前端页面
└── README.md             # 项目文档
```

## 端口说明

- `25565`: Minecraft 服务器端口
- `7860`: Web 监控面板端口

## 许可证

MIT License
