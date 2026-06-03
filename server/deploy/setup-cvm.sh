#!/usr/bin/env bash
# 在全新 Ubuntu 22.04 CVM 上首次部署梦悸 API
# 用法: bash deploy/setup-cvm.sh
set -euo pipefail

APP_ROOT="${APP_ROOT:-/var/mengji/app}"
DATA_ROOT="${DATA_ROOT:-/var/mengji/data}"
LOG_ROOT="${LOG_ROOT:-/var/log/mengji}"

echo "==> 安装 Node.js 20 与 PM2"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs git nginx
fi
sudo npm install -g pm2

echo "==> 创建目录"
sudo mkdir -p "$APP_ROOT" "$DATA_ROOT" "$LOG_ROOT" /var/mengji/secrets
sudo chown -R "$USER:$USER" /var/mengji "$LOG_ROOT"

echo "==> 请在 $APP_ROOT 克隆仓库并配置 .env"
echo "    cd $APP_ROOT && git clone <repo-url> . && cd server"
echo "    cp .env.production.example .env   # 编辑填入密钥"
echo "    npm install && npm run build"
echo "    pm2 start deploy/ecosystem.config.js && pm2 save && pm2 startup"

echo "==> Nginx"
echo "    sudo cp deploy/nginx.conf /etc/nginx/sites-available/mengji-api"
echo "    sudo ln -sf /etc/nginx/sites-available/mengji-api /etc/nginx/sites-enabled/"
echo "    sudo nginx -t && sudo systemctl reload nginx"

echo "==> 验收: curl http://localhost:3000/health"
echo "    期望 aiMock: false（当 .env 中 AI_MOCK=false）"
