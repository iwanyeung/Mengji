import OpenAI from 'openai';
import { env, hasDeepSeek } from '../config/env';
import { deriveTitlePhrase, resolveTitlePhrase } from '../utils/dreamTitle';

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    client = new OpenAI({
      apiKey: env.deepseekApiKey || 'mock',
      baseURL: 'https://api.deepseek.com',
    });
  }
  return client;
}

export interface DreamAnalysisResult {
  refinedNarrative: string;
  analysisText: string;
  /** 4–12 字意象短语，用于「关于「…」的夜里」标题 */
  titlePhrase: string;
  tags: Array<{ name: string; category: string }>;
  keywords: string[];
  riskFlag?: boolean;
  riskMessage?: string;
}

export type ComicPanelSource = 'verbatim' | 'atmosphere' | 'inferred';

export interface ComicPanelPrompt {
  panelIndex: number;
  caption: string;
  seedreamPrompt: string;
  source?: ComicPanelSource;
}

export interface ComicStoryboardInput {
  refinedNarrative: string;
  rawTranscript: string;
  tags: Array<{ name: string; category: string }>;
  mode: 'imagery' | 'narrative';
}

const SYSTEM_PROMPT = `你是梦悸 App 的梦境整理助手。用温柔陪伴的口吻，帮助用户整理口述梦境。
禁止医疗/心理诊断措辞（如「你患有」「你一定是」）。
若内容涉及自伤/自杀/极端绝望，设置 riskFlag 为 true，并给出简短引导寻求专业帮助。
输出必须是合法 JSON，包含以下字段：
- refinedNarrative: 整理后的梦境正文
- analysisText: 温柔陪伴式解读
- titlePhrase: 4–12 字中文意象短语（必填，禁止少于 4 字；不要直接截取正文开头；示例：「听不见的名字」「忽明忽暗的城市」「找不到的火车站」）
- tags: 数组，每项含 name 与 category（person|place|object|emotion|theme|scene_type|other）
- keywords, riskFlag, riskMessage

示例 JSON 片段：
{"titlePhrase":"忽明忽暗的城市","refinedNarrative":"…","analysisText":"…","tags":[{"name":"城市","category":"place"}],"keywords":[],"riskFlag":false,"riskMessage":null}`;

export async function analyzeDream(rawTranscript: string): Promise<DreamAnalysisResult> {
  if (env.aiMock || !env.deepseekApiKey) {
    return mockAnalyze(rawTranscript);
  }
  if (!hasDeepSeek()) {
    return mockAnalyze(rawTranscript);
  }

  const response = await getClient().chat.completions.create({
    model: env.deepseekModel,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      {
        role: 'user',
        content: `请整理以下梦境口述转写，保持忠实原意：\n\n${rawTranscript}`,
      },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.6,
  });

  const text = response.choices[0]?.message?.content || '{}';
  return parseAnalysisJson(text, rawTranscript);
}

const COMIC_STORYBOARD_SYSTEM = `你是梦悸 App 的四格梦境分镜助手。必须忠实用户已记录的梦境，禁止编造用户未提及的角色、地点、情节转折。

忠实度规则：
1. 只能使用「梦境原文」「整理正文」「标签/关键词」中已出现的人、地、物、动作与情绪。
2. 禁止新增剧情转折、新角色、新地点；不得把梦写成完整小说。
3. 每格标注 source：
   - verbatim：直接来自用户梦境的明确场景
   - atmosphere：同一意象的光影/远近/氛围延伸（不新增实体）
   - inferred：仅当信息略不足时用于过渡，全梦最多 1 格（叙事模式最多 2 格）
4. 若素材不足：优先用「意象四格」——同一核心意象的不同镜头（特写/全景/倒影/消散），不要编新故事。
5. caption 用中文短句，seedreamPrompt 为绘画 prompt（<=500字），需点明 16:9 横版全幅、单一场景、无边框无文字、无对话气泡。
6. 每一格都是独立 16:9 横版整幅电影感画面，不要分镜格线/多格拼贴。

输出 JSON：
{ "panels": [ { "panelIndex": 1-4, "caption": "...", "seedreamPrompt": "...", "source": "verbatim|atmosphere|inferred" } ] }`;

