import fs from 'fs';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { initDb } from '../db';
import { insertInviteCodes } from '../routes/invite';

const args = process.argv.slice(2);
let count = 100;
let batch = 'beta-100';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--count') count = Number(args[i + 1]) || 100;
  if (args[i] === '--batch') batch = args[i + 1] || batch;
}

async function main(): Promise<void> {
  await initDb();
  const codes = await insertInviteCodes(count, batch);
  const outDir = path.join(process.cwd(), 'data');
  fs.mkdirSync(outDir, { recursive: true });
  const csvPath = path.join(outDir, `invite-codes-${batch}.csv`);
  const sqlPath = path.join(outDir, `invite-codes-${batch}.sql`);
  const csv = ['code,batch', ...codes.map((c) => `${c},${batch}`)].join('\n');
  fs.writeFileSync(csvPath, csv);

  const ts = new Date().toISOString();
  const sqlLines = codes.map(
    (code) =>
      `INSERT INTO invite_codes (id, code, batch_name, free_comic_quota, status, created_at) VALUES ('${uuidv4()}', '${code}', '${batch}', 10, 'active', '${ts}');`,
  );
  fs.writeFileSync(
    sqlPath,
    `-- 梦悸邀请码批次 ${batch}，共 ${codes.length} 条\n-- 在腾讯云 CVM 上执行: mysql -h <内网IP> -u mengji -p mengji < invite-codes-${batch}.sql\n\n${sqlLines.join('\n')}\n`,
  );

  console.log(`Generated ${codes.length} codes`);
  console.log(`  CSV: ${csvPath}`);
  console.log(`  SQL: ${sqlPath}`);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
