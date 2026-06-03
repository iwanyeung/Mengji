const HIGH_RISK_PATTERNS = [/自杀/, /自残/, /不想活/, /结束生命/, /伤害自己/];

export function scanTranscriptRisk(text: string): { riskFlag: boolean; message?: string } {
  for (const pattern of HIGH_RISK_PATTERNS) {
    if (pattern.test(text)) {
      return {
        riskFlag: true,
        message:
          '我们注意到你的梦境内容可能涉及较高强度的情绪。梦悸不能替代专业帮助；若你感到持续困扰，请考虑联系当地心理援助热线或专业机构。',
      };
    }
  }
  return { riskFlag: false };
}

export function appendRiskNotice(analysisText: string, riskMessage?: string): string {
  if (!riskMessage) return analysisText;
  return `${analysisText}\n\n——\n${riskMessage}`;
}
