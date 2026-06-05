import type { ComicPanelPrompt, ComicPanelSource } from './deepseek';

const SOURCE_VALUES = new Set<ComicPanelSource>(['verbatim', 'atmosphere', 'inferred']);

export function normalizePanelSource(raw: unknown): ComicPanelSource {
  if (typeof raw === 'string' && SOURCE_VALUES.has(raw as ComicPanelSource)) {
    return raw as ComicPanelSource;
  }
  return 'atmosphere';
}

export function normalizeComicPanels(panels: ComicPanelPrompt[]): ComicPanelPrompt[] {
  return panels.slice(0, 4).map((panel, index) => ({
    panelIndex: panel.panelIndex ?? index + 1,
    caption: String(panel.caption || `第${index + 1}格`).trim(),
    seedreamPrompt: String(panel.seedreamPrompt || '').trim(),
    source: normalizePanelSource(panel.source),
  }));
}

function tokenizeForMatch(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]/gu, ' ')
    .split(/\s+/)
    .filter((t) => t.length >= 2);
}

function captionMentionsKnownEntity(caption: string, vocabulary: Set<string>): boolean {
  const normalized = caption.toLowerCase();
  for (const term of vocabulary) {
    if (term.length >= 2 && normalized.includes(term.toLowerCase())) return true;
  }
  return false;
}

/** 规则校验：将明显「编造剧情」的格降级为 atmosphere，并限制 inferred 格数 */
export function enforcePanelFidelity(
  panels: ComicPanelPrompt[],
  sourceText: string,
  tags: Array<{ name: string; category: string }>,
  mode: 'imagery' | 'narrative',
): ComicPanelPrompt[] {
  const vocabulary = new Set<string>();
  for (const token of tokenizeForMatch(sourceText)) vocabulary.add(token);
  for (const tag of tags) {
    if (tag.name.trim()) vocabulary.add(tag.name.trim());
  }

  const normalized = normalizeComicPanels(panels);
  let inferredCount = 0;
  const maxInferred = mode === 'imagery' ? 1 : 2;

  return normalized.map((panel) => {
    let source = panel.source ?? 'atmosphere';

    if (source === 'inferred') {
      inferredCount += 1;
      if (inferredCount > maxInferred) source = 'atmosphere';
    }

    if (source === 'inferred' && !captionMentionsKnownEntity(panel.caption, vocabulary)) {
      source = 'atmosphere';
    }

    if (mode === 'imagery' && source === 'inferred') {
      source = 'atmosphere';
    }

    return { ...panel, source };
  });
}

export function countInferredPanels(panels: ComicPanelPrompt[]): number {
  return panels.filter((p) => p.source === 'inferred').length;
}
