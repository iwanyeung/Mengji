import crypto from 'crypto';

export function computeNarrativeHash(narrative: string): string {
  const normalized = narrative.trim().replace(/\s+/g, ' ');
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex').slice(0, 16);
}

export function isSubstantialNarrativeChange(before: string, after: string): boolean {
  const a = before.trim().replace(/\s+/g, ' ');
  const b = after.trim().replace(/\s+/g, ' ');
  if (a === b) return false;
  if (a.length === 0 || b.length === 0) return true;
  const maxLen = Math.max(a.length, b.length);
  if (maxLen < 40) return a !== b;
  let diff = 0;
  const minLen = Math.min(a.length, b.length);
  for (let i = 0; i < minLen; i++) {
    if (a[i] !== b[i]) diff++;
  }
  diff += Math.abs(a.length - b.length);
  return diff / maxLen > 0.05 || diff > 30;
}
