export const MIN_TITLE_PHRASE_LENGTH = 4;
export const MAX_TITLE_PHRASE_LENGTH = 12;

const GENERIC_TAGS = new Set(['梦境', '自我观察', '梦', '夜', '未命名梦', '片段', '模糊']);

/** 标签类别优先级：场景/地点/物件更适合做标题意象 */
const TAG_CATEGORY_PRIORITY: Record<string, number> = {
  scene_type: 0,
  place: 1,
  object: 2,
  person: 3,
  theme: 4,
  emotion: 5,
  other: 6,
};

/** 将 AI 生成的意象短语格式化为梦析列表标题 */
export function formatDreamTitle(titlePhrase: string): string {
  const phrase = sanitizeTitlePhrase(titlePhrase) || '未命名梦境';
  return `关于「${phrase}」的夜里`;
}

export function sanitizeTitlePhrase(raw: string | undefined | null): string | null {
  if (!raw) return null;
  const trimmed = String(raw)
    .trim()
    .replace(/^关于[「『]/u, '')
    .replace(/[」』]的夜里$/u, '')
    .replace(/[「」『』]/gu, '')
    .trim();
  if (!trimmed) return null;
  const phrase = trimmed.slice(0, MAX_TITLE_PHRASE_LENGTH);
  if (phrase.length < MIN_TITLE_PHRASE_LENGTH) return null;
  return phrase;
}

/** 优先 AI 短语，不合格时用标签/正文兜底 */
export function resolveTitlePhrase(
  raw: string,
  tags?: Array<{ name: string; category?: string }>,
  fromAi?: string | null,
): string {
  const fromSanitized = sanitizeTitlePhrase(fromAi);
  if (fromSanitized) return fromSanitized;
  return deriveTitlePhrase(raw, tags);
}

/** mock / AI 缺字段时的标题短语兜底 */
export function deriveTitlePhrase(
  raw: string,
  tags?: Array<{ name: string; category?: string }>,
): string {
  const fromTags = pickTitleFromTags(tags);
  if (fromTags) return fromTags;

  const fromNarrative = pickTitleFromNarrative(raw);
  if (fromNarrative) return fromNarrative;

  return '模糊的梦';
}

function pickTitleFromTags(tags?: Array<{ name: string; category?: string }>): string | null {
  if (!tags?.length) return null;

  const eligible = tags
    .map((t) => ({
      name: t.name.trim(),
      category: (t.category || 'other').trim(),
    }))
    .filter((t) => t.name.length >= 2 && t.name.length <= MAX_TITLE_PHRASE_LENGTH && !GENERIC_TAGS.has(t.name))
    .sort((a, b) => {
      const pa = TAG_CATEGORY_PRIORITY[a.category] ?? 99;
      const pb = TAG_CATEGORY_PRIORITY[b.category] ?? 99;
      if (pa !== pb) return pa - pb;
      return b.name.length - a.name.length;
    });

  if (!eligible.length) return null;

  const longEnough = eligible.find((t) => t.name.length >= MIN_TITLE_PHRASE_LENGTH);
  if (longEnough) return longEnough.name.slice(0, MAX_TITLE_PHRASE_LENGTH);

  if (eligible.length >= 2) {
    const combined = combineTagNames(eligible[0].name, eligible[1].name);
    if (combined.length >= MIN_TITLE_PHRASE_LENGTH) {
      return combined.slice(0, MAX_TITLE_PHRASE_LENGTH);
    }
  }

  const single = eligible[0].name;
  if (single.length >= MIN_TITLE_PHRASE_LENGTH) return single;

  return null;
}

function combineTagNames(a: string, b: string): string {
  if (a.length + b.length + 1 <= MAX_TITLE_PHRASE_LENGTH) {
    return `${a}的${b}`;
  }
  return `${a}与${b}`;
}

function pickTitleFromNarrative(raw: string): string | null {
  const t = raw.trim();
  if (!t) return null;

  const stripped = t
    .replace(/^我(昨天|今天|刚才)?(做)?(了)?(一个)?梦(，|。|梦见|里)?/u, '')
    .trim();
  const source = stripped || t;

  if (source.length >= MIN_TITLE_PHRASE_LENGTH && source.length <= MAX_TITLE_PHRASE_LENGTH) {
    return source;
  }

  if (source.length > MAX_TITLE_PHRASE_LENGTH) {
    const slice = source.slice(0, MAX_TITLE_PHRASE_LENGTH).replace(/[，,。！？!?、\s]+$/u, '');
    if (slice.length >= MIN_TITLE_PHRASE_LENGTH) return slice;
  }

  if (source.length >= MIN_TITLE_PHRASE_LENGTH) {
    return source.slice(0, MAX_TITLE_PHRASE_LENGTH);
  }

  return null;
}
