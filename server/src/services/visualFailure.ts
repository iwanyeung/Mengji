export type VisualFailureCode =
  | 'moderation_blocked'
  | 'service_unavailable'
  | 'partial_success'
  | 'generation_failed'
  | 'unknown_error';

const MODERATION_PATTERNS = [
  /不符合平台规则/,
  /content.?policy/i,
  /moderation/i,
  /sensitive/i,
  /审核/,
  /安全规范/,
  /inappropriate/i,
  /违规/,
  /risk/i,
  /blocked/i,
];

const SERVICE_PATTERNS = [
  /timeout/i,
  /etimedout/i,
  /econnreset/i,
  /\b502\b|\b503\b|\b504\b/,
  /network/i,
  /failed to download/i,
  /seedream error 5/i,
  /service unavailable/i,
];

export function isModerationError(raw: string | undefined | null): boolean {
  const text = raw || '';
  return MODERATION_PATTERNS.some((p) => p.test(text));
}

export function classifyVisualFailure(raw: string | undefined | null): VisualFailureCode {
  const text = raw || '';
  if (isModerationError(text)) return 'moderation_blocked';
  if (SERVICE_PATTERNS.some((p) => p.test(text))) return 'service_unavailable';
  if (text.trim()) return 'generation_failed';
  return 'unknown_error';
}

export function resolveFailureForZeroPanels(opts: {
  lastError?: string;
  hadModerationBlock?: boolean;
}): { code: VisualFailureCode; internalReason: string } {
  if (opts.hadModerationBlock || isModerationError(opts.lastError)) {
    return {
      code: 'moderation_blocked',
      internalReason: '生成服务内容规范限制',
    };
  }
  const code = classifyVisualFailure(opts.lastError);
  return {
    code,
    internalReason:
      code === 'service_unavailable'
        ? '生成服务暂时不可用'
        : '本次未能生成任何分镜，已自动重试',
  };
}

export function userMessageForFailure(code: VisualFailureCode, successfulPanelCount?: number): string {
  switch (code) {
    case 'moderation_blocked':
      return (
        '你的梦已经安全保存在梦悸里。在把梦境转成画面时，生成服务对部分内容有安全规范，这次没能通过。' +
        '这不代表你的梦「有问题」——很多梦境里的意象，适合记录与陪伴式解读，但不适合直接画出来。'
      );
    case 'service_unavailable':
      return '生成服务暂时繁忙或连接不稳定，请稍后再试。你的梦境内容不会因此丢失。';
    case 'partial_success':
      return `四格还未完整落成（已完成 ${successfulPanelCount ?? 0}/4 格）。剩余分镜未能继续生成，本次额度已使用。`;
    case 'generation_failed':
      return '这次还未能把梦落成四格。你可以稍后再试，或换一种画面风格。';
    case 'unknown_error':
    default:
      return '这次还未能把梦落成四格。请稍后再试。';
  }
}
