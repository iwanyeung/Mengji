import { getDb, nowIso } from '../db';
import { computeNarrativeHash } from '../utils/narrativeHash';
import {
  generateComicPanelPrompts,
  type ComicPanelPrompt,
  type ComicStoryboardInput,
} from './deepseek';
import { computeComicReadiness, type ComicReadinessResult, type ComicStoryboardMode } from './comicReadiness';
import { enforcePanelFidelity, normalizeComicPanels } from './comicFidelity';

const STYLE_KEYS = ['noir-comic', 'neon-surreal'] as const;

export interface DreamStoryboardContext {
  narrative: string;
  rawTranscript: string;
  tags: Array<{ name: string; category: string }>;
  segmentCount: number;
  readiness: ComicReadinessResult;
  storyboardInput: ComicStoryboardInput;
}

export async function loadDreamStoryboardContext(dreamId: string): Promise<DreamStoryboardContext | null> {
  const db = getDb();
  const dream = await db.queryOne<{
    refined_narrative: string | null;
    raw_transcript: string | null;
    segments_combined_transcript: string | null;
  }>(`SELECT refined_narrative, raw_transcript, segments_combined_transcript FROM dreams WHERE id = ?`, [dreamId]);
  if (!dream) return null;

  const narrative = dream.refined_narrative?.trim() || '';
  const rawTranscript =
    dream.raw_transcript?.trim() || dream.segments_combined_transcript?.trim() || narrative;

  const segmentRow = await db.queryOne<{ count: number }>(
    `SELECT COUNT(*) AS count FROM dream_segments WHERE dream_id = ?`,
    [dreamId],
  );
  const segmentCount = Number(segmentRow?.count ?? 0);

  const tags = await db.query<{ name: string; category: string }>(
    `SELECT t.name, t.category FROM dream_tags dt JOIN tags t ON dt.tag_id = t.id WHERE dt.dream_id = ?`,
    [dreamId],
  );

  const readiness = computeComicReadiness({
    segmentCount,
    narrativeCharCount: narrative.length,
    rawCharCount: rawTranscript.length,
    tags,
  });

  const storyboardInput: ComicStoryboardInput = {
    refinedNarrative: narrative,
    rawTranscript,
    tags,
    mode: readiness.suggestedMode,
  };

  return {
    narrative,
    rawTranscript,
    tags,
    segmentCount,
    readiness,
    storyboardInput,
  };
}

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
  const bundle = parseCachedPayload(row.panels_json);
  if (bundle.panels.length >= 4) return bundle.panels;
  return null;
}

export async function saveCachedPanels(
  dreamId: string,
  styleKey: string,
  narrative: string,
  panels: ComicPanelPrompt[],
  storyboardMode?: ComicStoryboardMode,
): Promise<void> {
  const db = getDb();
  const hash = computeNarrativeHash(narrative);
  const ts = nowIso();
  const payload = JSON.stringify({
    panels,
    storyboardMode: storyboardMode ?? null,
  });
  const existing = await db.queryOne(`SELECT dream_id FROM dream_comic_storyboards WHERE dream_id = ? AND style_key = ?`, [
    dreamId,
    styleKey,
  ]);
  if (existing) {
    await db.execute(
      `UPDATE dream_comic_storyboards SET panels_json = ?, narrative_hash = ?, updated_at = ? WHERE dream_id = ? AND style_key = ?`,
      [payload, hash, ts, dreamId, styleKey],
    );
  } else {
    await db.execute(
      `INSERT INTO dream_comic_storyboards (dream_id, style_key, panels_json, narrative_hash, updated_at) VALUES (?, ?, ?, ?, ?)`,
      [dreamId, styleKey, payload, hash, ts],
    );
  }
}

