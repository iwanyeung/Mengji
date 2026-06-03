import { getDb, nowIso } from '../db';
import { computeNarrativeHash } from '../utils/narrativeHash';
import { generateComicPanelPrompts, type ComicPanelPrompt } from './deepseek';

const STYLE_KEYS = ['noir-comic', 'neon-surreal'] as const;

export async function invalidateStoryboardsForDream(dreamId: string): Promise<void> {
  const db = getDb();
  await db.execute(`DELETE FROM dream_comic_storyboards WHERE dream_id = ?`, [dreamId]);
}

export async function getCachedPanels(
  dreamId: string,
  styleKey: string,
  narrative: string,
): Promise<ComicPanelPrompt[] | null> {
  const db = getDb();
  const hash = computeNarrativeHash(narrative);
  const row = await db.queryOne<{ panels_json: string; narrative_hash: string }>(
    `SELECT panels_json, narrative_hash FROM dream_comic_storyboards WHERE dream_id = ? AND style_key = ?`,
    [dreamId, styleKey],
  );
  if (!row || row.narrative_hash !== hash) return null;
  try {
    const panels = JSON.parse(row.panels_json) as ComicPanelPrompt[];
    if (panels.length >= 4) return panels;
  } catch {
    /* miss */
  }
  return null;
}

export async function saveCachedPanels(
  dreamId: string,
  styleKey: string,
  narrative: string,
  panels: ComicPanelPrompt[],
): Promise<void> {
  const db = getDb();
  const hash = computeNarrativeHash(narrative);
  const ts = nowIso();
  const existing = await db.queryOne(`SELECT dream_id FROM dream_comic_storyboards WHERE dream_id = ? AND style_key = ?`, [
    dreamId,
    styleKey,
  ]);
  if (existing) {
    await db.execute(
      `UPDATE dream_comic_storyboards SET panels_json = ?, narrative_hash = ?, updated_at = ? WHERE dream_id = ? AND style_key = ?`,
      [JSON.stringify(panels), hash, ts, dreamId, styleKey],
    );
  } else {
    await db.execute(
      `INSERT INTO dream_comic_storyboards (dream_id, style_key, panels_json, narrative_hash, updated_at) VALUES (?, ?, ?, ?, ?)`,
      [dreamId, styleKey, JSON.stringify(panels), hash, ts],
    );
  }
}

export async function ensureStoryboard(
  dreamId: string,
  styleKey: string,
  narrative: string,
): Promise<ComicPanelPrompt[]> {
  const cached = await getCachedPanels(dreamId, styleKey, narrative);
  if (cached) return cached;
  const panels = await generateComicPanelPrompts(narrative, styleKey);
  await saveCachedPanels(dreamId, styleKey, narrative, panels);
  return panels;
}

export function prefetchStoryboardsForDream(dreamId: string, narrative: string): void {
  setImmediate(() => {
    void (async () => {
      for (const styleKey of STYLE_KEYS) {
        try {
          await ensureStoryboard(dreamId, styleKey, narrative);
        } catch (e) {
          console.warn(`Storyboard prefetch failed ${dreamId} ${styleKey}`, e);
        }
      }
    })();
  });
}
