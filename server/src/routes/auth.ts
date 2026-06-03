import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { getDb, nowIso } from '../db';
import { signToken } from '../middleware/auth';

export function createAuthRouter(): Router {
  const router = Router();

  router.post('/anonymous', async (req, res) => {
    const deviceId = String(req.body?.deviceId || uuidv4());
    const db = getDb();
    let user = await db.queryOne<{ id: string }>(`SELECT id FROM users WHERE device_id = ?`, [deviceId]);

    if (!user) {
      const id = uuidv4();
      const ts = nowIso();
      await db.execute(
        `INSERT INTO users (id, created_at, updated_at, auth_provider, device_id) VALUES (?, ?, ?, ?, ?)`,
        [id, ts, ts, 'anonymous', deviceId],
      );
      user = { id };
    }

    const token = signToken({ userId: user.id, authProvider: 'anonymous' });
    res.json({
      token,
      user: { id: user.id, authProvider: 'anonymous' },
    });
  });

  router.post('/apple', async (req, res) => {
    const appleId = String(req.body?.appleUserId || '');
    const deviceId = String(req.body?.deviceId || '');
    if (!appleId) {
      res.status(400).json({ error: '缺少 appleUserId' });
      return;
    }

    const db = getDb();
    let user = await db.queryOne<{ id: string }>(`SELECT id FROM users WHERE apple_id = ?`, [appleId]);

    if (!user && deviceId) {
      const anon = await db.queryOne<{ id: string }>(`SELECT id FROM users WHERE device_id = ?`, [deviceId]);
      if (anon) {
        await db.execute(`UPDATE users SET apple_id = ?, auth_provider = ?, updated_at = ? WHERE id = ?`, [
          appleId,
          'apple',
          nowIso(),
          anon.id,
        ]);
        user = { id: anon.id };
      }
    }

    if (!user) {
      const id = uuidv4();
      const ts = nowIso();
      await db.execute(
        `INSERT INTO users (id, created_at, updated_at, auth_provider, device_id, apple_id) VALUES (?, ?, ?, ?, ?, ?)`,
        [id, ts, ts, 'apple', deviceId || null, appleId],
      );
      user = { id };
    } else {
      await db.execute(`UPDATE users SET auth_provider = ?, updated_at = ? WHERE id = ?`, [
        'apple',
        nowIso(),
        user.id,
      ]);
    }

    const token = signToken({ userId: user.id, authProvider: 'apple' });
    res.json({
      token,
      user: { id: user.id, authProvider: 'apple' },
    });
  });

  return router;
}
