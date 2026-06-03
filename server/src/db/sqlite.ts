import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { SCHEMA_MIGRATION_STATEMENTS, SCHEMA_STATEMENTS } from './schema';
import type { DbClient, DbRow } from './types';

export function createSqliteClient(databasePath: string): DbClient {
  fs.mkdirSync(path.dirname(databasePath), { recursive: true });
  const sqlite = new Database(databasePath);
  sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('foreign_keys = ON');

  const client: DbClient = {
    backend: 'sqlite',

    async query<T extends DbRow = DbRow>(sql: string, params: unknown[] = []): Promise<T[]> {
      return sqlite.prepare(sql).all(...params) as T[];
    },

    async queryOne<T extends DbRow = DbRow>(sql: string, params: unknown[] = []): Promise<T | undefined> {
      return sqlite.prepare(sql).get(...params) as T | undefined;
    },

    async execute(sql: string, params: unknown[] = []): Promise<void> {
      sqlite.prepare(sql).run(...params);
    },

    async migrate(): Promise<void> {
      for (const stmt of SCHEMA_STATEMENTS) {
        sqlite.exec(stmt);
      }
      for (const stmt of SCHEMA_MIGRATION_STATEMENTS) {
        try {
          sqlite.exec(stmt);
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          if (!msg.includes('duplicate column')) throw e;
        }
      }
    },

    async close(): Promise<void> {
      sqlite.close();
    },
  };

  return client;
}
