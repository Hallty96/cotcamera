import * as admin from 'firebase-admin';
import { Request, Response, NextFunction } from 'express';

export interface AuthedRequest extends Request {
  user?: { uid: string };
}

export const authMiddleware = async (req: AuthedRequest, res: Response, next: NextFunction) => {
  const hdr = req.headers.authorization || '';
  const m = hdr.match(/^Bearer (.+)$/i);
  if (!m) return res.status(401).json({ error: 'Missing Authorization: Bearer <token>' });

  try {
    const decoded = await admin.auth().verifyIdToken(m[1], true);
    req.user = { uid: decoded.uid };
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired Firebase ID token' });
  }
};