function parseCachedPayload(raw: string): { panels: ComicPanelPrompt[]; storyboardMode: ComicStoryboardMode | null } {
  try {
    const parsed = JSON.parse(raw) as { panels?: ComicPanelPrompt[]; storyboardMode?: ComicStoryboardMode | null };
    if (Array.isArray(parsed.panels)) {
      return {
        panels: normalizeComicPanels(parsed.panels),
        storyboardMode: parsed.storyboardMode ?? null,
      };
    }
    const legacy = JSON.parse(raw) as ComicPanelPrompt[];
    if (Array.isArray(legacy)) {
      return { panels: normalizeComicPanels(legacy), storyboardMode: null };
    }
  } catch {
    /* legacy miss */
  }
  return { panels: [], storyboardMode: null };
}

export async function getCachedStoryboardBundle(
  dreamId: string,
  styleKey: string,
  narrative: string,
): Promise<{ panels: ComicPanelPrompt[]; storyboardMode: ComicStoryboardMode | null } | null> {
  const db = getDb();
  const hash = computeNarrativeHash(narrative);
  const row = await db.queryOne<{ panels_json: string; narrative_hash: string }>(
    `SELECT panels_json, narrative_hash FROM dream_comic_storyboards WHERE dream_id = ? AND style_key = ?`,
    [dreamId, styleKey],
  );
  if (!row || row.narrative_hash !== hash) return null;
  const bundle = parseCachedPayload(row.panels_json);
  if (bundle.panels.length >= 4) return bundle;
  return null;
}

export async function invalidateStoryboardForStyle(dreamId: string, styleKey: string): Promise<void> {
  const db = getDb();
  await db.execute(`DELETE FROM dream_comic_storyboards WHERE dream_id = ? AND style_key = ?`, [dreamId, styleKey]);
}

export async function ensureStoryboard(
  dreamId: string,
  styleKey: string,
  narrative: string,
  options?: { forceMode?: ComicStoryboardMode; bypassCache?: boolean },
): Promise<ComicPanelPrompt[]> {
  if (!options?.bypassCache) {
    const cached = await getCachedStoryboardBundle(dreamId, styleKey, narrative);
    if (cached) {
      const modeOk = !options?.forceMode || cached.storyboardMode === options.forceMode;
      if (modeOk) return cached.panels;
    }
  }

  const ctx = await loadDreamStoryboardContext(dreamId);
  if (!ctx) return [];

  const mode = options?.forceMode ?? ctx.readiness.suggestedMode;
  const input: ComicStoryboardInput = { ...ctx.storyboardInput, mode };
  const generated = await generateComicPanelPrompts(input, styleKey);
  const panels = enforcePanelFidelity(
    generated,
    `${ctx.rawTranscript}\n${ctx.narrative}`,
    ctx.tags,
    mode,
  );
  await saveCachedPanels(dreamId, styleKey, narrative, panels, mode);
  return panels;
}

export async function updateStoryboardCaptions(
  dreamId: string,
  styleKey: string,
  narrative: string,
  captions: Array<{ panelIndex: number; caption: string }>,
): Promise<ComicPanelPrompt[]> {
  const bundle = await getCachedStoryboardBundle(dreamId, styleKey, narrative);
  if (!bundle) {
    const panels = await ensureStoryboard(dreamId, styleKey, narrative);
    return applyCaptionEdits(panels, captions);
  }

  const updated = applyCaptionEdits(bundle.panels, captions);
  await saveCachedPanels(dreamId, styleKey, narrative, updated, bundle.storyboardMode ?? undefined);
  return updated;
}

function applyCaptionEdits(
  panels: ComicPanelPrompt[],
  captions: Array<{ panelIndex: number; caption: string }>,
): ComicPanelPrompt[] {
  const captionMap = new Map(captions.map((c) => [c.panelIndex, c.caption.trim()]));
  return panels.map((panel, index) => {
    const panelIndex = panel.panelIndex ?? index + 1;
    const nextCaption = captionMap.get(panelIndex);
    if (!nextCaption) return panel;
    return { ...panel, caption: nextCaption };
  });
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
