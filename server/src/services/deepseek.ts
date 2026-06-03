import OpenAI from 'openai';
import { env, hasDeepSeek } from '../config/env';

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
  tags: Array<{ name: string; category: string }>;
  keywords: string[];
  riskFlag?: boolean;
  riskMessage?: string;
}

export interface ComicPanelPrompt {
  panelIndex: number;
  caption: string;
  seedreamPrompt: string;
}

const SYSTEM_PROMPT = `你是梦悸 App 的梦境整理助手。用温柔陪伴的口吻，帮助用户整理口述梦境。
禁止医疗/心理诊断措辞（如「你患有」「你一定是」）。
若内容涉及自伤/自杀/极端绝望，设置 riskFlag 为 true，并给出简短引导寻求专业帮助。
输出必须是合法 JSON，字段：refinedNarrative, analysisText, tags（数组，每项含 name 与 category：person|place|object|emotion|theme|scene_type|other）, keywords, riskFlag, riskMessage。`;

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

export async function generateComicPanelPrompts(
  refinedNarrative: string,
  styleKey: string,
): Promise<ComicPanelPrompt[]> {
  if (env.aiMock || !env.deepseekApiKey) {
    return mockComicPrompts(refinedNarrative, styleKey);
  }

  const styleHint =
    styleKey === 'neon-surreal'
      ? '霓虹超现实拼贴风格，高饱和，梦幻'
      : '高对比黑白漫画，颗粒感，粗线条';

  const response = await getClient().chat.completions.create({
    model: env.deepseekModel,
    messages: [
      {
        role: 'system',
        content:
          '为四格梦境漫画生成分镜。输出 JSON：{ "panels": [ { "panelIndex": 1-4, "caption": "中文短句", "seedreamPrompt": "英文或中文绘画 prompt，<=500字" } ] }',
      },
      {
        role: 'user',
        content: `梦境文本：\n${refinedNarrative}\n\n视觉风格：${styleHint}\n生成 4 个连续分镜。`,
      },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.7,
  });

  const text = response.choices[0]?.message?.content || '{}';
  try {
    const parsed = JSON.parse(text) as { panels?: ComicPanelPrompt[] };
    const panels = (parsed.panels || []).slice(0, 4);
    if (panels.length >= 4) return panels;
  } catch {
    /* fallback */
  }
  return mockComicPrompts(refinedNarrative, styleKey);
}

function parseAnalysisJson(text: string, fallbackRaw: string): DreamAnalysisResult {
  try {
    const p = JSON.parse(text) as DreamAnalysisResult;
    if (p.refinedNarrative && p.analysisText) return p;
  } catch {
    /* fallback */
  }
  return mockAnalyze(fallbackRaw);
}

function mockAnalyze(raw: string): DreamAnalysisResult {
  const base = raw.trim().slice(0, 200) || '一段尚未说清的梦';
  return {
    refinedNarrative: `${base}……（梦悸已帮你整理成更连贯的叙述。）`,
    analysisText:
      '这个梦像是你心里某个角落的投影。不必急着读懂它，先温柔地陪自己待一会儿就好。',
    tags: [
      { name: '梦境', category: 'theme' },
      { name: '自我观察', category: 'emotion' },
    ],
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

function mockComicPrompts(narrative: string, styleKey: string): ComicPanelPrompt[] {
  const style =
    styleKey === 'neon-surreal' ? 'neon surreal dreamscape' : 'noir comic high contrast';
  const snippet = narrative.slice(0, 40);
  return [1, 2, 3, 4].map((i) => ({
    panelIndex: i,
    caption: `第${i}格 · ${snippet}`,
    seedreamPrompt: `${style}, dream comic panel ${i}, ${snippet}, cinematic, 2k`,
  }));
}
