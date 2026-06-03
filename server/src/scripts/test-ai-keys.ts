/**
 * 一次性连通性测试：DeepSeek / 火山方舟 Seedream / 豆包语音 ASR
 * 用法: npx ts-node src/scripts/test-ai-keys.ts
 */
import dotenv from 'dotenv';
dotenv.config();

import { analyzeDream } from '../services/deepseek';
import { env } from '../config/env';

async function testDeepSeek(): Promise<boolean> {
  console.log('\n--- DeepSeek 梦析 ---');
  try {
    const result = await analyzeDream('我梦见自己在一片发光的森林里奔跑，脚下是柔软的金色苔藓。');
    const isMock =
      result.refinedNarrative.includes('梦悸已帮你整理成更连贯的叙述') ||
      result.analysisText.includes('这个梦像是你心里某个角落的投影');
    if (isMock) {
      console.log('❌ 返回 Mock 数据，可能 Key 未生效');
      return false;
    }
    console.log('✅ 成功');
    console.log('  整理:', result.refinedNarrative.slice(0, 80) + '…');
    console.log('  标签:', result.tags.map((t) => t.name).join(', '));
    return true;
  } catch (err) {
    console.log('❌ 失败:', err instanceof Error ? err.message : err);
    return false;
  }
}

async function testSeedream(): Promise<boolean> {
  console.log('\n--- 火山方舟 Seedream 文生图 ---');
  if (!env.arkApiKey) {
    console.log('⏭ 跳过：未配置 ARK_API_KEY');
    return false;
  }
  try {
    const res = await fetch(`${env.arkBaseUrl}/images/generations`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.arkApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: env.arkImageModel,
        prompt: 'dreamy surreal forest, soft golden light, test panel',
        size: '2K',
        n: 1,
        response_format: 'url',
      }),
    });
    const text = await res.text();
    if (!res.ok) {
      console.log(`❌ HTTP ${res.status}:`, text.slice(0, 300));
      return false;
    }
    const data = JSON.parse(text) as { data?: Array<{ url?: string }> };
    const url = data.data?.[0]?.url;
    if (url) {
      console.log('✅ 成功，图片 URL:', url.slice(0, 80) + '…');
      return true;
    }
    console.log('❌ 响应无图片 URL:', text.slice(0, 200));
    return false;
  } catch (err) {
    console.log('❌ 失败:', err instanceof Error ? err.message : err);
    return false;
  }
}

async function testSpeechAsr(): Promise<boolean> {
  console.log('\n--- 豆包语音 ASR ---');
  if (!env.speechAppKey || !env.speechAccessKey) {
    console.log('⏭ 跳过：未配置 SPEECH_APP_KEY / SPEECH_ACCESS_KEY');
    return false;
  }
  // 最小有效 WAV（静音 0.1s）用于探测鉴权是否通过
  const wavHeader = Buffer.from([
    0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20,
    0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x44, 0xac, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00,
    0x02, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 0x00, 0x00, 0x00, 0x00,
  ]);
  const { randomUUID } = await import('crypto');
  const requestId = randomUUID();
  try {
    const res = await fetch(
      'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Api-App-Key': env.speechAppKey,
          'X-Api-Access-Key': env.speechAccessKey,
          'X-Api-Resource-Id': 'volc.bigasr.auc_turbo',
          'X-Api-Request-Id': requestId,
          'X-Api-Sequence': '-1',
        },
        body: JSON.stringify({
          user: { uid: env.speechAppKey },
          audio: { data: wavHeader.toString('base64') },
          request: { model_name: 'bigmodel' },
        }),
      },
    );
    const text = await res.text();
    if (res.status === 401 || res.status === 403) {
      console.log(`❌ 鉴权失败 HTTP ${res.status}:`, text.slice(0, 300));
      console.log(
        '   提示：豆包语音通常需要控制台「App Key」+「Access Token」，而非 IAM 的 Access Key ID/Secret。',
      );
      return false;
    }
    if (!res.ok) {
      console.log(`⚠️ HTTP ${res.status}（可能因测试音频无效，但鉴权已通过）:`, text.slice(0, 200));
      return res.status !== 401 && res.status !== 403;
    }
    console.log('✅ 请求成功:', text.slice(0, 200));
    return true;
  } catch (err) {
    console.log('❌ 失败:', err instanceof Error ? err.message : err);
    return false;
  }
}

async function main(): Promise<void> {
  console.log('梦悸 AI 连通性测试');
  console.log('AI_MOCK =', env.aiMock);
  console.log('DEEPSEEK_API_KEY =', env.deepseekApiKey ? `${env.deepseekApiKey.slice(0, 8)}…` : '(空)');
  console.log('ARK_API_KEY =', env.arkApiKey ? `${env.arkApiKey.slice(0, 12)}…` : '(空)');
  console.log('SPEECH_APP_KEY =', env.speechAppKey ? `${env.speechAppKey.slice(0, 8)}…` : '(空)');

  const results = {
    deepseek: await testDeepSeek(),
    seedream: await testSeedream(),
    speech: await testSpeechAsr(),
  };

  console.log('\n========== 汇总 ==========');
  console.log('DeepSeek 梦析:', results.deepseek ? '✅' : '❌');
  console.log('Seedream 文生图:', results.seedream ? '✅' : '❌');
  console.log('豆包语音 ASR:', results.speech ? '✅' : '❌');

  const ok = Object.values(results).filter(Boolean).length;
  console.log(`\n${ok}/3 项通过`);
  process.exit(ok === 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
