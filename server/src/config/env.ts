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
  /** Seedream 4.0 支持 1280x720；5.0 自定义像素下限为 2560x1440，勿与 seedreamImageSize 混用。 */
  arkImageModel: process.env.ARK_IMAGE_MODEL || 'doubao-seedream-4-0-250828',
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

  /**
   * 四格漫画每格出图尺寸。默认 16:9 横版（1280x720），与客户端单格 16:9 布局对齐，避免左右裁切。
   * 1280x720 是 doubao-seedream-4.0 支持的 16:9 最小档（总像素 921600），长边 1280 已覆盖客户端
   * 全屏 1200px 与 768px 缩略图的展示需求，无需更高分辨率，生成更快、产图与下载体积更小。
   */
  seedreamImageSize: process.env.SEEDREAM_IMAGE_SIZE || '1280x720',

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

/** staging 使用 http:// 公网 IP 时为 false；生产 https:// 域名时为 true */
export function isPublicHttps(): boolean {
  return env.publicBaseUrl.startsWith('https://');
}
