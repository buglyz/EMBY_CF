#!/usr/bin/env sh

set -eu

APT_UPDATED=false

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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [ "$(id -u)" -eq 0 ]; then
    return
  fi

  if command_exists sudo; then
    PRESERVE_ENV="APP_NAME,APP_DOMAIN,SERVICE_NAME,APP_DIR,RUN_USER,RUN_GROUP,HOST,PORT,TIME_ZONE,REQUEST_TIMEOUT_MS,TRUST_PROXY_HEADERS,STATS_FILE,MANUAL_REDIRECT_DOMAINS,DOMAIN_PROXY_RULES,JP_COLOS,NODE_MAJOR,OVERWRITE_ENV,PROXY_CHOICE,ENABLE_HTTPS,NGINX_USE_CERTBOT,ACME_EMAIL,SSL_CERT_PATH,SSL_KEY_PATH"
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
    ANSWER="$CURRENT_VALUE"
  elif is_interactive; then
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

prompt_proxy_choice() {
  CURRENT_VALUE="${PROXY_CHOICE:-}"

  if [ -n "$CURRENT_VALUE" ]; then
    ANSWER="$CURRENT_VALUE"
  elif is_interactive; then
    printf '%s [%s]: ' "请选择反向代理类型 (none/nginx/caddy)" "caddy"
    IFS= read -r ANSWER || ANSWER=""
    if [ -z "$ANSWER" ]; then
      ANSWER="caddy"
    fi
  else
    ANSWER="caddy"
  fi

  ANSWER="$(printf '%s' "$ANSWER" | tr '[:upper:]' '[:lower:]')"
  case "$ANSWER" in
    1) ANSWER="none" ;;
    2) ANSWER="nginx" ;;
    3) ANSWER="caddy" ;;
    none|nginx|caddy) ;;
    *) die "反向代理类型只能是 none、nginx 或 caddy。" ;;
  esac

  PROXY_CHOICE="$ANSWER"
}

detect_package_manager() {
  if command_exists apt-get; then
    PKG_MANAGER="apt"
  elif command_exists dnf; then
    PKG_MANAGER="dnf"
  elif command_exists yum; then
    PKG_MANAGER="yum"
  else
    die "未识别到受支持的包管理器。"
  fi
}

apt_update_once() {
  if [ "$APT_UPDATED" = "true" ]; then
    return
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  APT_UPDATED=true
}

install_packages() {
  detect_package_manager

  case "$PKG_MANAGER" in
    apt)
      apt_update_once
      export DEBIAN_FRONTEND=noninteractive
      apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    yum)
      yum install -y "$@"
      ;;
  esac
}

current_major_version() {
  if ! command_exists node; then
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
  detect_package_manager

  case "$PKG_MANAGER" in
    apt)
      install_packages ca-certificates curl gnupg
      install -d -m 0755 /etc/apt/keyrings
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
      printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_%s.x nodistro main\n' "$REQUIRED_NODE_MAJOR" \
        > /etc/apt/sources.list.d/nodesource.list
      APT_UPDATED=false
      install_packages nodejs
      ;;
    dnf)
      curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | bash -
      dnf install -y nodejs
      ;;
    yum)
      curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | bash -
      yum install -y nodejs
      ;;
  esac

  CURRENT_NODE_MAJOR="$(current_major_version)"
  if [ "$CURRENT_NODE_MAJOR" -lt "$REQUIRED_NODE_MAJOR" ]; then
    die "Node.js 安装失败，当前版本仍低于 ${REQUIRED_NODE_MAJOR}。"
  fi

  log "Node.js 安装完成。"
}

install_nginx() {
  if command_exists nginx; then
    log "检测到 nginx 已安装。"
    return
  fi

  log "开始安装 nginx ..."
  install_packages nginx
}

