import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { requireAuth } from '../middleware/auth';
import { getDb, nowIso } from '../db';
import { getFreeComicsRemaining } from '../services/dreamPipeline';

export function createMeRouter(): Router {
  const router = Router();

  router.get('/', requireAuth, async (req, res) => {
    const db = getDb();
    const user = await db.queryOne(`SELECT * FROM users WHERE id = ?`, [req.auth!.userId]);
    if (!user) {
      res.status(404).json({ error: '用户不存在' });
      return;
    }
    res.json({ user });
  });

  router.get('/entitlements', requireAuth, async (req, res) => {
    const db = getDb();
    const userId = req.auth!.userId;
    const ent = await db.queryOne<{
      free_comics_total: number;
      free_comics_used: number;
      invite_code_id: string | null;
    }>(`SELECT * FROM user_comic_entitlements WHERE user_id = ?`, [userId]);

    let channelLabel: string | null = null;
    if (ent?.invite_code_id) {
      const code = await db.queryOne<{ channel_label: string | null }>(
        `SELECT channel_label FROM invite_codes WHERE id = ?`,
        [ent.invite_code_id],
      );
      channelLabel = code?.channel_label ?? null;
    }

    const freeComicsRemaining = await getFreeComicsRemaining(userId);

    res.json({
      freeComicsRemaining,
      freeComicsTotal: ent?.free_comics_total ?? 0,
      hasRedeemedInvite: Boolean(ent && ent.free_comics_total > 0),
      inviteChannelLabel: channelLabel,
    });
  });

  router.put('/push-token', requireAuth, async (req, res) => {
    const token = String(req.body?.token || '').trim();
    const environment = String(req.body?.environment || 'sandbox').trim();
    if (!token) {
      res.status(400).json({ error: '缺少 device token' });
      return;
    }
    if (environment !== 'sandbox' && environment !== 'production') {
      res.status(400).json({ error: 'environment 须为 sandbox 或 production' });
      return;
    }

    const userId = req.auth!.userId;
    const ts = nowIso();
    const db = getDb();
    const existing = await db.queryOne<{ id: string }>(
      `SELECT id FROM device_push_tokens WHERE user_id = ? AND token = ?`,
      [userId, token],
    );

    if (existing) {
      await db.execute(`UPDATE device_push_tokens SET environment = ?, updated_at = ? WHERE id = ?`, [
        environment,
        ts,
        existing.id,
      ]);
    } else {
      await db.execute(
        `INSERT INTO device_push_tokens (id, user_id, token, platform, environment, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [uuidv4(), userId, token, 'ios', environment, ts],
      );
    }

    res.json({ ok: true });
  });

  router.get('/pending-visuals', requireAuth, async (req, res) => {
    const rows = await getDb().query<Record<string, unknown>>(
      `SELECT id, dream_id, style_key, status, successful_panel_count, updated_at
       FROM dream_visuals
       WHERE user_id = ? AND status IN ('queued', 'generating')
       ORDER BY created_at DESC`,
      [req.auth!.userId],
    );
    res.json({
      items: rows.map((row) => ({
        visualId: row.id,
        dreamId: row.dream_id,
        styleKey: row.style_key,
        status: row.status,
        successfulPanelCount: row.successful_panel_count,
        updatedAt: row.updated_at,
      })),
    });
  });

  return router;
}
