import { Router } from 'express';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';
import { requireAuth } from '../middleware/auth';
import { getDb, nowIso } from '../db';
import { saveUpload, resolvePublicUrl } from '../services/storage';
import { visualUrlsFromJson } from '../services/comicImageUrls';
import { finalizeDreamRecording } from '../services/dreamPipeline';
import { getGraphForUser } from '../services/graphService';
import {
  patchDreamNarrative,
  putDreamFeedback,
  getDreamFeedback,
  runReinterpret,
  replaceDreamTagsFromUser,
  type DreamFeedbackType,
} from '../services/dreamInsight';
import { prefetchStoryboardsForDream, ensureStoryboard } from '../services/comicStoryboardCache';
import {
  markDreamAnalyzedPushSent,
  sendDreamAnalyzedPush,
  shouldSendDreamAnalyzedPush,
} from '../services/apns';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024 } });

async function dreamToResponse(dreamId: string) {
  const db = getDb();
  const dream = await db.queryOne<Record<string, unknown>>(`SELECT * FROM dreams WHERE id = ?`, [dreamId]);
  if (!dream) return null;

  const segments = await db.query(
    `SELECT id, segment_index AS \`index\`, audio_duration_seconds AS durationSeconds, transcript FROM dream_segments WHERE dream_id = ? ORDER BY segment_index`,
    [dreamId],
  );

  const tags = await db.query(
    `SELECT t.id, t.name, t.category FROM dream_tags dt JOIN tags t ON dt.tag_id = t.id WHERE dt.dream_id = ?`,
    [dreamId],
  );

  const visualRows = await db.query<Record<string, unknown>>(
    `SELECT id, type, status, style_key AS styleKey, image_url AS imageUrl, image_urls_json, narrative_hash_at_gen AS narrativeHashAtGen FROM dream_visuals WHERE dream_id = ?`,
    [dreamId],
  );
  const visuals = visualRows.map((v) => {
    const urls = v.image_urls_json ? visualUrlsFromJson(v.image_urls_json) : null;
    const imageUrl = v.imageUrl ? resolvePublicUrl(String(v.imageUrl)) : undefined;
    return {
      ...v,
      imageUrl,
      imageUrls: urls?.imageUrls,
      imageThumbUrls: urls?.imageThumbUrls,
    };
  });

  const narrativeHash = dream.narrative_hash ? String(dream.narrative_hash) : null;
  const analysisNarrativeHash = dream.analysis_narrative_hash ? String(dream.analysis_narrative_hash) : null;
  const analysisStale = Boolean(
    narrativeHash && analysisNarrativeHash && narrativeHash !== analysisNarrativeHash,
  );

  const fb = await getDreamFeedback(dreamId);

  return {
    id: dream.id,
    occurredAt: dream.occurred_at,
    status: dream.status,
    refinedNarrative: dream.refined_narrative,
    analysisText: dream.analysis_text,
    title: dream.title ?? null,
    rawTranscript: dream.raw_transcript,
    narrativeHash,
    analysisNarrativeHash,
    analysisRevision: dream.analysis_revision ?? 1,
    analysisStale,
    userTagsLocked: Boolean(dream.user_tags_locked),
    segments,
    tags,
    visuals,
    feedback: fb
      ? {
          type: fb.feedback,
          optionalNote: fb.optional_note,
          aBitOffSheetSeen: Boolean(fb.a_bit_off_sheet_seen),
          interpretationRevision: fb.interpretation_revision,
        }
      : null,
  };
}

