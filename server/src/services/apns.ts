import http2 from 'http2';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { getDb, nowIso } from '../db';

export type VisualPushType = 'visual_done' | 'visual_failed';

export interface VisualPushPayload {
  type: VisualPushType;
  visualId: string;
  dreamId: string;
  styleKey: string;
  failureCode?: string;
}

export function hasApns(): boolean {
  return Boolean(env.apnsKeyId && env.apnsTeamId && env.apnsBundleId && env.apnsPrivateKey);
}

function apnsPrivateKeyPem(): string {
  return env.apnsPrivateKey.replace(/\\n/g, '\n');
}

function createApnsJwt(): string {
  return jwt.sign({}, apnsPrivateKeyPem(), {
    algorithm: 'ES256',
    issuer: env.apnsTeamId,
    header: { alg: 'ES256', kid: env.apnsKeyId },
    expiresIn: '50m',
  });
}

async function sendApnsAlert(
  deviceToken: string,
  environment: 'sandbox' | 'production',
  alert: { title: string; body: string },
  custom: VisualPushPayload,
): Promise<void> {
  const host = environment === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
  const authToken = createApnsJwt();
  const payload = JSON.stringify({
    aps: {
      alert,
      sound: 'default',
    },
    ...custom,
  });

  await new Promise<void>((resolve, reject) => {
    const client = http2.connect(`https://${host}`);
    client.on('error', reject);

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${authToken}`,
      'apns-topic': env.apnsBundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
      'content-length': Buffer.byteLength(payload),
    });

    req.on('response', (headers) => {
      const status = Number(headers[':status'] || 0);
      req.on('data', () => {});
      req.on('end', () => {
        client.close();
        if (status >= 200 && status < 300) {
          resolve();
        } else {
          reject(new Error(`APNs HTTP ${status}`));
        }
      });
    });
    req.on('error', (err) => {
      client.close();
      reject(err);
    });
    req.write(payload);
    req.end();
  });
}

function alertForPush(custom: VisualPushPayload): { title: string; body: string } {
  if (custom.type === 'visual_done') {
    return {
      title: '四格已落成',
      body: '你的梦已变成四格故事，点按查看。',
    };
  }
  switch (custom.failureCode) {
    case 'moderation_blocked':
      return {
        title: '这次还未能落成画面',
        body: '梦境已安全保存，可稍后在梦作间重试或换风格。',
      };
    case 'partial_success':
      return {
        title: '四格还未完整落成',
        body: '部分分镜已生成，可在梦作间查看详情。',
      };
    default:
      return {
        title: '四格生成未完成',
        body: '可在梦作间查看详情或稍后再试。',
      };
  }
}

export async function sendVisualCompletionPush(
  userId: string,
  custom: VisualPushPayload,
): Promise<void> {
  if (!hasApns()) {
    console.warn('[apns] skipped: APNS_* env not configured');
    return;
  }

  const db = getDb();
  const tokens = await db.query<{ token: string; environment: string }>(
    `SELECT token, environment FROM device_push_tokens WHERE user_id = ?`,
    [userId],
  );

  if (tokens.length === 0) {
    console.warn('[apns] no device tokens for user', userId);
    return;
  }

  const alert = alertForPush(custom);
  const results = await Promise.allSettled(
    tokens.map((row) =>
      sendApnsAlert(
        row.token,
        row.environment === 'production' ? 'production' : 'sandbox',
        alert,
        custom,
      ),
    ),
  );

  for (const result of results) {
    if (result.status === 'rejected') {
      console.warn('[apns] send failed:', result.reason);
    }
  }
}

export async function markVisualPushSent(visualId: string): Promise<void> {
  await getDb().execute(`UPDATE dream_visuals SET push_sent_at = ? WHERE id = ?`, [nowIso(), visualId]);
}

export async function shouldSendVisualPush(visualId: string): Promise<boolean> {
  const row = await getDb().queryOne<{ push_sent_at: string | null }>(
    `SELECT push_sent_at FROM dream_visuals WHERE id = ?`,
    [visualId],
  );
  return !row?.push_sent_at;
}
