import { env, hasSeedream } from '../config/env';
import { isModerationError } from './visualFailure';
import type { ComicPanelRef } from './comicImageUrls';

const SEEDREAM_COST_PER_IMAGE = 0.2;
export const MAX_RETRIES_PER_PANEL = 1;

export interface PanelGenerationResult {
  panels: ComicPanelRef[];
  seedreamCallCount: number;
  successfulPanelCount: number;
  estimatedCostCny: number;
  captions: string[];
  /** Last panel error message (for failure classification) */
  lastError?: string;
  hadModerationBlock?: boolean;
}

export type PanelProgressCallback = (
  index: number,
  panel: ComicPanelRef,
  completedCount: number,
  panelsSoFar: (ComicPanelRef | null)[],
) => Promise<void>;

export async function generateFourPanels(
  panels: Array<{ seedreamPrompt: string; caption: string }>,
  uploadPanel: (buffer: Buffer, index: number) => Promise<ComicPanelRef>,
  onPanelComplete?: PanelProgressCallback,
): Promise<PanelGenerationResult> {
  const captions: string[] = [];
  const panelsSoFar: (ComicPanelRef | null)[] = [null, null, null, null];
  let seedreamCallCount = 0;
  let lastError: string | undefined;
  let hadModerationBlock = false;

  const tasks = panels.slice(0, 4).map(async (panel, i) => {
    if (!panel) return { index: i, success: false as const };
    captions[i] = panel.caption;

    for (let attempt = 0; attempt <= MAX_RETRIES_PER_PANEL; attempt++) {
      try {
        const buffer = await generateOneImage(panel.seedreamPrompt);
        seedreamCallCount += 1;
        const panelRef = await uploadPanel(buffer, i);
        panelsSoFar[i] = panelRef;
        const completedCount = panelsSoFar.filter(Boolean).length;
        if (onPanelComplete) {
          await onPanelComplete(i, panelRef, completedCount, [...panelsSoFar]);
        }
        return { index: i, success: true as const, panel: panelRef };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        lastError = msg;
        if (isModerationError(msg)) hadModerationBlock = true;
        console.warn(`Panel ${i + 1} attempt ${attempt + 1} failed`, err);
      }
    }
    return { index: i, success: false as const };
  });

  const results = await Promise.all(tasks);
  results.sort((a, b) => a.index - b.index);

  const generatedPanels: ComicPanelRef[] = [];
  let successfulPanelCount = 0;
  for (const r of results) {
    if (r.success && r.panel) {
      generatedPanels.push(r.panel);
      successfulPanelCount += 1;
    } else {
      break;
    }
  }

  return {
    panels: generatedPanels,
    seedreamCallCount,
    successfulPanelCount,
    estimatedCostCny: seedreamCallCount * SEEDREAM_COST_PER_IMAGE,
    captions,
    lastError,
    hadModerationBlock,
  };
}

async function generateOneImage(prompt: string): Promise<Buffer> {
  if (env.aiMock || !env.arkApiKey) {
    return mockPngBuffer(prompt);
  }
  if (!hasSeedream()) {
    return mockPngBuffer(prompt);
  }

  const res = await fetch(`${env.arkBaseUrl}/images/generations`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.arkApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: env.arkImageModel,
      prompt: prompt.slice(0, 500),
      size: env.seedreamImageSize,
      n: 1,
      response_format: 'url',
    }),
  });

  if (!res.ok) {
    throw new Error(`Seedream error ${res.status}: ${await res.text()}`);
  }

  const data = (await res.json()) as {
    data?: Array<{ url?: string; b64_json?: string }>;
  };
  const item = data.data?.[0];
  if (item?.b64_json) {
    return Buffer.from(item.b64_json, 'base64');
  }
  if (item?.url) {
    const imgRes = await fetch(item.url);
    if (!imgRes.ok) throw new Error('Failed to download generated image');
    return Buffer.from(await imgRes.arrayBuffer());
  }
  throw new Error('Empty Seedream response');
}

function mockPngBuffer(prompt: string): Buffer {
  const hash = prompt.length % 256;
  const png = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44,
    0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00,
    0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7,
    0x63, hash, hash, hash, 0x00, 0x00, 0x00, 0x04, 0x00, 0x01, 0x27, 0x34, 0x27, 0x0a,
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ]);
  return png;
}

export { SEEDREAM_COST_PER_IMAGE };
