import fs from 'fs';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';

export interface IapVerification {
  transactionId: string;
  originalTransactionId: string;
  environment: 'Sandbox' | 'Production';
  productId: string;
}

interface TransactionPayload {
  transactionId?: string;
  originalTransactionId?: string;
  environment?: string;
  productId?: string;
  bundleId?: string;
}

function decodeJwsPayload(transactionJws: string): TransactionPayload {
  const parts = transactionJws.split('.');
  if (parts.length < 2) {
    throw new Error('无效的交易凭证');
  }
  return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')) as TransactionPayload;
}

function parseTransactionPayload(raw: string): TransactionPayload {
  const trimmed = raw.trim();
  if (trimmed.startsWith('{')) {
    return JSON.parse(trimmed) as TransactionPayload;
  }
  return decodeJwsPayload(trimmed);
}

function hasAppStoreApiCredentials(): boolean {
  return Boolean(
    env.appleKeyId &&
      env.appleIssuerId &&
      env.applePrivateKeyPath &&
      fs.existsSync(env.applePrivateKeyPath),
  );
}

function buildAppStoreApiToken(): string {
  const privateKey = fs.readFileSync(env.applePrivateKeyPath, 'utf8');
  return jwt.sign({}, privateKey, {
    algorithm: 'ES256',
    expiresIn: '5m',
    issuer: env.appleIssuerId,
    audience: 'appstoreconnect-v1',
    header: { alg: 'ES256', kid: env.appleKeyId, typ: 'JWT' },
  });
}

async function verifyViaAppStoreApi(transactionId: string): Promise<TransactionPayload> {
  const token = buildAppStoreApiToken();
  const bases = [
    'https://api.storekit.itunes.apple.com',
    'https://api.storekit-sandbox.itunes.apple.com',
  ];

  for (const base of bases) {
    const res = await fetch(`${base}/inApps/v1/transactions/${transactionId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) continue;
    if (!res.ok) {
      throw new Error(`App Store 验证失败 ${res.status}`);
    }
    const data = (await res.json()) as { signedTransactionInfo?: string };
    if (!data.signedTransactionInfo) {
      throw new Error('App Store 未返回交易信息');
    }
    return decodeJwsPayload(data.signedTransactionInfo);
  }
  throw new Error('交易不存在或无法验证');
}

function payloadToVerification(payload: TransactionPayload, expectedProductId: string): IapVerification {
  if (env.appleBundleId && payload.bundleId && payload.bundleId !== env.appleBundleId) {
    throw new Error('Bundle ID 不匹配');
  }
  if (payload.productId !== expectedProductId) {
    throw new Error('商品 ID 不匹配');
  }
  if (!payload.transactionId) {
    throw new Error('缺少 transactionId');
  }
  return {
    transactionId: payload.transactionId,
    originalTransactionId: payload.originalTransactionId || payload.transactionId,
    environment: payload.environment === 'Production' ? 'Production' : 'Sandbox',
    productId: payload.productId || expectedProductId,
  };
}

export async function verifyAppleTransaction(
  transactionPayload: string,
  expectedProductId: string,
): Promise<IapVerification> {
  if (env.appleIapSkipVerify) {
    const mockId = `mock-${Date.now()}`;
    return {
      transactionId: mockId,
      originalTransactionId: mockId,
      environment: 'Sandbox',
      productId: expectedProductId,
    };
  }

  const payload = parseTransactionPayload(transactionPayload);

  if (hasAppStoreApiCredentials() && payload.transactionId) {
    const verified = await verifyViaAppStoreApi(payload.transactionId);
    return payloadToVerification({ ...payload, ...verified }, expectedProductId);
  }

  return payloadToVerification(payload, expectedProductId);
}
