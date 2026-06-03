import { v4 as uuidv4 } from 'uuid';
import { getDb, nowIso } from '../db';
import { env } from '../config/env';
import { computeNarrativeHash, isSubstantialNarrativeChange } from '../utils/narrativeHash';
import { reinterpretDream, type ReinterpretMode } from './deepseek';
import { scanTranscriptRisk, appendRiskNotice } from './contentSafety';
import { checkDailyAnalysisLimit, incrementDailyAnalysis } from './graphService';
import { invalidateStoryboardsForDream } from './comicStoryboardCache';

export type DreamFeedbackType = 'very_close' | 'a_bit_off' | 'uncomfortable';

export async function assertDreamOwner(dreamId: string, userId: string) {
  const dream = await getDb().queryOne<{ id: string }>(`SELECT id FROM dreams WHERE id = ? AND user_id = ?`, [
    dreamId,
    userId,
  ]);
  if (!dream) throw new Error('梦境不存在');
}

export async function patchDreamNarrative(
  dreamId: string,
  userId: string,
  refinedNarrative: string,
): Promise<{ narrativeHash: string; analysisStale: boolean }> {
  await assertDreamOwner(dreamId, userId);
  const db = getDb();
  const row = await db.queryOne<{ refined_narrative: string | null; analysis_narrative_hash: string | null }>(
    `SELECT refined_narrative, analysis_narrative_hash FROM dreams WHERE id = ?`,
    [dreamId],
  );
  const before = row?.refined_narrative || '';
  const hash = computeNarrativeHash(refinedNarrative);
  const prevAnalysisHash = row?.analysis_narrative_hash ?? null;
  const analysisStale = Boolean(prevAnalysisHash) && prevAnalysisHash !== hash;

  await db.execute(
    `UPDATE dreams SET refined_narrative = ?, narrative_hash = ?, updated_at = ? WHERE id = ?`,
    [refinedNarrative, hash, nowIso(), dreamId],
  );

  if (isSubstantialNarrativeChange(before, refinedNarrative)) {
    await invalidateStoryboardsForDream(dreamId);
  }

  return { narrativeHash: hash, analysisStale };
}

export async function runReinterpret(
  dreamId: string,
  userId: string,
  mode: ReinterpretMode,
  trigger: string,
  feedbackNote?: string,
  updateTags = false,
): Promise<{ analysisText: string; analysisRevision: number; narrativeHash: string; tags?: Array<{ name: string; category: string }> }> {
  await assertDreamOwner(dreamId, userId);

  if (!(await checkDailyAnalysisLimit(userId, env.dailyDreamAnalysisLimit))) {
    const err = new Error('今日梦析次数已达上限，请明天再试');
    (err as Error & { statusCode: number }).statusCode = 429;
    throw err;
  }

  const db = getDb();
  const dream = await db.queryOne<{
    refined_narrative: string | null;
    analysis_revision: number;
    user_tags_locked: number;
    raw_transcript: string | null;
  }>(`SELECT refined_narrative, analysis_revision, user_tags_locked, raw_transcript FROM dreams WHERE id = ?`, [
    dreamId,
  ]);
  const narrative = dream?.refined_narrative?.trim() || '';
  if (!narrative) throw new Error('请先完成梦境整理');

  const risk = scanTranscriptRisk(narrative);
  const result = await reinterpretDream(narrative, mode, feedbackNote);
  let analysisText = result.analysisText;
  if (risk.riskFlag) {
    analysisText = appendRiskNotice(analysisText, risk.message);
  }

  const hash = computeNarrativeHash(narrative);
  const nextRevision = (dream?.analysis_revision || 1) + 1;

  await db.execute(
    `UPDATE dreams SET analysis_text = ?, analysis_narrative_hash = ?, analysis_revision = ?, updated_at = ?, narrative_hash = ? WHERE id = ?`,
    [analysisText, hash, nextRevision, nowIso(), hash, dreamId],
  );

  let tags: Array<{ name: string; category: string }> | undefined;
  if (updateTags && !dream?.user_tags_locked) {
    // Reinterpret path for tags: only when not user-locked; MVP reinterpret API skips tag regen per plan
    tags = undefined;
  }

  await incrementDailyAnalysis(userId);
  return { analysisText, analysisRevision: nextRevision, narrativeHash: hash, tags };
}

export async function getDreamFeedback(dreamId: string) {
  return getDb().queryOne<{
    feedback: string | null;
    optional_note: string | null;
    a_bit_off_sheet_seen: number;
    interpretation_revision: number | null;
  }>(`SELECT feedback, optional_note, a_bit_off_sheet_seen, interpretation_revision FROM dream_analysis_feedback WHERE dream_id = ?`, [
    dreamId,
  ]);
}

export async function putDreamFeedback(
  dreamId: string,
  userId: string,
  feedback: DreamFeedbackType | null,
  optionalNote?: string,
  markSheetSeen?: boolean,
) {
  await assertDreamOwner(dreamId, userId);
  const db = getDb();
  const dream = await db.queryOne<{ analysis_revision: number }>(
    `SELECT analysis_revision FROM dreams WHERE id = ?`,
    [dreamId],
  );
  const ts = nowIso();
  const existing = await getDreamFeedback(dreamId);
  const sheetSeen =
    markSheetSeen === true
      ? 1
      : existing?.a_bit_off_sheet_seen
        ? 1
        : 0;

  if (existing) {
    await db.execute(
      `UPDATE dream_analysis_feedback SET feedback = ?, optional_note = ?, a_bit_off_sheet_seen = ?, interpretation_revision = ?, updated_at = ? WHERE dream_id = ?`,
      [
        feedback,
        optionalNote ?? existing.optional_note,
        sheetSeen,
        dream?.analysis_revision ?? 1,
        ts,
        dreamId,
      ],
    );
  } else {
    await db.execute(
      `INSERT INTO dream_analysis_feedback (dream_id, feedback, optional_note, a_bit_off_sheet_seen, interpretation_revision, updated_at) VALUES (?, ?, ?, ?, ?, ?)`,
      [dreamId, feedback, optionalNote ?? null, sheetSeen, dream?.analysis_revision ?? 1, ts],
    );
  }
}

export async function lockUserTags(dreamId: string): Promise<void> {
  await getDb().execute(`UPDATE dreams SET user_tags_locked = 1 WHERE id = ?`, [dreamId]);
}

export async function replaceDreamTagsFromUser(
  dreamId: string,
  tagNames: string[],
): Promise<void> {
  const db = getDb();
  await db.execute(`DELETE FROM dream_tags WHERE dream_id = ?`, [dreamId]);
  for (const name of tagNames) {
    const trimmed = name.trim();
    if (!trimmed) continue;
    let tagRow = await db.queryOne<{ id: string }>(`SELECT id FROM tags WHERE name = ? AND category = ?`, [
      trimmed,
      'other',
    ]);
    if (!tagRow) {
      const tagId = uuidv4();
      await db.execute(`INSERT INTO tags (id, name, category, created_at) VALUES (?, ?, ?, ?)`, [
        tagId,
        trimmed,
        'other',
        nowIso(),
      ]);
      tagRow = { id: tagId };
    }
    await db.execute(`INSERT INTO dream_tags (id, dream_id, tag_id, relevance_score) VALUES (?, ?, ?, ?)`, [
      uuidv4(),
      dreamId,
      tagRow.id,
      0.9,
    ]);
  }
  await lockUserTags(dreamId);
}
