export type DbBackend = 'sqlite' | 'mysql';

export type DbRow = Record<string, unknown>;

export interface DbClient {
  readonly backend: DbBackend;
  query<T extends DbRow = DbRow>(sql: string, params?: unknown[]): Promise<T[]>;
  queryOne<T extends DbRow = DbRow>(sql: string, params?: unknown[]): Promise<T | undefined>;
  execute(sql: string, params?: unknown[]): Promise<void>;
  migrate(): Promise<void>;
  close(): Promise<void>;
}

export function nowIso(): string {
  return new Date().toISOString();
}
