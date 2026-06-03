import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { requireAuth } from '../middleware/auth';
import { getDb, nowIso } from '../db';
import { env } from '../config/env';
import { verifyAppleTransaction } from '../services/appleIAP';
import {
  getFreeComicsRemaining,
  reserveFreeComicQuota,
  refundFreeComicQuota,
} from '../services/dreamPipeline';
import { generateFourPanels } from '../services/seedream';
import { saveComicPanelUpload, resolvePublicUrl } from '../services/storage';
import {
  parseComicPanelsJson,
  resolvedFullUrls,
  serializeComicPanelsJson,
  visualUrlsFromJson,
  type ComicPanelSlot,
} from '../services/comicImageUrls';
import { ensureStoryboard } from '../services/comicStoryboardCache';
import { computeNarrativeHash } from '../utils/narrativeHash';
import {
  classifyVisualFailure,
  resolveFailureForZeroPanels,
  userMessageForFailure,
  type VisualFailureCode,
} from '../services/visualFailure';
import {
  markVisualPushSent,
  sendVisualCompletionPush,
  shouldSendVisualPush,
} from '../services/apns';

function parseImageUrlsJson(raw: unknown): string[] {
  return resolvedFullUrls(parseComicPanelsJson(raw));
}

async function markVisualFailed(
  visualId: string,
  opts: {
    failureCode: VisualFailureCode;
    internalReason: string;
    seedreamCallCount?: number;
    successfulPanelCount?: number;
    estimatedCostCny?: number;
    imageUrlsJson?: string;
  },
): Promise<void> {
  const db = getDb();
  await db.execute(
    `UPDATE dream_visuals SET status = ?, failure_code = ?, failure_reason = ?, seedream_call_count = ?, successful_panel_count = ?, estimated_cost_cny = ?, image_urls_json = ?, updated_at = ? WHERE id = ?`,
    [
      'failed',
      opts.failureCode,
      opts.internalReason,
      opts.seedreamCallCount ?? 0,
      opts.successfulPanelCount ?? 0,
      opts.estimatedCostCny ?? 0,
      opts.imageUrlsJson ?? null,
      nowIso(),
      visualId,
    ],
  );
}

async function notifyVisualPushIfNeeded(
  visualId: string,
  userId: string,
  dreamId: string,
  styleKey: string,
  type: 'visual_done' | 'visual_failed',
  failureCode?: string,
): Promise<void> {
  if (!(await shouldSendVisualPush(visualId))) return;
  try {
    await sendVisualCompletionPush(userId, {
      type,
      visualId,
      dreamId,
      styleKey,
      failureCode,
    });
    await markVisualPushSent(visualId);
  } catch (e) {
    console.warn('[apns] notifyVisualPushIfNeeded failed:', e);
  }
}