export async function generateComicPanelPrompts(
  input: ComicStoryboardInput,
  styleKey: string,
): Promise<ComicPanelPrompt[]> {
  if (env.aiMock || !env.deepseekApiKey) {
    return mockComicPrompts(input, styleKey);
  }

  const styleHint =
    styleKey === 'neon-surreal'
      ? '霓虹超现实拼贴风格，高饱和，梦幻'
      : '高对比黑白漫画，颗粒感，粗线条';

  const tagLine =
    input.tags.length > 0
      ? input.tags.map((t) => `${t.name}(${t.category})`).join('、')
      : '（无标签）';

  const modeHint =
    input.mode === 'imagery'
      ? '本次为「意象四格」模式：围绕用户梦中最核心的 1–2 个意象，用 4 个不同镜头表现，不要编造新剧情。'
      : '本次为「叙事四格」模式：在用户已有情节基础上做起承转合，不得添加原文没有的事件。';

  const response = await getClient().chat.completions.create({
    model: env.deepseekModel,
    messages: [
      { role: 'system', content: COMIC_STORYBOARD_SYSTEM },
      {
        role: 'user',
        content:
          `${modeHint}\n\n` +
          `梦境整理正文：\n${input.refinedNarrative}\n\n` +
          `梦境口述原文：\n${input.rawTranscript || input.refinedNarrative}\n\n` +
          `意象标签：${tagLine}\n\n` +
          `视觉风格：${styleHint}\n` +
          `生成 4 个分镜，每格为独立 16:9 横版全幅单场景画面。`,
      },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.4,
  });

  const text = response.choices[0]?.message?.content || '{}';
  try {
    const parsed = JSON.parse(text) as { panels?: ComicPanelPrompt[] };
    const panels = (parsed.panels || []).slice(0, 4);
    if (panels.length >= 4) return panels;
  } catch {
    /* fallback */
  }
  return mockComicPrompts(input, styleKey);
}

function parseAnalysisJson(text: string, fallbackRaw: string): DreamAnalysisResult {
  try {
    const p = JSON.parse(text) as DreamAnalysisResult;
    if (p.refinedNarrative && p.analysisText) {
      return {
        ...p,
        titlePhrase: resolveTitlePhrase(fallbackRaw, p.tags, p.titlePhrase),
      };
    }
  } catch {
    /* fallback */
  }
  return mockAnalyze(fallbackRaw);
}

function mockAnalyze(raw: string): DreamAnalysisResult {
  const base = raw.trim().slice(0, 200) || '一段尚未说清的梦';
  const tags = [
    { name: '梦境', category: 'theme' },
    { name: '自我观察', category: 'emotion' },
  ];
  return {
    refinedNarrative: `${base}……（梦悸已帮你整理成更连贯的叙述。）`,
    analysisText:
      '这个梦像是你心里某个角落的投影。不必急着读懂它，先温柔地陪自己待一会儿就好。',
    titlePhrase: deriveTitlePhrase(raw, tags),
    tags,
    keywords: ['梦', '夜'],
    riskFlag: false,
  };
}

export type ReinterpretMode = 'default' | 'gentler';

export interface ReinterpretResult {
  analysisText: string;
  riskFlag?: boolean;
  riskMessage?: string;
}

const REINTERPRET_SYSTEM = `你是梦悸 App 的梦境陪伴解读助手。用户已自行修订梦境整理正文，请仅基于该正文写温柔陪伴式解读。
禁止医疗/心理诊断措辞（如「你患有」「你一定是」）。不要改写或重复输出用户正文。
输出合法 JSON：{ "analysisText": "...", "riskFlag": false, "riskMessage": null }`;

export async function reinterpretDream(
  refinedNarrative: string,
  mode: ReinterpretMode = 'default',
  feedbackNote?: string,
): Promise<ReinterpretResult> {
  if (env.aiMock || !env.deepseekApiKey) {
    return mockReinterpret(refinedNarrative, mode);
  }

  const gentler =
    mode === 'gentler'
      ? '\n请用更轻柔的语气：更短句、少隐喻、避免第二人称评判、不展开可能刺激的细节。'
      : '';
  const note = feedbackNote?.trim() ? `\n用户补充：${feedbackNote.trim()}` : '';

  const response = await getClient().chat.completions.create({
    model: env.deepseekModel,
    messages: [
      { role: 'system', content: REINTERPRET_SYSTEM + gentler },
      {
        role: 'user',
        content: `梦境整理正文：\n${refinedNarrative}${note}`,
      },
    ],
    response_format: { type: 'json_object' },
    temperature: mode === 'gentler' ? 0.5 : 0.6,
  });

  const text = response.choices[0]?.message?.content || '{}';
  try {
    const p = JSON.parse(text) as ReinterpretResult;
    if (p.analysisText) return p;
  } catch {
    /* fallback */
  }
  return mockReinterpret(refinedNarrative, mode);
}

function mockReinterpret(narrative: string, mode: ReinterpretMode): ReinterpretResult {
  const snippet = narrative.trim().slice(0, 60) || '这段梦';
  const base =
    mode === 'gentler'
      ? `关于「${snippet}」……你不必立刻读懂它。可以先允许自己停在这里，感受一下身体是否比刚才松一点。`
      : `从「${snippet}」出发，这个梦像是在陪你看见一些尚未说清的情绪。不必急着下结论，温柔地陪自己待一会儿就好。`;
  return { analysisText: base, riskFlag: false };
}

function mockComicPrompts(input: ComicStoryboardInput, styleKey: string): ComicPanelPrompt[] {
  const style =
    styleKey === 'neon-surreal' ? 'neon surreal dreamscape' : 'noir comic high contrast';
  const snippet = (input.refinedNarrative || input.rawTranscript).slice(0, 40);
  const sources: ComicPanelSource[] =
    input.mode === 'imagery'
      ? ['verbatim', 'atmosphere', 'atmosphere', 'atmosphere']
      : ['verbatim', 'atmosphere', 'atmosphere', 'inferred'];
  return [1, 2, 3, 4].map((i) => ({
    panelIndex: i,
    caption: `第${i}格 · ${snippet}`,
    seedreamPrompt: `${style}, single full-frame cinematic scene, 16:9 horizontal composition, dream comic panel ${i}, ${snippet}, no panel borders, no grid, no text, subject centered with safe margins`,
    source: sources[i - 1],
  }));
}
