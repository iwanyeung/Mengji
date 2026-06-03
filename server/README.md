# 梦悸后端 API

Node.js + Express，代理 DeepSeek（文本梦析）与火山引擎（豆包语音 ASR + Seedream 文生图）。

## 快速开始

```bash
cd server
cp .env.example .env
# 编辑 .env 填入密钥；本地开发可保持 AI_MOCK=true
npm install
npm run dev
```

健康检查：`GET http://localhost:3000/health`

## 凭证清单

见 `.env.example` 与 `.env.production.example`。生产环境请勿提交 `.env`。

| 变量 | 说明 |
|------|------|
| `MYSQL_URL` | 生产 MySQL 连接串；未配置则用 SQLite |
| `COS_*` | 腾讯云 COS；未配置则用本地 `data/uploads` |
| `AI_MOCK=false` | 生产必须关闭 Mock |
| `APPLE_IAP_SKIP_VERIFY` | 内测 `true`；ASC 就绪后 `false` 并配置 `.p8` |

## 邀请码

```bash
# 1. 本地生成（写入当前数据库 + 导出 CSV/SQL）
npm run invite:generate -- --count 100 --batch beta-20250603

# 输出:
#   data/invite-codes-<batch>.csv
#   data/invite-codes-<batch>.sql
```

### 导入腾讯云

**方式 A — CVM 上使用 MySQL（TencentDB，推荐）**

```bash
# 在 Mac 上传 SQL 到 CVM
scp data/invite-codes-beta-20250603.sql user@<CVM公网IP>:/var/mengji/app/server/data/

# SSH 登录 CVM 后
cd /var/mengji/app/server
mysql -h <MySQL内网IP> -u mengji -p mengji < data/invite-codes-beta-20250603.sql
```

**方式 B — 使用 import 脚本（需 .env 中 MYSQL_URL）**

```bash
MYSQL_URL=mysql://mengji:password@10.x.x.x:3306/mengji npm run invite:import -- --file data/invite-codes-beta-20250603.csv
```

**方式 C — CVM 使用 SQLite（未配 MYSQL_URL 时）**

```bash
scp data/invite-codes-beta-20250603.sql user@<CVM>:/var/mengji/app/server/data/
ssh user@<CVM> "sqlite3 /var/mengji/data/mengji.db < /var/mengji/app/server/data/invite-codes-beta-20250603.sql"
```

或在 CVM 上直接生成：`npm run invite:generate -- --count 100 --batch beta-20250603`

## 部署（腾讯云 CVM）

### 1. 首次安装

```bash
bash deploy/setup-cvm.sh
cd /var/mengji/app/server
cp .env.production.example .env   # 填入密钥
npm install && npm run build
pm2 start deploy/ecosystem.config.js
pm2 save && pm2 startup
```

### 2. Nginx

```bash
sudo cp deploy/nginx.conf /etc/nginx/sites-available/mengji-api
sudo ln -sf /etc/nginx/sites-available/mengji-api /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### 3. MySQL

在 CVM 上用 **内网地址** 连接 TencentDB MySQL，执行：

```bash
mysql -h 10.x.x.x -u mengji -p mengji < docs/schema.sql
```

`.env` 中设置：

```
MYSQL_URL=mysql://mengji:password@10.x.x.x:3306/mengji
```

服务启动时会自动 migrate 建表（与 schema.sql 一致）。

### 4. COS

私有读写桶，与 CVM 同地域。配置 `COS_SECRET_ID`、`COS_SECRET_KEY`、`COS_BUCKET`、`COS_REGION`。

### 5. HTTPS（域名备案后）

参考 `deploy/nginx-ssl.conf`，更新 `PUBLIC_BASE_URL=https://api.yourdomain.com` 并 `pm2 restart mengji-api`。

### 验收

```bash
curl http://YOUR_HOST/health
# 期望: aiMock: false, database: mysql, storage: cos
```
