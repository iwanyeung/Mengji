import { v4 as uuidv4 } from 'uuid';
import { getDb, nowIso } from '../db';
import { analyzeDream } from './deepseek';
import { transcribeAudioFile } from './speechASR';
import { recomputeSimilarityForUser, checkDailyAnalysisLimit, incrementDailyAnalysis } from './graphService';
import { env } from '../config/env';
import { scanTranscriptRisk, appendRiskNotice } from './contentSafety';
import { readUpload, writeTempFile } from './storage';
import { computeNarrativeHash } from '../utils/narrativeHash';
import { prefetchStoryboardsForDream } from './comicStoryboardCache';
import fs from 'fs';

export async function finalizeDreamRecording(dreamId: string, userId: string): Promise<void> {
  const db = getDb();
  const dream = await db.queryOne<Record<string, unknown>>(
    `SELECT * FROM dreams WHERE id = ? AND user_id = ?`,
    [dreamId, userId],
  );
  if (!dream) throw new Error('梦境不存在');

  if (!(await checkDailyAnalysisLimit(userId, env.dailyDreamAnalysisLimit))) {
    throw new Error('今日梦析次数已达上限，请明天再试');
  }

  const segments = await db.query<{
    id: string;
    audio_url: string | null;
    transcript: string | null;
    device_transcript: string | null;
  }>(`SELECT * FROM dream_segments WHERE dream_id = ? ORDER BY segment_index ASC`, [dreamId]);

  const transcripts: string[] = [];
  for (const seg of segments) {
    let text = seg.transcript || seg.device_transcript || '';
    if (seg.audio_url) {
      try {
        const buffer = await readUpload(seg.audio_url);
        const tmpPath = await writeTempFile(buffer, 'm4a');
        try {
          text = await transcribeAudioFile(tmpPath, seg.device_transcript || text);
          await db.execute(`UPDATE dream_segments SET transcript = ? WHERE id = ?`, [text, seg.id]);
        } finally {
          fs.unlinkSync(tmpPath);
        }
      } catch (e) {
        console.warn('ASR segment skip', e);
      }
    }
    if (text) transcripts.push(text);
  }

  const combined = transcripts.join('。') || (dream.raw_transcript as string) || '';
  await db.execute(`UPDATE dreams SET segments_combined_transcript = ?, raw_transcript = ?, status = ? WHERE id = ?`, [
    combined,
    combined,
    'transcribed',
    dreamId,
  ]);

  const analysis = await analyzeDream(combined);
  const risk = scanTranscriptRisk(combined);
  const analysisText = risk.riskFlag
    ? appendRiskNotice(analysis.analysisText, risk.message)
    : analysis.analysisText;
  const narrativeHash = computeNarrativeHash(analysis.refinedNarrative);
  await db.execute(
    `UPDATE dreams SET refined_narrative = ?, analysis_text = ?, status = ?, updated_at = ?, narrative_hash = ?, analysis_narrative_hash = ?, analysis_revision = 1 WHERE id = ?`,
    [
      analysis.refinedNarrative,
      analysisText,
      'analyzed',
      nowIso(),
      narrativeHash,
      narrativeHash,
      dreamId,
    ],
  );

  prefetchStoryboardsForDream(dreamId, analysis.refinedNarrative);

  await db.execute(`DELETE FROM dream_tags WHERE dream_id = ?`, [dreamId]);
  for (const tag of analysis.tags) {
    let tagRow = await db.queryOne<{ id: string }>(`SELECT id FROM tags WHERE name = ? AND category = ?`, [
      tag.name,
      tag.category,
    ]);
    if (!tagRow) {
      const tagId = uuidv4();
      await db.execute(`INSERT INTO tags (id, name, category, created_at) VALUES (?, ?, ?, ?)`, [
        tagId,
        tag.name,
        tag.category,
        nowIso(),
      ]);
      tagRow = { id: tagId };
    }
    await db.execute(`INSERT INTO dream_tags (id, dream_id, tag_id, relevance_score) VALUES (?, ?, ?, ?)`, [
      uuidv4(),
      dreamId,
      tagRow.id,
      0.8,
    ]);
  }

  await incrementDailyAnalysis(userId);
  await recomputeSimilarityForUser(userId);
}

export async function getFreeComicsRemaining(userId: string): Promise<number> {
  const db = getDb();
  const row = await db.queryOne<{ free_comics_total: number; free_comics_used: number }>(
    `SELECT free_comics_total, free_comics_used FROM user_comic_entitlements WHERE user_id = ?`,
    [userId],
  );
  if (!row) return 0;
  return Math.max(0, row.free_comics_total - row.free_comics_used);
}

export async function reserveFreeComicQuota(userId: string): Promise<boolean> {
  const remaining = await getFreeComicsRemaining(userId);
  if (remaining <= 0) return false;
  const db = getDb();
  await db.execute(
    `UPDATE user_comic_entitlements SET free_comics_used = free_comics_used + 1, updated_at = ? WHERE user_id = ?`,
    [nowIso(), userId],
  );
  return true;
}

export async function refundFreeComicQuota(userId: string): Promise<void> {
  const db = getDb();
  const row = await db.queryOne<{ free_comics_used: number }>(
    `SELECT free_comics_used FROM user_comic_entitlements WHERE user_id = ?`,
    [userId],
  );
  if (!row || row.free_comics_used <= 0) return;
  await db.execute(
    `UPDATE user_comic_entitlements SET free_comics_used = free_comics_used - 1, updated_at = ? WHERE user_id = ?`,
    [nowIso(), userId],
  );
}
