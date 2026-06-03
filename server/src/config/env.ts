import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

dotenv.config();

function loadApnsPrivateKey(): string {
  const inline = process.env.APNS_PRIVATE_KEY || '';
  if (inline) return inline;

  const keyPath = process.env.APNS_PRIVATE_KEY_PATH || '';
  if (!keyPath) return '';

  const resolved = path.isAbsolute(keyPath) ? keyPath : path.resolve(process.cwd(), keyPath);
  if (!fs.existsSync(resolved)) {
    console.warn(`[env] APNS_PRIVATE_KEY_PATH not found: ${resolved}`);
    return '';
  }
  return fs.readFileSync(resolved, 'utf8');
}

function bool(v: string | undefined, fallback: boolean): boolean {
  if (v === undefined || v === '') return fallback;
  return v === '1' || v.toLowerCase() === 'true';
}

export const env = {
  port: Number(process.env.PORT || 3000),
  jwtSecret: process.env.JWT_SECRET || 'dev-secret-change-me',
  publicBaseUrl: (process.env.PUBLIC_BASE_URL || 'http://localhost:3000').replace(/\/$/, ''),
  databasePath: process.env.DATABASE_PATH || path.join(process.cwd(), 'data', 'mengji.db'),
  mysqlUrl: process.env.MYSQL_URL || '',
  uploadsDir: path.join(process.cwd(), 'data', 'uploads'),
  cosSignedUrlTtlSeconds: Number(process.env.COS_SIGNED_URL_TTL || 3600),

  deepseekApiKey: process.env.DEEPSEEK_API_KEY || '',
  deepseekModel: process.env.DEEPSEEK_MODEL || 'deepseek-chat',

  arkApiKey: process.env.ARK_API_KEY || '',
  arkImageModel: process.env.ARK_IMAGE_MODEL || 'doubao-seedream-5-0-260128',
  arkBaseUrl: process.env.ARK_BASE_URL || 'https://ark.cn-beijing.volces.com/api/v3',

  speechAppKey: process.env.SPEECH_APP_KEY || '',
  speechAccessKey: process.env.SPEECH_ACCESS_KEY || '',

  cosSecretId: process.env.COS_SECRET_ID || '',
  cosSecretKey: process.env.COS_SECRET_KEY || '',
  cosBucket: process.env.COS_BUCKET || '',
  cosRegion: process.env.COS_REGION || 'ap-guangzhou',

  appleBundleId: process.env.APPLE_BUNDLE_ID || 'com.mengji.app',
  appleKeyId: process.env.APPLE_APP_STORE_KEY_ID || '',
  appleIssuerId: process.env.APPLE_APP_STORE_ISSUER_ID || '',
  applePrivateKeyPath: process.env.APPLE_APP_STORE_PRIVATE_KEY_PATH || '',
  appleIapSkipVerify: bool(process.env.APPLE_IAP_SKIP_VERIFY, true),

  aiMock: bool(process.env.AI_MOCK, true),
  dailyDreamAnalysisLimit: Number(process.env.DAILY_DREAM_ANALYSIS_LIMIT || 30),

  iapProductId: process.env.IAP_PRODUCT_ID || 'com.mengji.visual.four_panel_once',

  /** Ark Seedream 要求至少约 1920×1920 像素；可用 2K 或 1920x1920 */
  seedreamImageSize: process.env.SEEDREAM_IMAGE_SIZE || '2K',

  apnsKeyId: process.env.APNS_KEY_ID || '',
  apnsTeamId: process.env.APNS_TEAM_ID || '',
  apnsBundleId: process.env.APNS_BUNDLE_ID || process.env.APPLE_BUNDLE_ID || '',
  apnsPrivateKey: loadApnsPrivateKey(),
  apnsUseSandbox: bool(process.env.APNS_USE_SANDBOX, true),
};

export function hasDeepSeek(): boolean {
  return Boolean(env.deepseekApiKey) || env.aiMock;
}

export function hasSeedream(): boolean {
  return Boolean(env.arkApiKey) || env.aiMock;
}

export function hasSpeechAsr(): boolean {
  return Boolean(env.speechAppKey && env.speechAccessKey) || env.aiMock;
}

export function hasCos(): boolean {
  return Boolean(env.cosSecretId && env.cosSecretKey && env.cosBucket && env.cosRegion);
}