install_caddy() {
  if command_exists caddy; then
    log "检测到 Caddy 已安装。"
    return
  fi

  log "开始安装 Caddy ..."
  detect_package_manager

  case "$PKG_MANAGER" in
    apt)
      CADDY_KEYRING_PATH="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
      CADDY_APT_SOURCE_FILE="/etc/apt/sources.list.d/caddy-stable.list"

      rm -f "$CADDY_APT_SOURCE_FILE"
      install_packages ca-certificates curl gnupg debian-keyring debian-archive-keyring apt-transport-https
      install -d -m 0755 /usr/share/keyrings
      if [ ! -f "$CADDY_KEYRING_PATH" ]; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
          | gpg --dearmor -o "$CADDY_KEYRING_PATH"
      fi
      curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        > "$CADDY_APT_SOURCE_FILE"
      APT_UPDATED=false
      install_packages caddy
      ;;
    dnf)
      install_packages 'dnf-command(config-manager)' ca-certificates curl
      if [ ! -f /etc/yum.repos.d/caddy-stable.repo ]; then
        dnf config-manager --add-repo https://dl.cloudsmith.io/public/caddy/stable/rpm.repo
      fi
      dnf install -y caddy
      ;;
    yum)
      install_packages yum-utils ca-certificates curl
      if [ ! -f /etc/yum.repos.d/caddy-stable.repo ]; then
        yum-config-manager --add-repo https://dl.cloudsmith.io/public/caddy/stable/rpm.repo
      fi
      yum install -y caddy
      ;;
  esac
}

install_certbot_for_nginx() {
  if command_exists certbot; then
    log "检测到 certbot 已安装。"
    return
  fi

  log "开始安装 certbot nginx 插件 ..."
  install_packages certbot python3-certbot-nginx
}

