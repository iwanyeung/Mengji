import fs from 'fs';
import { randomUUID } from 'crypto';
import { env, hasSpeechAsr } from '../config/env';

const FLASH_URL = 'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash';

export async function transcribeAudioFile(
  filePath: string,
  deviceTranscript?: string,
): Promise<string> {
  if (env.aiMock || !hasSpeechAsr()) {
    return deviceTranscript?.trim() || '（Mock ASR：未识别到语音）';
  }

  const audioBase64 = fs.readFileSync(filePath).toString('base64');
  const requestId = randomUUID();

  const res = await fetch(FLASH_URL, {
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
      audio: { data: audioBase64 },
      request: { model_name: 'bigmodel' },
    }),
  });

  if (!res.ok) {
    console.warn('ASR failed', res.status, await res.text());
    return deviceTranscript?.trim() || '';
  }

  const data = (await res.json()) as {
    result?: { text?: string };
    text?: string;
  };
  const text = data.result?.text || data.text || '';
  const cleaned = text.trim();
  if (cleaned) return cleaned;
  return deviceTranscript?.trim() || '';
}
