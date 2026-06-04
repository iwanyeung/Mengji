/**
 * One-time: generates StylePreviewNoir / StylePreviewNeon into iOS Assets.
 * Usage: npx tsx src/scripts/generate-style-preview-assets.ts
 */
import fs from 'fs';
import path from 'path';
import { env, hasSeedream } from '../config/env';

const OUT_DIR = path.resolve(
  __dirname,
  '../../../ios-app/MengJiApp/MengjiApp/MengjiApp/Assets.xcassets',
);

/** 风格预览图固定竖版 3:4（与 prompt 的 vertical poster 3:4 一致），不随四格漫画的 16:9 默认尺寸变化。 */
const STYLE_PREVIEW_SIZE = '1728x2304';

const STYLES = [
  {
    name: 'StylePreviewNoir',
    prompt:
      'High contrast black and white grainy four-panel comic style sample, noir newspaper halftone, surreal dream scene silhouette, no text, vertical poster 3:4',
  },
  {
    name: 'StylePreviewNeon',
    prompt:
      'Neon surreal collage four-panel comic style sample, vivid pink and cyan, dreamlike cutout figures, no text, vertical poster 3:4',
  },
] as const;

async function fetchSeedreamImage(prompt: string): Promise<Buffer> {
  const res = await fetch(`${env.arkBaseUrl}/images/generations`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.arkApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: env.arkImageModel,
      prompt: prompt.slice(0, 500),
      size: STYLE_PREVIEW_SIZE,
      n: 1,
      response_format: 'url',
    }),
  });
  if (!res.ok) throw new Error(await res.text());
  const data = (await res.json()) as { data?: Array<{ url?: string }> };
  const url = data.data?.[0]?.url;
  if (!url) throw new Error('No image url');
  const img = await fetch(url);
  return Buffer.from(await img.arrayBuffer());
}

/** Minimal solid-fill PNG (width x height, RGB) */
function solidPng(width: number, height: number, r: number, g: number, b: number): Buffer {
  const raw: number[] = [];
  for (let y = 0; y < height; y++) {
    raw.push(0);
    for (let x = 0; x < width; x++) {
      const t = y / height;
      raw.push(
        Math.min(255, Math.floor(r * (1 - t * 0.3))),
        Math.min(255, Math.floor(g * (1 - t * 0.2))),
        Math.min(255, Math.floor(b + t * 40)),
      );
    }
  }
  const zlib = require('zlib') as typeof import('zlib');
  const compressed = zlib.deflateSync(Buffer.from(raw), { level: 9 });

  function crc32(buf: Buffer): number {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) {
      c ^= buf[i];
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    return (c ^ 0xffffffff) >>> 0;
  }

  function chunk(type: string, data: Buffer): Buffer {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const t = Buffer.from(type);
    const crcBuf = Buffer.concat([t, data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(crcBuf));
    return Buffer.concat([len, t, data, crc]);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', compressed),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

async function writeImageset(name: string, buffer: Buffer) {
  const dir = path.join(OUT_DIR, `${name}.imageset`);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${name}.png`), buffer);
  fs.writeFileSync(
    path.join(dir, 'Contents.json'),
    JSON.stringify(
      {
        images: [{ filename: `${name}.png`, idiom: 'universal', scale: '1x' }],
        info: { author: 'xcode', version: 1 },
      },
      null,
      2,
    ),
  );
  console.log(`Wrote ${dir}`);
}

async function main() {
  const useApi = hasSeedream() && !env.aiMock;
  for (let i = 0; i < STYLES.length; i++) {
    const style = STYLES[i];
    let buf: Buffer;
    if (useApi) {
      try {
        buf = await fetchSeedreamImage(style.prompt);
        console.log(`Seedream OK: ${style.name}`);
      } catch (e) {
        console.warn(`Seedream failed for ${style.name}, using placeholder`, e);
        buf = solidPng(768, 1024, i === 0 ? 40 : 255, i === 0 ? 40 : 60, i === 0 ? 40 : 120);
      }
    } else {
      buf = solidPng(768, 1024, i === 0 ? 212 : 255, i === 0 ? 255 : 51, i === 0 ? 51 : 102);
    }
    await writeImageset(style.name, buf);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
