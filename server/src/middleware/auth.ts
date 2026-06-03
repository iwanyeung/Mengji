import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';

export interface AuthPayload {
  userId: string;
  authProvider: 'anonymous' | 'apple';
}

declare global {
  namespace Express {
    interface Request {
      auth?: AuthPayload;
    }
  }
}

export function signToken(payload: AuthPayload): string {
  return jwt.sign(payload, env.jwtSecret, { expiresIn: '90d' });
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: '未授权' });
    return;
  }
  try {
    const token = header.slice(7);
    req.auth = jwt.verify(token, env.jwtSecret) as AuthPayload;
    next();
  } catch {
    res.status(401).json({ error: '令牌无效或已过期' });
  }
}

export function requireAppleLogin(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: '未授权' });
    return;
  }
  try {
    const token = header.slice(7);
    req.auth = jwt.verify(token, env.jwtSecret) as AuthPayload;
  } catch {
    res.status(401).json({ error: '令牌无效或已过期' });
    return;
  }
  if (req.auth.authProvider !== 'apple') {
    res.status(403).json({ error: '请先使用 Apple 登录' });
    return;
  }
  next();
}
