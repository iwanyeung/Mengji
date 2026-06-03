/**
 * 将 CSV 邀请码导入数据库（用于腾讯云 TencentDB MySQL）
 * 用法:
 *   MYSQL_URL=mysql://user:pass@host:3306/mengji npm run invite:import -- --file data/invite-codes-beta-100.csv
 *   npm run invite:import -- --file data/invite-codes-beta-100.csv --mysql-url mysql://...
 */
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { v4 as uuidv4 } from 'uuid';
import { initDb, nowIso } from '../db';

dotenv.config();

function parseArgs(): { file: string; mysqlUrl?: string } {
  const args = process.argv.slice(2);
  let file = '';
  let mysqlUrl: string | undefined;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--file') file = args[i + 1] || '';
    if (args[i] === '--mysql-url') mysqlUrl = args[i + 1];
  }
  if (!file) {
    console.error('用法: npm run invite:import -- --file data/invite-codes-xxx.csv [--mysql-url mysql://...]');
    process.exit(1);
  }
  return { file, mysqlUrl };
}

async function main(): Promise<void> {
  const { file, mysqlUrl } = parseArgs();
  const csvPath = path.isAbsolute(file) ? file : path.join(process.cwd(), file);
  if (!fs.existsSync(csvPath)) {
    console.error('文件不存在:', csvPath);
    process.exit(1);
  }

  if (mysqlUrl) {
    process.env.MYSQL_URL = mysqlUrl;
  }
  if (!process.env.MYSQL_URL) {
    console.error('请设置 MYSQL_URL 环境变量，或使用 --mysql-url');
    process.exit(1);
  }

  const lines = fs
    .readFileSync(csvPath, 'utf8')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);
  const rows = lines.slice(1).map((line) => {
    const [code, batch] = line.split(',');
    return { code: code?.trim().toUpperCase(), batch: batch?.trim() || 'imported' };
  });

  const db = await initDb();
  const ts = nowIso();
  let inserted = 0;
  let skipped = 0;

  for (const row of rows) {
    if (!row.code) continue;
    const existing = await db.queryOne(`SELECT 1 AS ok FROM invite_codes WHERE code = ?`, [row.code]);
    if (existing) {
      skipped += 1;
      continue;
    }
    await db.execute(
      `INSERT INTO invite_codes (id, code, batch_name, free_comic_quota, status, created_at) VALUES (?, ?, ?, 10, ?, ?)`,
      [uuidv4(), row.code, row.batch, 'active', ts],
    );
    inserted += 1;
  }

  console.log(`导入完成: 新增 ${inserted} 条，跳过 ${skipped} 条（已存在）`);
  console.log(`数据库: MySQL (${process.env.MYSQL_URL.replace(/:[^:@/]+@/, ':***@')})`);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