async function runComicGeneration(
  visualId: string,
  dreamId: string,
  userId: string,
  styleKey: string,
): Promise<void> {
  const db = getDb();
  const usedFree = await db.queryOne<{ used_free_quota: number }>(
    `SELECT used_free_quota FROM dream_visuals WHERE id = ?`,
    [visualId],
  );

  try {
    const dream = await db.queryOne<{ refined_narrative: string; narrative_hash: string | null }>(
      `SELECT refined_narrative, narrative_hash FROM dreams WHERE id = ?`,
      [dreamId],
    );
    const narrative = dream?.refined_narrative || '';
    const narrativeHash = dream?.narrative_hash || computeNarrativeHash(narrative);
    const panels = await ensureStoryboard(dreamId, styleKey, narrative);

    await db.execute(
      `UPDATE dream_visuals SET status = ?, updated_at = ?, narrative_hash_at_gen = ? WHERE id = ?`,
      ['generating', nowIso(), narrativeHash, visualId],
    );

    const slotPanels: ComicPanelSlot[] = [null, null, null, null];

    const result = await generateFourPanels(
      panels,
      async (buffer, _index) => saveComicPanelUpload(buffer, `comics/${dreamId}`),
      async (_index, _panel, completedCount, panelsSoFar) => {
        for (let i = 0; i < panelsSoFar.length; i++) {
          slotPanels[i] = panelsSoFar[i];
        }
        await db.execute(
          `UPDATE dream_visuals SET successful_panel_count = ?, image_urls_json = ?, updated_at = ? WHERE id = ?`,
          [completedCount, serializeComicPanelsJson(slotPanels), nowIso(), visualId],
        );
      },
    );

    const signedUrls = resolvedFullUrls(result.panels);
    const panelsJson = serializeComicPanelsJson(
      result.panels.length === 4
        ? result.panels
        : [...result.panels, ...Array(Math.max(0, 4 - result.panels.length)).fill(null)],
    );

    if (result.successfulPanelCount === 4) {
      await db.execute(
        `UPDATE dream_visuals SET status = ?, image_urls_json = ?, image_url = ?, seedream_call_count = ?, successful_panel_count = ?, estimated_cost_cny = ?, updated_at = ?, narrative_hash_at_gen = ? WHERE id = ?`,
        [
          'succeeded',
          panelsJson,
          signedUrls[0] || null,
          result.seedreamCallCount,
          result.successfulPanelCount,
          result.estimatedCostCny,
          nowIso(),
          narrativeHash,
          visualId,
        ],
      );
      await db.execute(`UPDATE dreams SET status = ? WHERE id = ?`, ['visualized', dreamId]);
      if (!usedFree?.used_free_quota) {
        await db.execute(
          `UPDATE user_comic_entitlements SET paid_comics_generated = paid_comics_generated + 1, updated_at = ? WHERE user_id = ?`,
          [nowIso(), userId],
        );
      }
      await notifyVisualPushIfNeeded(visualId, userId, dreamId, styleKey, 'visual_done');
    } else if (result.successfulPanelCount === 0) {
      if (usedFree?.used_free_quota) {
        await refundFreeComicQuota(userId);
      }
      const { code, internalReason } = resolveFailureForZeroPanels({
        lastError: result.lastError,
        hadModerationBlock: result.hadModerationBlock,
      });
      await markVisualFailed(visualId, {
        failureCode: code,
        internalReason,
        seedreamCallCount: result.seedreamCallCount,
        successfulPanelCount: 0,
        estimatedCostCny: result.estimatedCostCny,
      });
      await notifyVisualPushIfNeeded(visualId, userId, dreamId, styleKey, 'visual_failed', code);
    } else {
      await markVisualFailed(visualId, {
        failureCode: 'partial_success',
        internalReason: `已生成 ${result.successfulPanelCount}/4 格，本次额度已使用`,
        seedreamCallCount: result.seedreamCallCount,
        successfulPanelCount: result.successfulPanelCount,
        estimatedCostCny: result.estimatedCostCny,
        imageUrlsJson: serializeComicPanelsJson(slotPanels),
      });
      await notifyVisualPushIfNeeded(
        visualId,
        userId,
        dreamId,
        styleKey,
        'visual_failed',
        'partial_success',
      );
    }
  } catch (e) {
    if (usedFree?.used_free_quota) {
      await refundFreeComicQuota(userId);
    }
    const raw = e instanceof Error ? e.message : '生成失败';
    const code = classifyVisualFailure(raw);
    await markVisualFailed(visualId, {
      failureCode: code,
      internalReason: raw,
    });
    await notifyVisualPushIfNeeded(visualId, userId, dreamId, styleKey, 'visual_failed', code);
  }
}

