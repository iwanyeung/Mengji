#!/usr/bin/env bash
# 在腾讯云 CVM 上导入邀请码（MySQL 或 SQLite 生产库）
# 用法（在 CVM 上，server 目录内）:
#   bash deploy/import-invite-codes-cvm.sh data/invite-codes-beta-20250603.sql
set -euo pipefail

SQL_FILE="${1:-}"
if [[ -z "$SQL_FILE" || ! -f "$SQL_FILE" ]]; then
  echo "用法: bash deploy/import-invite-codes-cvm.sh <invite-codes-xxx.sql>"
  exit 1
fi

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -n "${MYSQL_URL:-}" ]]; then
  echo "==> 导入 MySQL（TencentDB）"
  # 从 mysql://user:pass@host:3306/db 解析（简化：直接用 Node 脚本更稳）
  npm run invite:import -- --file "${SQL_FILE%.sql}.csv" 2>/dev/null || {
    echo "若 CSV 同目录不存在，改用 mysql 客户端:"
    echo "  mysql -h <内网IP> -u mengji -p mengji < $SQL_FILE"
    exit 1
  }
elif [[ -n "${DATABASE_PATH:-}" && -f "$DATABASE_PATH" ]]; then
  echo "==> 导入 SQLite: $DATABASE_PATH"
  sqlite3 "$DATABASE_PATH" < "$SQL_FILE"
  COUNT=$(sqlite3 "$DATABASE_PATH" "SELECT COUNT(*) FROM invite_codes WHERE status='active';")
  echo "当前 active 邀请码总数: $COUNT"
else
  echo "未找到 MYSQL_URL 或 DATABASE_PATH，请先配置 server/.env"
  exit 1
fi

echo "==> 导入完成"