ensure_systemd() {
  if ! command_exists systemctl; then
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

write_nginx_config() {
  TARGET_FILE="$1"
  SERVER_NAME="${APP_DOMAIN:-_}"
  PROXY_UPSTREAM_HOST="$(format_proxy_upstream_host "$HOST")"

  if [ "$ENABLE_HTTPS" = "true" ] && [ "$NGINX_USE_CERTBOT" = "false" ]; then
    cat > "$TARGET_FILE" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name $SERVER_NAME;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name $SERVER_NAME;

    ssl_certificate $SSL_CERT_PATH;
    ssl_certificate_key $SSL_KEY_PATH;

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
    return
  fi

  cat > "$TARGET_FILE" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name $SERVER_NAME;

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
}

write_caddy_config() {
  TARGET_FILE="$1"
  PROXY_UPSTREAM_HOST="$(format_proxy_upstream_host "$HOST")"

  if [ "$ENABLE_HTTPS" = "true" ]; then
    SITE_ADDRESS="$APP_DOMAIN"
  elif [ -n "$APP_DOMAIN" ]; then
    SITE_ADDRESS="http://$APP_DOMAIN"
  else
    SITE_ADDRESS=":80"
  fi

  cat > "$TARGET_FILE" <<EOF
$SITE_ADDRESS {
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

generate_proxy_config() {
  GENERATED_DIR="$APP_DIR/deploy/generated"
  mkdir -p "$GENERATED_DIR"

  case "$PROXY_CHOICE" in
    none)
      return
      ;;
    nginx)
      LOCAL_PROXY_CONFIG="$GENERATED_DIR/nginx.${SERVICE_NAME}.conf"
      log "生成 nginx 配置：$LOCAL_PROXY_CONFIG"
      write_nginx_config "$LOCAL_PROXY_CONFIG"
      ;;
    caddy)
      LOCAL_PROXY_CONFIG="$GENERATED_DIR/Caddyfile.${SERVICE_NAME}"
      log "生成 Caddy 配置：$LOCAL_PROXY_CONFIG"
      write_caddy_config "$LOCAL_PROXY_CONFIG"
      ;;
  esac
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

reload_and_start_app_service() {
  log "重新加载 systemd 并启动应用服务 ..."
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    die "应用服务启动失败，请查看上面的 systemd 状态输出。"
  fi
}

ensure_caddy_import() {
  CADDY_MAIN_FILE="/etc/caddy/Caddyfile"
  CADDY_SITE_DIR="/etc/caddy/sites"
  mkdir -p "$CADDY_SITE_DIR"

  if [ ! -f "$CADDY_MAIN_FILE" ]; then
    printf 'import /etc/caddy/sites/*.caddy\n' > "$CADDY_MAIN_FILE"
    return
  fi

  if ! grep -qF 'import /etc/caddy/sites/*.caddy' "$CADDY_MAIN_FILE"; then
    printf '\nimport /etc/caddy/sites/*.caddy\n' >> "$CADDY_MAIN_FILE"
  fi
}

configure_nginx_proxy() {
  install_nginx

  NGINX_SITE_FILE="/etc/nginx/conf.d/${SERVICE_NAME}.conf"
  write_nginx_config "$LOCAL_PROXY_CONFIG"
  cp "$LOCAL_PROXY_CONFIG" "$NGINX_SITE_FILE"

  nginx -t
  systemctl enable --now nginx
  systemctl restart nginx

  if [ "$ENABLE_HTTPS" = "true" ] && [ "$NGINX_USE_CERTBOT" = "true" ]; then
    install_certbot_for_nginx
    certbot --nginx --non-interactive --agree-tos --no-eff-email -m "$ACME_EMAIL" -d "$APP_DOMAIN" --redirect
    systemctl reload nginx
  fi

  INSTALLED_PROXY_CONFIG="$NGINX_SITE_FILE"
}

configure_caddy_proxy() {
  install_caddy
  ensure_caddy_import

  CADDY_SITE_FILE="/etc/caddy/sites/${SERVICE_NAME}.caddy"
  write_caddy_config "$LOCAL_PROXY_CONFIG"
  cp "$LOCAL_PROXY_CONFIG" "$CADDY_SITE_FILE"

  caddy validate --config /etc/caddy/Caddyfile
  systemctl enable --now caddy
  systemctl restart caddy

  INSTALLED_PROXY_CONFIG="$CADDY_SITE_FILE"
}

configure_selected_proxy() {
  INSTALLED_PROXY_CONFIG=""

  case "$PROXY_CHOICE" in
    none)
      log "未选择安装反向代理，仅部署 Node.js 服务。"
      ;;
    nginx)
      configure_nginx_proxy
      ;;
    caddy)
      configure_caddy_proxy
      ;;
  esac
}

validate_port() {
  case "$PORT" in
    ""|*[!0-9]*)
      die "监听端口必须是数字。"
      ;;
  esac

  if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    die "监听端口必须在 1 到 65535 之间。"
  fi
}

validate_proxy_options() {
  validate_port

  case "$PROXY_CHOICE" in
    none)
      return
      ;;
    nginx|caddy)
      ;;
    *)
      die "反向代理类型只能是 none、nginx 或 caddy。"
      ;;
  esac

  if [ "$ENABLE_HTTPS" = "true" ] && [ -z "$APP_DOMAIN" ]; then
    die "启用 HTTPS 时必须提供域名。"
  fi

  if [ "$PROXY_CHOICE" = "nginx" ] && [ "$ENABLE_HTTPS" = "true" ]; then
    if [ "$NGINX_USE_CERTBOT" = "true" ]; then
      [ -n "$ACME_EMAIL" ] || die "使用 certbot 自动申请证书时必须提供邮箱。"
    else
      [ -n "$SSL_CERT_PATH" ] || die "启用 nginx HTTPS 时必须提供证书文件路径。"
      [ -n "$SSL_KEY_PATH" ] || die "启用 nginx HTTPS 时必须提供私钥文件路径。"
      [ -f "$SSL_CERT_PATH" ] || die "证书文件不存在: $SSL_CERT_PATH"
      [ -f "$SSL_KEY_PATH" ] || die "私钥文件不存在: $SSL_KEY_PATH"
    fi
  fi
}