export function createDreamsRouter(): Router {
  const router = Router();

  router.post('/', requireAuth, async (req, res) => {
    const id = String(req.body?.id || uuidv4());
    const ts = nowIso();
    const occurredAt = req.body?.occurredAt || ts;
    const source = req.body?.source || 'iphone';
    const existing = await getDb().queryOne(`SELECT id FROM dreams WHERE id = ?`, [id]);
    if (existing) {
      res.json({ id, status: 'recorded' });
      return;
    }
    await getDb().execute(
      `INSERT INTO dreams (id, user_id, created_at, updated_at, occurred_at, source, status) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, req.auth!.userId, ts, ts, occurredAt, source, 'recorded'],
    );
    res.json({ id, status: 'recorded' });
  });

  router.get('/graph', requireAuth, async (req, res) => {
    const onlyVisualized = req.query.onlyVisualized === 'true';
    res.json(await getGraphForUser(req.auth!.userId, onlyVisualized));
  });

  router.get('/search', requireAuth, async (req, res) => {
    const q = String(req.query.q || '').trim();
    const rows = await getDb().query(
      `SELECT id, refined_narrative, title, occurred_at FROM dreams WHERE user_id = ? AND (refined_narrative LIKE ? OR raw_transcript LIKE ? OR title LIKE ?) ORDER BY occurred_at DESC LIMIT 50`,
      [req.auth!.userId, `%${q}%`, `%${q}%`, `%${q}%`],
    );
    res.json({ dreams: rows });
  });

  router.get('/:dreamId', requireAuth, async (req, res) => {
    const dream = await getDb().queryOne(`SELECT id FROM dreams WHERE id = ? AND user_id = ?`, [
      req.params.dreamId,
      req.auth!.userId,
    ]);
    if (!dream) {
      res.status(404).json({ error: '梦境不存在' });
      return;
    }
    res.json(await dreamToResponse(req.params.dreamId));
  });

  router.patch('/:dreamId', requireAuth, async (req, res) => {
    const dreamId = req.params.dreamId;
    const userId = req.auth!.userId;
    const dream = await getDb().queryOne(`SELECT id FROM dreams WHERE id = ? AND user_id = ?`, [
      dreamId,
      userId,
    ]);
    if (!dream) {
      res.status(404).json({ error: '梦境不存在' });
      return;
    }

    try {
      if (req.body?.refinedNarrative !== undefined) {
        const text = String(req.body.refinedNarrative).trim();
        if (!text) {
          res.status(400).json({ error: '梦境整理不能为空' });
          return;
        }
        const result = await patchDreamNarrative(dreamId, userId, text);
        res.json(result);
        return;
      }

      if (req.body?.tags !== undefined && Array.isArray(req.body.tags)) {
        const names = (req.body.tags as string[]).map((t) => String(t).trim()).filter(Boolean);
        await replaceDreamTagsFromUser(dreamId, names);
        res.json({ ok: true });
        return;
      }

      res.status(400).json({ error: '无有效更新字段' });
    } catch (e) {
      res.status(400).json({ error: e instanceof Error ? e.message : '更新失败' });
    }
  });

  router.post('/:dreamId/reinterpret', requireAuth, async (req, res) => {
    const dreamId = req.params.dreamId;
    const mode = req.body?.mode === 'gentler' ? 'gentler' : 'default';
    const feedbackNote = req.body?.feedbackNote as string | undefined;
    const updateTags = req.body?.updateTags === true;

    try {
      const result = await runReinterpret(
        dreamId,
        req.auth!.userId,
        mode,
        String(req.body?.trigger || 'edit'),
        feedbackNote,
        updateTags,
      );
      res.json({
        analysisText: result.analysisText,
        analysisRevision: result.analysisRevision,
        narrativeHash: result.narrativeHash,
        analysisStale: false,
      });
    } catch (e) {
      const statusCode = (e as Error & { statusCode?: number }).statusCode;
      if (statusCode === 429) {
        res.status(429).json({ error: e instanceof Error ? e.message : '今日梦析次数已达上限' });
        return;
      }
      res.status(400).json({ error: e instanceof Error ? e.message : '更新解读失败' });
    }
  });

  router.put('/:dreamId/feedback', requireAuth, async (req, res) => {
    const dreamId = req.params.dreamId;
    const raw = req.body?.feedback;
    const feedback: DreamFeedbackType | null =
      raw === 'very_close' || raw === 'a_bit_off' || raw === 'uncomfortable' ? raw : null;
    const optionalNote = req.body?.optionalNote as string | undefined;
    const markSheetSeen = req.body?.markABitOffSheetSeen === true;

    try {
      await putDreamFeedback(dreamId, req.auth!.userId, feedback, optionalNote, markSheetSeen);
      const fb = await getDreamFeedback(dreamId);
      res.json({
        feedback: fb?.feedback ?? null,
        optionalNote: fb?.optional_note ?? null,
        aBitOffSheetSeen: Boolean(fb?.a_bit_off_sheet_seen),
      });
    } catch (e) {
      res.status(400).json({ error: e instanceof Error ? e.message : '保存反馈失败' });
    }
  });

  router.post('/:dreamId/comic-storyboard/prefetch', requireAuth, async (req, res) => {
    const dreamId = req.params.dreamId;
    const db = getDb();
    const dream = await db.queryOne<{ refined_narrative: string | null }>(
      `SELECT refined_narrative FROM dreams WHERE id = ? AND user_id = ?`,
      [dreamId, req.auth!.userId],
    );
    if (!dream) {
      res.status(404).json({ error: '梦境不存在' });
      return;
    }
    const narrative = dream.refined_narrative || '';
    if (!narrative.trim()) {
      res.status(400).json({ error: '请先完成梦境整理' });
      return;
    }

    const styleKey = req.body?.styleKey as string | undefined;
    if (styleKey) {
      setImmediate(() => {
        ensureStoryboard(dreamId, styleKey, narrative).catch(console.error);
      });
    } else {
      prefetchStoryboardsForDream(dreamId, narrative);
    }
    res.json({ accepted: true });
  });

  router.post('/:dreamId/segments', requireAuth, upload.single('audio'), async (req, res) => {
    const dreamId = req.params.dreamId;
    const db = getDb();
    const dream = await db.queryOne(`SELECT id FROM dreams WHERE id = ? AND user_id = ?`, [
      dreamId,
      req.auth!.userId,
    ]);
    if (!dream) {
      res.status(404).json({ error: '梦境不存在' });
      return;
    }

    const index = Number(req.body?.index ?? 0);
    const deviceTranscript = String(req.body?.deviceTranscript || '');
    let audioUrl: string | null = null;

    if (req.file) {
      const ext = req.file.originalname.split('.').pop() || 'm4a';
      const saved = await saveUpload(req.file.buffer, ext, 'audio');
      audioUrl = saved.storageKey;
    }

    const segmentId = uuidv4();
    const ts = nowIso();
    await db.execute(
      `INSERT INTO dream_segments (id, dream_id, segment_index, created_at, audio_url, transcript, device_transcript)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [segmentId, dreamId, index, ts, audioUrl, deviceTranscript, deviceTranscript],
    );

    res.json({
      segmentId,
      index,
      transcript: deviceTranscript,
    });
  });

  router.post('/:dreamId/finalize-recording', requireAuth, async (req, res) => {
    const dreamId = req.params.dreamId;
    const dream = await getDb().queryOne(`SELECT id FROM dreams WHERE id = ? AND user_id = ?`, [
      dreamId,
      req.auth!.userId,
    ]);
    if (!dream) {
      res.status(404).json({ error: '梦境不存在' });
      return;
    }

    try {
      await finalizeDreamRecording(dreamId, req.auth!.userId);
      const userId = req.auth!.userId;
      if (await shouldSendDreamAnalyzedPush(dreamId)) {
        try {
          await sendDreamAnalyzedPush(userId, dreamId);
          await markDreamAnalyzedPushSent(dreamId);
        } catch (e) {
          console.warn('[apns] dream_analyzed push failed:', e);
        }
      }
      res.json({ id: dreamId, status: 'analyzed' });
    } catch (e) {
      const msg = e instanceof Error ? e.message : '整理失败';
      res.status(500).json({ error: msg });
    }
  });

  router.post('/:dreamId/visuals/four-panel', requireAuth, (_req, res) => {
    res.status(400).json({ error: '请使用 POST /api/visuals/four-panel' });
  });

  return router;
}
