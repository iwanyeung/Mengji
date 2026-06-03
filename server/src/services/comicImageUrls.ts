import { resolvePublicUrl } from './storage';

export interface ComicPanelRef {
  full: string;
  thumb: string;
}

export type ComicPanelSlot = ComicPanelRef | null;

export function parseComicPanelsJson(raw: unknown): ComicPanelSlot[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(String(raw)) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.map(normalizePanelSlot);
  } catch {
    return [];
  }
}

function normalizePanelSlot(entry: unknown): ComicPanelSlot {
  if (entry == null) return null;
  if (typeof entry === 'string') {
    const key = storageKeyFromLegacy(entry);
    return { full: key, thumb: key };
  }
  if (typeof entry === 'object' && entry !== null) {
    const obj = entry as { full?: string; thumb?: string };
    const full = obj.full ? storageKeyFromLegacy(obj.full) : '';
    const thumb = obj.thumb ? storageKeyFromLegacy(obj.thumb) : full;
    if (!full) return null;
    return { full, thumb: thumb || full };
  }
  return null;
}

/** 从旧版 signed URL 或 storage key 提取可 resolve 的 key/路径 */
function storageKeyFromLegacy(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return trimmed.replace(/^\/uploads\//, '').replace(/^uploads\//, '');
}

export function serializeComicPanelsJson(panels: ComicPanelSlot[]): string {
  return JSON.stringify(panels);
}

export function resolveComicPanelUrls(panels: ComicPanelSlot[]): {
  imageUrls: (string | null)[];
  imageThumbUrls: (string | null)[];
} {
  return {
    imageUrls: panels.map((p) => (p ? resolvePublicUrl(p.full) : null)),
    imageThumbUrls: panels.map((p) => (p ? resolvePublicUrl(p.thumb) : null)),
  };
}

export function resolvedFullUrls(panels: ComicPanelSlot[]): string[] {
  return panels
    .filter((p): p is ComicPanelRef => Boolean(p))
    .map((p) => resolvePublicUrl(p.full));
}

export function resolvedThumbUrls(panels: ComicPanelSlot[]): string[] {
  return panels
    .filter((p): p is ComicPanelRef => Boolean(p))
    .map((p) => resolvePublicUrl(p.thumb));
}

export function visualUrlsFromJson(raw: unknown): {
  imageUrls: string[];
  imageThumbUrls: string[];
  imageUrlsPartial: (string | null)[];
  imageThumbUrlsPartial: (string | null)[];
} {
  const panels = parseComicPanelsJson(raw);
  const { imageUrls, imageThumbUrls } = resolveComicPanelUrls(panels);
  return {
    imageUrls: imageUrls.filter((u): u is string => Boolean(u)),
    imageThumbUrls: imageThumbUrls.filter((u): u is string => Boolean(u)),
    imageUrlsPartial: imageUrls,
    imageThumbUrlsPartial: imageThumbUrls,
  };
}
