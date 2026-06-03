import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { v4 as uuidv4 } from 'uuid';
import { requireAppleLogin } from '../middleware/auth';
import { getDb, nowIso } from '../db';

const redeemLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  message: { error: '尝试次数过多，请稍后再试' },
});

export function createInviteRouter(): Router {
  const router = Router();

  router.post('/redeem', requireAppleLogin, redeemLimiter, async (req, res) => {
    const code = String(req.body?.code || '')
      .trim()
      .toUpperCase();
    if (!code) {
      res.status(400).json({ error: '请输入兑换码' });
      return;
    }

    const db = getDb();
    const userId = req.auth!.userId;

    const existing = await db.queryOne(
      `SELECT 1 AS ok FROM user_comic_entitlements WHERE user_id = ? AND free_comics_total > 0`,
      [userId],
    );
    if (existing) {
      res.status(400).json({ error: '兑换码无效或已使用' });
      return;
    }

    const invite = await db.queryOne<{
      id: string;
      status: string;
      free_comic_quota: number;
    }>(`SELECT * FROM invite_codes WHERE code = ?`, [code]);

    if (!invite || invite.status !== 'active') {
      res.status(400).json({ error: '兑换码无效或已使用' });
      return;
    }

    const ts = nowIso();
    await db.execute(
      `UPDATE invite_codes SET status = ?, redeemed_by_user_id = ?, redeemed_at = ? WHERE id = ?`,
      ['redeemed', userId, ts, invite.id],
    );

    await db.execute(
      `INSERT INTO user_comic_entitlements (user_id, invite_code_id, free_comics_total, free_comics_used, paid_comics_generated, updated_at)
       VALUES (?, ?, ?, 0, 0, ?)`,
      [userId, invite.id, invite.free_comic_quota, ts],
    );

    res.json({
      success: true,
      freeComicsTotal: invite.free_comic_quota,
      freeComicsRemaining: invite.free_comic_quota,
      message: `已激活体验资格，${invite.free_comic_quota} 次免费漫画已到账`,
    });
  });

  return router;
}

export function generateInviteCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const part = () =>
    Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
  return `MENGJI-${part()}-${part()}`;
}

export async function insertInviteCodes(count: number, batchName: string): Promise<string[]> {
  const db = getDb();
  const codes: string[] = [];
  const ts = nowIso();
  for (let i = 0; i < count; i++) {
    let code = generateInviteCode();
    while (await db.queryOne(`SELECT 1 AS ok FROM invite_codes WHERE code = ?`, [code])) {
      code = generateInviteCode();
    }
    await db.execute(
      `INSERT INTO invite_codes (id, code, batch_name, free_comic_quota, status, created_at) VALUES (?, ?, ?, 10, ?, ?)`,
      [uuidv4(), code, batchName, 'active', ts],
    );
    codes.push(code);
  }
  return codes;
}
