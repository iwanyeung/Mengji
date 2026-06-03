import { v4 as uuidv4 } from 'uuid';
import { getDb, nowIso, dailyAnalysisUpsertSql } from '../db';

export async function recomputeSimilarityForUser(userId: string): Promise<void> {
  const db = getDb();
  const dreams = await db.query<{ id: string; occurred_at: string }>(
    `SELECT d.id, d.occurred_at FROM dreams d WHERE d.user_id = ? AND d.status = 'analyzed'`,
    [userId],
  );

  await db.execute(
    `DELETE FROM similarity_edges WHERE dream_id_a IN (
    SELECT id FROM dreams WHERE user_id = ?
  )`,
    [userId],
  );

  for (let i = 0; i < dreams.length; i++) {
    for (let j = i + 1; j < dreams.length; j++) {
      const a = dreams[i];
      const b = dreams[j];
      const tagsA = await getDreamTagNames(a.id);
      const tagsB = await getDreamTagNames(b.id);
      const shared = tagsA.filter((t) => tagsB.includes(t));
      if (shared.length === 0) continue;
      const jaccard = shared.length / new Set([...tagsA, ...tagsB]).size;
      const score = Math.min(0.95, jaccard + 0.1);
      await db.execute(
        `INSERT INTO similarity_edges (id, dream_id_a, dream_id_b, score, shared_tag_ids, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [uuidv4(), a.id, b.id, score, JSON.stringify(shared), nowIso()],
      );
    }
  }
}

async function getDreamTagNames(dreamId: string): Promise<string[]> {
  const db = getDb();
  const rows = await db.query<{ name: string }>(
    `SELECT t.name FROM dream_tags dt JOIN tags t ON dt.tag_id = t.id WHERE dt.dream_id = ?`,
    [dreamId],
  );
  return rows.map((r) => r.name);
}

export async function getGraphForUser(userId: string, onlyVisualized?: boolean) {
  const db = getDb();
  let sql = `SELECT d.id, d.occurred_at, d.refined_narrative, d.status FROM dreams d WHERE d.user_id = ? AND d.status IN ('analyzed', 'visualized')`;
  if (onlyVisualized) {
    sql += ` AND EXISTS (SELECT 1 FROM dream_visuals v WHERE v.dream_id = d.id AND v.status = 'succeeded')`;
  }
  const dreams = await db.query<{
    id: string;
    occurred_at: string;
    refined_narrative: string | null;
  }>(sql, [userId]);

  const nodes = await Promise.all(
    dreams.map(async (d, idx) => {
      const tags = await getDreamTagNames(d.id);
      const hasVisual = await db.queryOne(
        `SELECT 1 AS ok FROM dream_visuals WHERE dream_id = ? AND status = 'succeeded' LIMIT 1`,
        [d.id],
      );
      const angle = (idx / Math.max(dreams.length, 1)) * Math.PI * 2;
      const r = 0.25 + (idx % 5) * 0.08;
      return {
        id: d.id,
        dateLabel: d.occurred_at.slice(5, 10).replace('-', '.'),
        tags: tags.slice(0, 3),
        snippet: (d.refined_narrative || '').slice(0, 40),
        hasVisual: Boolean(hasVisual),
        position: { x: 0.5 + Math.cos(angle) * r, y: 0.5 + Math.sin(angle) * r },
      };
    }),
  );

  const edges = await db.query<{
    id: string;
    dream_id_a: string;
    dream_id_b: string;
    score: number;
    shared_tag_ids: string;
  }>(
    `SELECT e.* FROM similarity_edges e
       JOIN dreams da ON da.id = e.dream_id_a
       WHERE da.user_id = ?`,
    [userId],
  );

  return {
    nodes,
    edges: edges.map((e) => ({
      id: e.id,
      from: e.dream_id_a,
      to: e.dream_id_b,
      score: e.score,
      sharedTags: JSON.parse(e.shared_tag_ids || '[]') as string[],
    })),
  };
}

export async function checkDailyAnalysisLimit(userId: string, limit: number): Promise<boolean> {
  const db = getDb();
  const day = new Date().toISOString().slice(0, 10);
  const row = await db.queryOne<{ dream_analysis_count: number }>(
    `SELECT dream_analysis_count FROM usage_daily WHERE user_id = ? AND day = ?`,
    [userId, day],
  );
  return (row?.dream_analysis_count ?? 0) < limit;
}

export async function incrementDailyAnalysis(userId: string): Promise<void> {
  const db = getDb();
  const day = new Date().toISOString().slice(0, 10);
  await db.execute(dailyAnalysisUpsertSql(db.backend), [userId, day]);
}
