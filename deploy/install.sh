#!/usr/bin/env sh

set -eu

log() {
  printf '%s\n' "[install] $*"
}

warn() {
  printf '%s\n' "[install] WARN: $*" >&2
}

die() {
  printf '%s\n' "[install] ERROR: $*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -eq 0 ]; then
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    PRESERVE_ENV="APP_NAME,APP_DOMAIN,SERVICE_NAME,APP_DIR,RUN_USER,RUN_GROUP,HOST,PORT,TIME_ZONE,REQUEST_TIMEOUT_MS,TRUST_PROXY_HEADERS,STATS_FILE,MANUAL_REDIRECT_DOMAINS,DOMAIN_PROXY_RULES,JP_COLOS,NODE_MAJOR,OVERWRITE_ENV"
    exec sudo --preserve-env="$PRESERVE_ENV" sh "$0" "$@"
  fi

  die "请使用 root 或 sudo 运行此脚本。"
}

is_interactive() {
  [ -t 0 ] && [ -t 1 ]
}

prompt_with_default() {
  VAR_NAME="$1"
  LABEL="$2"
  DEFAULT_VALUE="$3"
  CURRENT_VALUE="$(eval "printf '%s' \"\${$VAR_NAME-}\"")"

  if [ -n "$CURRENT_VALUE" ]; then
    return
  fi

  if is_interactive; then
    printf '%s [%s]: ' "$LABEL" "$DEFAULT_VALUE"
    IFS= read -r ANSWER || ANSWER=""
    if [ -z "$ANSWER" ]; then
      ANSWER="$DEFAULT_VALUE"
    fi
  else
    ANSWER="$DEFAULT_VALUE"
  fi

  eval "$VAR_NAME=\$ANSWER"
}

prompt_optional() {
  VAR_NAME="$1"
  LABEL="$2"
  CURRENT_VALUE="$(eval "printf '%s' \"\${$VAR_NAME-}\"")"

  if [ -n "$CURRENT_VALUE" ]; then
    return
  fi

  if is_interactive; then
    printf '%s [留空跳过]: ' "$LABEL"
    IFS= read -r ANSWER || ANSWER=""
  else
    ANSWER=""
  fi

  eval "$VAR_NAME=\$ANSWER"
}

prompt_yes_no() {
  VAR_NAME="$1"
  LABEL="$2"
  DEFAULT_VALUE="$3"
  CURRENT_VALUE="$(eval "printf '%s' \"\${$VAR_NAME-}\"")"

  if [ -n "$CURRENT_VALUE" ]; then
    return
  fi

  if is_interactive; then
    printf '%s [%s]: ' "$LABEL" "$DEFAULT_VALUE"
    IFS= read -r ANSWER || ANSWER=""
    if [ -z "$ANSWER" ]; then
      ANSWER="$DEFAULT_VALUE"
    fi
  else
    ANSWER="$DEFAULT_VALUE"
  fi

  ANSWER="$(printf '%s' "$ANSWER" | tr '[:upper:]' '[:lower:]')"
  case "$ANSWER" in
    y|yes|1|true) ANSWER="true" ;;
    n|no|0|false) ANSWER="false" ;;
    *) die "$LABEL 请输入 yes 或 no。" ;;
  esac

  eval "$VAR_NAME=\$ANSWER"
}

current_major_version() {
  if ! command -v node >/dev/null 2>&1; then
    printf '0'
    return
  fi

  node -p "process.versions.node.split('.')[0]"
}

install_nodejs() {
  REQUIRED_NODE_MAJOR="${NODE_MAJOR:-20}"
  CURRENT_NODE_MAJOR="$(current_major_version)"

  if [ "$CURRENT_NODE_MAJOR" -ge "$REQUIRED_NODE_MAJOR" ]; then
    log "检测到 Node.js v$CURRENT_NODE_MAJOR，满足要求。"
    return
  fi

  log "开始安装 Node.js ${REQUIRED_NODE_MAJOR}.x ..."

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_%s.x nodistro main\n' "$REQUIRED_NODE_MAJOR" \
      > /etc/apt/sources.list.d/nodesource.list
    apt-get update
    apt-get install -y nodejs
  elif command -v dnf >/dev/null 2>&1; then
    curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | bash -
    dnf install -y nodejs
  elif command -v yum >/dev/null 2>&1; then
    curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | bash -
    yum install -y nodejs
  else
    die "未识别到受支持的包管理器，无法自动安装 Node.js。请先手动安装 Node.js ${REQUIRED_NODE_MAJOR}+。"
  fi

  CURRENT_NODE_MAJOR="$(current_major_version)"
  if [ "$CURRENT_NODE_MAJOR" -lt "$REQUIRED_NODE_MAJOR" ]; then
    die "Node.js 安装失败，当前版本仍低于 ${REQUIRED_NODE_MAJOR}。"
  fi

  log "Node.js 安装完成。"
}

