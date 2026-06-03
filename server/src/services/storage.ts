import fs from 'fs';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import COS from 'cos-nodejs-sdk-v5';
import sharp from 'sharp';
import { env, hasCos } from '../config/env';
import type { ComicPanelRef } from './comicImageUrls';

const COMIC_THUMB_MAX_EDGE = 768;
const COMIC_THUMB_JPEG_QUALITY = 82;

let cosClient: COS | null = null;

function getCosClient(): COS {
  if (!cosClient) {
    cosClient = new COS({
      SecretId: env.cosSecretId,
      SecretKey: env.cosSecretKey,
    });
  }
  return cosClient;
}

function cosPutObject(key: string, buffer: Buffer): Promise<void> {
  return new Promise((resolve, reject) => {
    getCosClient().putObject(
      {
        Bucket: env.cosBucket,
        Region: env.cosRegion,
        Key: key,
        Body: buffer,
      },
      (err) => {
        if (err) reject(err);
        else resolve();
      },
    );
  });
}

function cosGetObject(key: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    getCosClient().getObject(
      {
        Bucket: env.cosBucket,
        Region: env.cosRegion,
        Key: key,
      },
      (err, data) => {
        if (err) return reject(err);
        const body = data.Body;
        if (Buffer.isBuffer(body)) return resolve(body);
        if (typeof body === 'string') return resolve(Buffer.from(body));
        reject(new Error('COS 返回空内容'));
      },
    );
  });
}

export function getSignedUrl(storageKey: string): string {
  if (!hasCos()) {
    return `${env.publicBaseUrl}/uploads/${storageKey.replace(/\\/g, '/')}`;
  }
  return getCosClient().getObjectUrl({
    Bucket: env.cosBucket,
    Region: env.cosRegion,
    Key: storageKey,
    Sign: true,
    Expires: env.cosSignedUrlTtlSeconds,
  });
}

export function resolvePublicUrl(storageKeyOrUrl: string): string {
  if (storageKeyOrUrl.startsWith('http://') || storageKeyOrUrl.startsWith('https://')) {
    return storageKeyOrUrl;
  }
  const key = storageKeyOrUrl.replace(/^\/uploads\//, '').replace(/^uploads\//, '');
  return getSignedUrl(key);
}

export async function saveUpload(
  buffer: Buffer,
  ext: string,
  subdir: string,
): Promise<{ storageKey: string; publicUrl: string }> {
  const id = uuidv4();
  const safeExt = ext.replace(/[^a-z0-9.]/gi, '') || 'bin';
  const storageKey = `${subdir}/${id}.${safeExt}`.replace(/\\/g, '/');

  if (hasCos()) {
    await cosPutObject(storageKey, buffer);
    return { storageKey, publicUrl: getSignedUrl(storageKey) };
  }

  const absolute = path.join(env.uploadsDir, storageKey);
  fs.mkdirSync(path.dirname(absolute), { recursive: true });
  fs.writeFileSync(absolute, buffer);
  const publicUrl = `${env.publicBaseUrl}/uploads/${storageKey}`;
  return { storageKey, publicUrl };
}

/** 四格单张：保存原图 + 768px JPEG 缩略图 */
export async function saveComicPanelUpload(
  buffer: Buffer,
  subdir: string,
): Promise<ComicPanelRef> {
  const id = uuidv4();
  const fullKey = `${subdir}/${id}.png`.replace(/\\/g, '/');
  const thumbKey = `${subdir}/${id}_thumb.jpg`.replace(/\\/g, '/');

  let thumbBuffer: Buffer;
  try {
    thumbBuffer = await sharp(buffer)
      .rotate()
      .resize(COMIC_THUMB_MAX_EDGE, COMIC_THUMB_MAX_EDGE, {
        fit: 'inside',
        withoutEnlargement: true,
      })
      .jpeg({ quality: COMIC_THUMB_JPEG_QUALITY, mozjpeg: true })
      .toBuffer();
  } catch (err) {
    console.warn('[storage] thumb generation failed, using full image as thumb', err);
    thumbBuffer = buffer;
  }

  if (hasCos()) {
    await cosPutObject(fullKey, buffer);
    await cosPutObject(thumbKey, thumbBuffer);
  } else {
    for (const [key, body] of [
      [fullKey, buffer],
      [thumbKey, thumbBuffer],
    ] as const) {
      const absolute = path.join(env.uploadsDir, key);
      fs.mkdirSync(path.dirname(absolute), { recursive: true });
      fs.writeFileSync(absolute, body);
    }
  }

  return { full: fullKey, thumb: thumbKey };
}

export async function readUpload(storageKey: string): Promise<Buffer> {
  const key = storageKey.replace(/^\/uploads\//, '').replace(/^uploads\//, '');

  if (hasCos()) {
    return cosGetObject(key);
  }

  const absolute = path.join(env.uploadsDir, key);
  return fs.readFileSync(absolute);
}

export async function writeTempFile(buffer: Buffer, ext: string): Promise<string> {
  const tmpDir = path.join(env.uploadsDir, '_tmp');
  fs.mkdirSync(tmpDir, { recursive: true });
  const filePath = path.join(tmpDir, `${uuidv4()}.${ext}`);
  fs.writeFileSync(filePath, buffer);
  return filePath;
}
