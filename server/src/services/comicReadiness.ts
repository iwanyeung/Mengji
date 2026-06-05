export type ComicReadinessLevel = 'sparse' | 'moderate' | 'rich';
export type ComicStoryboardMode = 'imagery' | 'narrative';

const CONCRETE_TAG_CATEGORIES = new Set(['person', 'place', 'object', 'scene_type']);

export interface ComicReadinessInput {
  segmentCount: number;
  narrativeCharCount: number;
  rawCharCount: number;
  tags: Array<{ name: string; category: string }>;
}

export interface ComicReadinessResult {
  level: ComicReadinessLevel;
  score: number;
  segmentCount: number;
  narrativeCharCount: number;
  concreteImageryCount: number;
  suggestedMode: ComicStoryboardMode;
  userHint: string;
  ctaHint: string;
}

function countConcreteImagery(tags: Array<{ name: string; category: string }>): number {
  const seen = new Set<string>();
  for (const tag of tags) {
    if (!CONCRETE_TAG_CATEGORIES.has(tag.category)) continue;
    const name = tag.name.trim();
    if (name) seen.add(name);
  }
  return seen.size;
}

export function computeComicReadiness(input: ComicReadinessInput): ComicReadinessResult {
  const narrativeChars = Math.max(input.narrativeCharCount, input.rawCharCount);
  const segmentCount = input.segmentCount;
  const concreteImageryCount = countConcreteImagery(input.tags);

  let score = 0;
  score += Math.min(segmentCount, 4) * 18;
  score += Math.min(Math.floor(narrativeChars / 20), 8) * 5;
  score += Math.min(concreteImageryCount, 4) * 12;

  let level: ComicReadinessLevel;
  if (
    segmentCount >= 3 ||
    (narrativeChars >= 120 && concreteImageryCount >= 2)
  ) {
    level = 'rich';
  } else if (narrativeChars >= 40 || concreteImageryCount >= 1 || segmentCount >= 2) {
    level = 'moderate';
  } else {
    level = 'sparse';
  }

  const suggestedMode: ComicStoryboardMode = level === 'sparse' || level === 'moderate' ? 'imagery' : 'narrative';

  const userHint =
    level === 'rich'
      ? '你的梦画面感很足，很适合落成连续四格。'
      : level === 'moderate'
        ? '内容偏短，漫画会更偏意象延伸，可能和你记得的细节不完全一样。'
        : '记录还比较少，落成时 AI 会较多用氛围画面补全；补录一两句具体画面会更像你梦里的样子。';

  const ctaHint =
    level === 'rich'
      ? '让这条梦落成四格故事'
      : level === 'moderate'
        ? '落成四格（偏意象化）'
        : '仍要尝试落成四格';

  return {
    level,
    score: Math.min(100, score),
    segmentCount,
    narrativeCharCount: narrativeChars,
    concreteImageryCount,
    suggestedMode,
    userHint,
    ctaHint,
  };
}

export function isCompensationEligible(
  readinessLevel: ComicReadinessLevel,
  feedback: 'too_invented' | 'not_mine',
): boolean {
  return feedback === 'not_mine' || (feedback === 'too_invented' && readinessLevel !== 'rich');
}
