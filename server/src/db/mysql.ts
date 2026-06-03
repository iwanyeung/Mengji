import mysql from 'mysql2/promise';
import { SCHEMA_MIGRATION_STATEMENTS, SCHEMA_STATEMENTS, MYSQL_INDEX_STATEMENTS } from './schema';
import type { DbClient, DbRow } from './types';

type SqlParam = string | number | boolean | null | Date | Buffer;

export async function createMysqlClient(mysqlUrl: string): Promise<DbClient> {
  const pool = mysql.createPool(mysqlUrl);

  const client: DbClient = {
    backend: 'mysql',

    async query<T extends DbRow = DbRow>(sql: string, params: unknown[] = []): Promise<T[]> {
      const [rows] = await pool.query(sql, params as SqlParam[]);
      return rows as T[];
    },

    async queryOne<T extends DbRow = DbRow>(sql: string, params: unknown[] = []): Promise<T | undefined> {
      const rows = await client.query<T>(sql, params);
      return rows[0];
    },

    async execute(sql: string, params: unknown[] = []): Promise<void> {
      await pool.query(sql, params as SqlParam[]);
    },

    async migrate(): Promise<void> {
      for (const stmt of SCHEMA_STATEMENTS) {
        try {
          await pool.execute(stmt);
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          if (!msg.includes('already exists')) throw e;
        }
      }
      for (const idx of MYSQL_INDEX_STATEMENTS) {
        try {
          await pool.execute(idx);
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          if (!msg.includes('Duplicate key name')) throw e;
        }
      }
      for (const stmt of SCHEMA_MIGRATION_STATEMENTS) {
        try {
          await pool.execute(stmt);
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          if (!msg.includes('Duplicate column')) throw e;
        }
      }
    },

    async close(): Promise<void> {
      await pool.end();
    },
  };

  return client;
}