show_summary() {
  log "部署完成。"
  log "服务名称: $SERVICE_NAME"
  log "项目目录: $APP_DIR"
  log "运行用户: $RUN_USER:$RUN_GROUP"
  log "监听地址: $HOST:$PORT"
  log "反向代理: $PROXY_CHOICE"

  if [ "$PROXY_CHOICE" != "none" ]; then
    log "HTTPS: $ENABLE_HTTPS"
    if [ -n "$APP_DOMAIN" ]; then
      log "访问域名: $APP_DOMAIN"
    fi
    if [ -n "$LOCAL_PROXY_CONFIG" ]; then
      log "生成配置: $LOCAL_PROXY_CONFIG"
    fi
    if [ -n "$INSTALLED_PROXY_CONFIG" ]; then
      log "系统配置: $INSTALLED_PROXY_CONFIG"
    fi
  fi

  log "环境文件: $ENV_FILE"
  log "查看应用状态: systemctl status $SERVICE_NAME"
  log "查看应用日志: journalctl -u $SERVICE_NAME -f"

  case "$PROXY_CHOICE" in
    nginx)
      log "查看 nginx 状态: systemctl status nginx"
      ;;
    caddy)
      log "查看 Caddy 状态: systemctl status caddy"
      ;;
  esac
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
PROXY_CHOICE="${PROXY_CHOICE:-}"
ENABLE_HTTPS="${ENABLE_HTTPS:-}"
NGINX_USE_CERTBOT="${NGINX_USE_CERTBOT:-}"
ACME_EMAIL="${ACME_EMAIL:-}"
SSL_CERT_PATH="${SSL_CERT_PATH:-}"
SSL_KEY_PATH="${SSL_KEY_PATH:-}"
LOCAL_PROXY_CONFIG=""
INSTALLED_PROXY_CONFIG=""

[ -f "$APP_DIR/server.js" ] || die "未在 $APP_DIR 找到 server.js，请确认脚本位于仓库的 deploy 目录中。"

if [ -f "$ENV_FILE" ]; then
  prompt_yes_no OVERWRITE_ENV "如果存在 .env，是否覆盖现有配置" "no"
  if [ "$OVERWRITE_ENV" = "false" ]; then
    load_existing_env_file
  fi
else
  OVERWRITE_ENV="${OVERWRITE_ENV:-true}"
fi

prompt_optional APP_DOMAIN "请输入反向代理使用的域名"

if [ "$OVERWRITE_ENV" = "true" ] || [ ! -f "$ENV_FILE" ]; then
  prompt_with_default HOST "请输入服务监听地址" "0.0.0.0"
  prompt_with_default PORT "请输入服务监听端口" "3000"
fi

prompt_proxy_choice

if [ "$PROXY_CHOICE" != "none" ]; then
  prompt_yes_no ENABLE_HTTPS "是否启用 HTTPS" "no"

  if [ "$PROXY_CHOICE" = "nginx" ] && [ "$ENABLE_HTTPS" = "true" ]; then
    prompt_yes_no NGINX_USE_CERTBOT "nginx HTTPS 是否使用 certbot 自动申请证书" "yes"

    if [ "$NGINX_USE_CERTBOT" = "true" ]; then
      prompt_with_default ACME_EMAIL "请输入 certbot 使用的邮箱" "admin@${APP_DOMAIN:-example.com}"
    else
      prompt_with_default SSL_CERT_PATH "请输入现有 SSL 证书路径" "/etc/ssl/${SERVICE_NAME}.crt"
      prompt_with_default SSL_KEY_PATH "请输入现有 SSL 私钥路径" "/etc/ssl/private/${SERVICE_NAME}.key"
    fi
  fi
fi

validate_proxy_options
install_nodejs
mkdir -p "$APP_DIR/data"
write_env_file
install_dependencies
chown -R "$RUN_USER:$RUN_GROUP" "$APP_DIR"
write_service_file
reload_and_start_app_service
generate_proxy_config
configure_selected_proxy
show_summary