ensure_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    die "当前系统未检测到 systemd，无法创建保活服务。"
  fi

  if [ ! -d /run/systemd/system ]; then
    die "当前系统未以 systemd 作为 init 运行，无法自动注册服务。"
  fi
}

strip_wrapping_quotes() {
  VALUE="$1"

  case "$VALUE" in
    \"*\")
      VALUE=${VALUE#\"}
      VALUE=${VALUE%\"}
      ;;
    \'*\')
      VALUE=${VALUE#\'}
      VALUE=${VALUE%\'}
      ;;
  esac

  printf '%s' "$VALUE"
}

load_existing_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    return
  fi

  while IFS= read -r RAW_LINE || [ -n "$RAW_LINE" ]; do
    LINE="$(printf '%s' "$RAW_LINE" | tr -d '\r')"

    case "$LINE" in
      ""|\#*)
        continue
        ;;
    esac

    KEY=${LINE%%=*}
    VALUE=${LINE#*=}
    VALUE="$(strip_wrapping_quotes "$VALUE")"

    case "$KEY" in
      HOST) HOST="$VALUE" ;;
      PORT) PORT="$VALUE" ;;
      TIME_ZONE) TIME_ZONE="$VALUE" ;;
      STATS_FILE) STATS_FILE="$VALUE" ;;
      REQUEST_TIMEOUT_MS) REQUEST_TIMEOUT_MS="$VALUE" ;;
      TRUST_PROXY_HEADERS) TRUST_PROXY_HEADERS="$VALUE" ;;
      MANUAL_REDIRECT_DOMAINS) MANUAL_REDIRECT_DOMAINS="$VALUE" ;;
      DOMAIN_PROXY_RULES) DOMAIN_PROXY_RULES="$VALUE" ;;
      JP_COLOS) JP_COLOS="$VALUE" ;;
    esac
  done < "$ENV_FILE"
}

format_proxy_upstream_host() {
  SELECTED_HOST="$1"

  case "$SELECTED_HOST" in
    ""|"0.0.0.0")
      printf '%s' "127.0.0.1"
      ;;
    "::"|"::0"|"[::]")
      printf '%s' "[::1]"
      ;;
    \[*\])
      printf '%s' "$SELECTED_HOST"
      ;;
    *:*)
      printf '[%s]' "$SELECTED_HOST"
      ;;
    *)
      printf '%s' "$SELECTED_HOST"
      ;;
  esac
}

write_env_file() {
  if [ -f "$ENV_FILE" ]; then
    if [ "$OVERWRITE_ENV" = "true" ]; then
      log "检测到现有 .env，将按本次交互配置覆盖：$ENV_FILE"
    else
      log "检测到现有 .env，保留原配置：$ENV_FILE"
      load_existing_env_file
      return
    fi
  fi

  log "创建默认 .env 配置：$ENV_FILE"

  cat > "$ENV_FILE" <<EOF
HOST=$HOST
PORT=$PORT
TIME_ZONE=$TIME_ZONE
STATS_FILE=$STATS_FILE
REQUEST_TIMEOUT_MS=$REQUEST_TIMEOUT_MS
TRUST_PROXY_HEADERS=$TRUST_PROXY_HEADERS
EOF

  if [ -n "${MANUAL_REDIRECT_DOMAINS:-}" ]; then
    printf 'MANUAL_REDIRECT_DOMAINS=%s\n' "$MANUAL_REDIRECT_DOMAINS" >> "$ENV_FILE"
  else
    printf '# MANUAL_REDIRECT_DOMAINS=\n' >> "$ENV_FILE"
  fi

  if [ -n "${DOMAIN_PROXY_RULES:-}" ]; then
    printf 'DOMAIN_PROXY_RULES=%s\n' "$DOMAIN_PROXY_RULES" >> "$ENV_FILE"
  else
    printf '# DOMAIN_PROXY_RULES=\n' >> "$ENV_FILE"
  fi

  if [ -n "${JP_COLOS:-}" ]; then
    printf 'JP_COLOS=%s\n' "$JP_COLOS" >> "$ENV_FILE"
  else
    printf '# JP_COLOS=NRT,KIX,FUK,OKA\n' >> "$ENV_FILE"
  fi
}