export function createVisualsRouter(): Router {
  const router = Router();

  router.post('/four-panel', requireAuth, async (req, res) => {
    const dreamId = String(req.body?.dreamId || '');
    const styleKey = String(req.body?.styleKey || 'noir-comic');
    const transactionJws = req.body?.transactionJws as string | undefined;
    const forceNew = req.body?.forceNew === true;
    const userId = req.auth!.userId;

    const db = getDb();
    const dream = await db.queryOne<{ id: string; status: string; narrative_hash: string | null; refined_narrative: string | null }>(
      `SELECT id, status, narrative_hash, refined_narrative FROM dreams WHERE id = ? AND user_id = ?`,
      [dreamId, userId],
    );
    if (!dream) {
      res.status(404).json({ error: '梦境不存在' });
      return;
    }
    if (dream.status !== 'analyzed' && dream.status !== 'visualized') {
      res.status(400).json({ error: '请先完成梦析' });
      return;
    }

    const currentHash =
      dream.narrative_hash || computeNarrativeHash(dream.refined_narrative || '');

    if (!forceNew) {
      const existing = await db.queryOne<{ id: string; image_urls_json: string; narrative_hash_at_gen: string | null }>(
        `SELECT id, image_urls_json, narrative_hash_at_gen FROM dream_visuals
         WHERE dream_id = ? AND style_key = ? AND status = 'succeeded'
         ORDER BY created_at DESC LIMIT 1`,
        [dreamId, styleKey],
      );
      if (existing && existing.narrative_hash_at_gen === currentHash) {
        const urls = visualUrlsFromJson(existing.image_urls_json);
        res.json({
          visualId: existing.id,
          status: 'succeeded',
          reused: true,
          imageUrls: urls.imageUrls,
          imageThumbUrls: urls.imageThumbUrls,
        });
        return;
      }
    }

    let usedFree = false;
    let paymentOrderId: string | null = null;

    const freeRemaining = await getFreeComicsRemaining(userId);
    if (freeRemaining > 0) {
      if (!(await reserveFreeComicQuota(userId))) {
        res.status(400).json({ error: '体验额度不足' });
        return;
      }
      usedFree = true;
    } else {
      if (!transactionJws) {
        res.status(402).json({ error: '需要支付', productId: env.iapProductId });
        return;
      }
      try {
        const verified = await verifyAppleTransaction(transactionJws, env.iapProductId);
        const existingOrder = await db.queryOne<{ visual_id: string | null }>(
          `SELECT visual_id FROM payment_orders WHERE apple_transaction_id = ?`,
          [verified.transactionId],
        );
        if (existingOrder?.visual_id && !forceNew) {
          const v = await db.queryOne<{ status: string; image_urls_json: string }>(
            `SELECT status, image_urls_json FROM dream_visuals WHERE id = ?`,
            [existingOrder.visual_id],
          );
          if (v?.status === 'succeeded') {
            const urls = visualUrlsFromJson(v.image_urls_json);
            res.json({
              visualId: existingOrder.visual_id,
              status: 'succeeded',
              reused: true,
              imageUrls: urls.imageUrls,
              imageThumbUrls: urls.imageThumbUrls,
            });
            return;
          }
          res.json({ visualId: existingOrder.visual_id, status: 'queued', reused: true });
          return;
        }
        paymentOrderId = uuidv4();
        await db.execute(
          `INSERT INTO payment_orders (id, user_id, dream_id, product_id, apple_transaction_id, apple_original_transaction_id, environment, status, verified_at, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            paymentOrderId,
            userId,
            dreamId,
            verified.productId,
            verified.transactionId,
            verified.originalTransactionId,
            verified.environment,
            'verified',
            nowIso(),
            nowIso(),
          ],
        );
      } catch (e) {
        res.status(400).json({ error: e instanceof Error ? e.message : '支付验证失败' });
        return;
      }
    }

    const visualId = uuidv4();
    const ts = nowIso();
    await db.execute(
      `INSERT INTO dream_visuals (id, dream_id, user_id, type, style_key, status, created_at, updated_at, used_free_quota, narrative_hash_at_gen)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        visualId,
        dreamId,
        userId,
        'four_panel_comic',
        styleKey,
        'queued',
        ts,
        ts,
        usedFree ? 1 : 0,
        currentHash,
      ],
    );

    if (paymentOrderId) {
      await db.execute(`UPDATE payment_orders SET visual_id = ? WHERE id = ?`, [visualId, paymentOrderId]);
    }

    setImmediate(() => {
      runComicGeneration(visualId, dreamId, userId, styleKey).catch(console.error);
    });

    res.json({ visualId, status: 'queued', reused: false });
  });

  router.get('/:visualId', requireAuth, async (req, res) => {
    const row = await getDb().queryOne<Record<string, unknown>>(
      `SELECT * FROM dream_visuals WHERE id = ? AND user_id = ?`,
      [req.params.visualId, req.auth!.userId],
    );
    if (!row) {
      res.status(404).json({ error: '任务不存在' });
      return;
    }
    const urls = visualUrlsFromJson(row.image_urls_json);
    res.json({
      id: row.id,
      dreamId: row.dream_id,
      type: row.type,
      status: row.status,
      styleKey: row.style_key,
      imageUrl: row.image_url ? resolvePublicUrl(String(row.image_url)) : undefined,
      imageUrls: urls.imageUrls,
      imageThumbUrls: urls.imageThumbUrls,
      imageUrlsPartial: urls.imageUrlsPartial,
      imageThumbUrlsPartial: urls.imageThumbUrlsPartial,
      failureReason: row.failure_reason,
      failureCode: row.failure_code ?? undefined,
      userMessage:
        row.status === 'failed' && row.failure_code
          ? userMessageForFailure(
              String(row.failure_code) as VisualFailureCode,
              Number(row.successful_panel_count) || 0,
            )
          : undefined,
      quotaRefunded:
        row.status === 'failed' &&
        Number(row.successful_panel_count) === 0 &&
        Number(row.used_free_quota) === 1,
      successfulPanelCount: row.successful_panel_count,
      narrativeHashAtGen: row.narrative_hash_at_gen,
    });
  });

  return router;
}
