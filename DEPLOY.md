# 服务器部署说明

本文档说明如何把本项目部署到普通 Linux 服务器，不使用 Docker。

## 方案概览

推荐结构：

1. Node.js 服务默认监听 `0.0.0.0:3000`
2. 使用 `systemd` 守护进程
3. 使用 `nginx` 或 `Caddy` 对外提供 HTTPS

## 一、准备环境

### 1. 安装 Node.js

建议 Node.js 20 及以上。

### 2. 上传项目

把项目放到类似下面的目录：

```bash
/opt/emby-server-proxy
```

### 3. 配置环境变量

创建 `.env` 文件：

```bash
HOST=0.0.0.0
PORT=3000
TIME_ZONE=Asia/Shanghai
STATS_FILE=./data/stats.json
REQUEST_TIMEOUT_MS=300000
TRUST_PROXY_HEADERS=true
```

## 二、一键安装

仓库拉取到服务器后，直接在项目根目录执行：

```bash
sudo sh deploy/install.sh
```

脚本会自动完成：

1. 检查并安装 Node.js 20+
2. 交互式询问域名、监听地址和端口
3. 安装项目运行依赖
4. 创建默认 `.env`
5. 生成 `systemd` 服务
6. 开机自启并立即启动服务

默认行为：

- 服务名：`emby-server-proxy`
- 监听地址：`0.0.0.0:3000`
- 运行目录：当前仓库目录
- 运行用户：执行 `sudo` 前的当前用户

交互安装时会提示你输入：

- 对外访问域名
- 服务监听地址
- 服务监听端口

如果你想跳过交互，直接通过环境变量指定，也可以这样执行：

```bash
sudo APP_DOMAIN=media.example.com PORT=3100 SERVICE_NAME=my-emby-proxy RUN_USER=www-data RUN_GROUP=www-data sh deploy/install.sh
```

支持的环境变量：

- `APP_NAME`
- `SERVICE_NAME`
- `APP_DIR`
- `RUN_USER`
- `RUN_GROUP`
- `HOST`
- `PORT`
- `TIME_ZONE`
- `REQUEST_TIMEOUT_MS`
- `TRUST_PROXY_HEADERS`
- `STATS_FILE`
- `MANUAL_REDIRECT_DOMAINS`
- `DOMAIN_PROXY_RULES`
- `JP_COLOS`
- `NODE_MAJOR`

## 三、手动启动项目

进入项目目录后执行：

```bash
npm install
npm run start
```

如果终端输出类似下面内容，说明服务已经正常监听：

```text
Emby server proxy listening on http://0.0.0.0:3000
```

## 四、配置 systemd

项目已提供示例文件：

```text
deploy/emby-proxy.service
```

把它放到：

```bash
/etc/systemd/system/emby-proxy.service
```

然后按你的实际路径修改：

- `WorkingDirectory`
- `EnvironmentFile`
- `ExecStart`
- `User`
- `Group`

启用服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now emby-proxy
sudo systemctl status emby-proxy
```

查看日志：

```bash
sudo journalctl -u emby-proxy -f
```

## 五、配置 nginx

项目提供示例文件：

```text
deploy/nginx.conf
```

关键点：

- `proxy_http_version 1.1`
- 透传 `Upgrade` 和 `Connection`
- 透传 `Host`、`X-Forwarded-*`
- 关闭缓冲 `proxy_buffering off`

部署步骤：

1. 按你的域名修改 `server_name`
2. 把 `proxy_pass` 指向 Node 服务端口
3. 测试配置：`sudo nginx -t`
4. 重载：`sudo systemctl reload nginx`

如果你还没有 HTTPS，可以再配合 `certbot` 签发证书。

## 六、配置 Caddy

项目提供示例文件：

```text
deploy/Caddyfile
```

Caddy 会自动处理 HTTPS。你只需要：

1. 改掉域名 `your.domain.example`
2. 确认反代目标是 `127.0.0.1:3000`
3. 重载配置：`sudo systemctl reload caddy`

## 七、验证

### 1. 健康检查

```bash
curl http://127.0.0.1:3000/health
```

### 2. 首页

```bash
curl http://127.0.0.1:3000/
```

### 3. 统计接口

```bash
curl http://127.0.0.1:3000/stats
```

### 4. 代理访问示例

```text
https://你的域名/http://emby.example.com:8096
https://你的域名/https://emby.example.com
```

## 八、统计数据说明

统计数据默认写入：

```text
./data/stats.json
```

会统计两类请求：

- `/Sessions/Playing`
- `/PlaybackInfo`

这是单机本地持久化方案，不需要额外数据库。

## 九、兼容原项目规则

本版本保留了以下行为：

- 目标地址仍从请求路径解析
- 保留手动重定向白名单
- 支持 WebSocket
- 支持原有日本节点域名改写逻辑

与原 Cloudflare Worker 版本相比，主要变化是：

- 运行时改为 Node.js
- D1 改为本地文件存储
- 部署方式改为 `systemd + nginx` 或 `systemd + Caddy`

## 十、常见问题

### 1. 为什么 `npm install` 很快结束？

因为当前版本没有额外第三方依赖，Node.js 标准库就可以运行。

### 2. 为什么统计没有数据？

只有命中 `/Sessions/Playing` 和 `/PlaybackInfo` 这两类请求时才会累计。

### 3. 如果我还想放在 Cloudflare 后面可以吗？

可以。本项目仍会在启用 `TRUST_PROXY_HEADERS=true` 时读取部分 `CF-*` 请求头，以兼容原来的日本节点规则。

### 4. 能不能多机部署共用统计？

当前默认方案不适合多机共享统计。如果后续你需要，我可以继续把统计层改成 SQLite 或 MySQL。