generate_proxy_configs() {
  GENERATED_DIR="$APP_DIR/deploy/generated"
  mkdir -p "$GENERATED_DIR"

  if [ -z "$APP_DOMAIN" ]; then
    warn "未填写域名，跳过生成 nginx/Caddy 域名配置。"
    return
  fi

  NGINX_FILE="$GENERATED_DIR/nginx.${SERVICE_NAME}.conf"
  CADDY_FILE="$GENERATED_DIR/Caddyfile.${SERVICE_NAME}"
  PROXY_UPSTREAM_HOST="$(format_proxy_upstream_host "$HOST")"

  log "生成 nginx 配置：$NGINX_FILE"
  cat > "$NGINX_FILE" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name $APP_DOMAIN;

    client_max_body_size 0;

    location / {
        proxy_pass http://$PROXY_UPSTREAM_HOST:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
EOF

  log "生成 Caddy 配置：$CADDY_FILE"
  cat > "$CADDY_FILE" <<EOF
$APP_DOMAIN {
    encode zstd gzip

    reverse_proxy $PROXY_UPSTREAM_HOST:$PORT {
        header_up Host {host}
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote}
        header_up X-Real-IP {remote}
        flush_interval -1
    }
}
EOF
}

install_dependencies() {
  log "安装项目运行依赖 ..."
  cd "$APP_DIR"
  npm install --omit=dev --no-package-lock
}

write_service_file() {
  NODE_BIN="$(command -v node)"

  log "写入 systemd 服务：$SERVICE_FILE"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=$APP_NAME
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=NODE_ENV=production
EnvironmentFile=$ENV_FILE
ExecStart=$NODE_BIN $APP_DIR/server.js
Restart=always
RestartSec=5
User=$RUN_USER
Group=$RUN_GROUP
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  chmod 0644 "$SERVICE_FILE"
}

reload_and_start_service() {
  log "重新加载 systemd 并启动服务 ..."
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    die "服务启动失败，请查看上面的 systemd 状态输出。"
  fi
}

show_summary() {
  log "部署完成。"
  log "服务名称: $SERVICE_NAME"
  log "项目目录: $APP_DIR"
  log "运行用户: $RUN_USER:$RUN_GROUP"
  log "监听地址: $HOST:$PORT"
  if [ -n "$APP_DOMAIN" ]; then
    log "访问域名: $APP_DOMAIN"
    log "nginx 配置: $APP_DIR/deploy/generated/nginx.${SERVICE_NAME}.conf"
    log "Caddy 配置: $APP_DIR/deploy/generated/Caddyfile.${SERVICE_NAME}"
  fi
  log "环境文件: $ENV_FILE"
  log "查看状态: systemctl status $SERVICE_NAME"
  log "查看日志: journalctl -u $SERVICE_NAME -f"
}

require_root "$@"
ensure_systemd

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-Emby Server Proxy}"
SERVICE_NAME="${SERVICE_NAME:-emby-server-proxy}"
APP_DIR_INPUT="${APP_DIR:-$REPO_DIR}"
APP_DIR="$(CDPATH= cd -- "$APP_DIR_INPUT" && pwd)"
APP_DOMAIN="${APP_DOMAIN:-}"

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  DEFAULT_RUN_USER="$SUDO_USER"
else
  DEFAULT_RUN_USER="$(id -un)"
fi

RUN_USER="${RUN_USER:-$DEFAULT_RUN_USER}"
id "$RUN_USER" >/dev/null 2>&1 || die "运行用户不存在: $RUN_USER"
DEFAULT_RUN_GROUP="$(id -gn "$RUN_USER")"
RUN_GROUP="${RUN_GROUP:-$DEFAULT_RUN_GROUP}"
HOST="${HOST:-}"
PORT="${PORT:-}"
TIME_ZONE="${TIME_ZONE:-Asia/Shanghai}"
REQUEST_TIMEOUT_MS="${REQUEST_TIMEOUT_MS:-300000}"
TRUST_PROXY_HEADERS="${TRUST_PROXY_HEADERS:-true}"
STATS_FILE="${STATS_FILE:-$APP_DIR/data/stats.json}"
ENV_FILE="$APP_DIR/.env"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
OVERWRITE_ENV="${OVERWRITE_ENV:-}"

[ -f "$APP_DIR/server.js" ] || die "未在 $APP_DIR 找到 server.js，请确认脚本位于仓库的 deploy 目录中。"

prompt_optional APP_DOMAIN "请输入反向代理使用的域名"
prompt_with_default HOST "请输入服务监听地址" "0.0.0.0"
prompt_with_default PORT "请输入服务监听端口" "3000"
prompt_yes_no OVERWRITE_ENV "如果存在 .env，是否覆盖现有配置" "no"

install_nodejs
mkdir -p "$APP_DIR/data"
write_env_file
install_dependencies
chown -R "$RUN_USER:$RUN_GROUP" "$APP_DIR"
write_service_file
generate_proxy_configs
reload_and_start_service
show_summary
