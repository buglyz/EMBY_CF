# Emby Server Proxy

这是一个可直接部署到普通 Linux 服务器的 Emby 反向代理项目，不再依赖 Cloudflare Workers，也不需要 Docker。服务本体使用 Node.js 运行，可放在 `nginx` 或 `Caddy` 后面提供 HTTPS、域名接入和反向代理。

## 功能

- 保留原项目的路径格式：`https://你的域名/https://目标地址`
- 支持 Emby 常见 HTTP 代理请求
- 支持 WebSocket 升级转发
- 支持重定向处理与直连白名单
- 支持本地统计持久化，数据保存到服务器文件
- 提供首页说明、`/stats` 统计接口和 `/health` 健康检查

## 快速开始

### 1. 安装 Node.js

建议使用 Node.js 20 或更高版本。

### 2. 一键安装并注册 systemd

拉取仓库后，在 Linux 服务器中直接执行：

```bash
sudo sh deploy/install.sh
```

脚本会自动完成：

- 检查并安装 Node.js 20+
- 交互式询问域名、监听地址和端口
- 生成 `.env`
- 安装运行依赖
- 注册 `systemd` 服务
- 设置开机自启并立即启动

默认服务名为 `emby-server-proxy`，默认监听 `0.0.0.0:3000`。

交互安装时会依次提示你输入：

- 对外访问域名
- 服务监听地址
- 服务监听端口

如果你不想交互输入，也可以直接用环境变量覆盖，例如：

```bash
sudo APP_DOMAIN=media.example.com PORT=3100 RUN_USER=www-data RUN_GROUP=www-data sh deploy/install.sh
```

### 3. 手动启动服务

```bash
npm install
npm run start
```

默认监听：

- `HOST=0.0.0.0`
- `PORT=3000`

### 4. 访问示例

```text
https://你的服务域名/http://emby.example.com:8096
https://你的服务域名/https://emby.example.com
```

如果路径里没有写协议，服务默认按 `https://` 处理。

## 环境变量

可选配置写在 `.env` 中，示例见 `.env.example`。

- `HOST`：监听地址，默认 `0.0.0.0`
- `PORT`：监听端口，默认 `3000`
- `TIME_ZONE`：统计使用的时区，默认 `Asia/Shanghai`
- `STATS_FILE`：统计文件保存路径，默认 `./data/stats.json`
- `REQUEST_TIMEOUT_MS`：单次上游请求超时，默认 `300000`
- `TRUST_PROXY_HEADERS`：是否信任 `X-Forwarded-*` 和 `CF-*` 头，默认 `true`
- `MANUAL_REDIRECT_DOMAINS`：覆盖内置直连白名单，逗号分隔
- `DOMAIN_PROXY_RULES`：当请求来自指定 Cloudflare 日本节点时改写上游域名，格式为 `后缀=主机[:端口]`
- `JP_COLOS`：用于 `DOMAIN_PROXY_RULES` 的节点代码，默认 `NRT,KIX,FUK,OKA`

## 目录结构

```text
.
├─ server.js                 # Node 服务入口
├─ src/
│  ├─ config.js              # 运行配置
│  ├─ frontend.js            # 首页 HTML
│  └─ stats-store.js         # 本地统计持久化
├─ deploy/
│  ├─ nginx.conf             # nginx 配置示例
│  ├─ Caddyfile              # Caddy 配置示例
│  ├─ emby-proxy.service     # systemd 服务示例
│  └─ install.sh             # 一键安装脚本
├─ .env.example              # 环境变量示例
└─ DEPLOY.md                 # 服务器部署说明
```

## 部署方式

详细部署步骤见 [DEPLOY.md](./DEPLOY.md)。

## 说明

- 本项目仅用于学习和研究目的，请勿用于非法用途。
- 统计数据默认保存为本地 JSON 文件，适合单机部署。
- 如果你仍然在 Cloudflare 后面接入本服务，服务会尝试读取 `CF-RAY` 里的节点代码来兼容原有日本节点规则。
