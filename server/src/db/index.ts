import { env } from '../config/env';
import { createMysqlClient } from './mysql';
import { createSqliteClient } from './sqlite';
import type { DbClient } from './types';

export { nowIso } from './types';
export type { DbClient, DbRow } from './types';
export { dailyAnalysisUpsertSql } from './schema';

let client: DbClient | null = null;

export async function initDb(): Promise<DbClient> {
  if (client) return client;

  if (env.mysqlUrl) {
    client = await createMysqlClient(env.mysqlUrl);
    console.log('Database: MySQL');
  } else {
    client = createSqliteClient(env.databasePath);
    console.log(`Database: SQLite (${env.databasePath})`);
  }

  await client.migrate();
  return client;
}

export function getDb(): DbClient {
  if (!client) {
    throw new Error('Database not initialized — call initDb() at startup');
  }
  return client;
}
