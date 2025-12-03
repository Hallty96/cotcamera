// src/index.ts
import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import express from 'express';
import { Storage } from '@google-cloud/storage';
import { ImageAnnotatorClient } from '@google-cloud/vision';
import { nanoid } from 'nanoid';
import * as crypto from 'crypto';
import { z } from 'zod';

// ---------- minimal schema ----------
const CreateSubmissionSchema = z.object({
  contentType: z.string().min(1),
  sizeBytes: z.number().int().nonnegative(),
  imageSha256: z.string().regex(/^[a-f0-9]{64}$/),
  lat: z.number().optional(),
  lng: z.number().optional(),
  takenAt: z.string().optional(), // ISO from client (optional)
});

// ---------- very simple auth middleware just for completeSubmission ----------
import { Request, Response, NextFunction } from 'express';

interface AuthedRequest extends Request {
  user?: { uid: string };
}

const authMiddleware = async (req, res, next) => {
  try {
    const m = (req.headers.authorization || '').match(/^Bearer (.+)$/i);
    if (!m) return res.status(401).json({ error: 'Missing Authorization: Bearer <idToken>' });
    const token = m[1].trim();

    console.log('auth: token length', token.length, 'prefix', token.slice(0, 20));
    const decoded = await admin.auth().verifyIdToken(token); // no 'true' here
    console.log('auth: uid', decoded.uid, 'aud', decoded.aud, 'provider', decoded.firebase?.sign_in_provider);

    (req as any).user = { uid: decoded.uid };
    next();
  } catch (e: any) {
    console.error('auth: verifyIdToken error:', e?.code, e?.message || e);
    return res.status(401).json({ error: 'Invalid or expired Firebase ID token' });
  }
};


// ---------- init ----------
admin.initializeApp();
const app = express();
app.use(express.json({ limit: '1mb' }));

const db = admin.firestore();
const storage = new Storage();
const vision = new ImageAnnotatorClient();

const DEFAULT_BUCKET = admin.storage().bucket().name;
const SIGNED_URL_TTL_SECONDS = 120;

// ---------- debug routes ----------
app.get('/ping', (_req, res) => res.status(200).send('pong'));

// ========================================================================
//  Day 4 (testing made easy): createSession is OPEN (no auth)
//  We still record expected hash/size/ct + give a signed PUT URL.
// ========================================================================
app.post('/createSubmissionSession', async (req, res) => {
  try {
    const parsed = CreateSubmissionSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'Invalid request body', details: parsed.error.issues });
    }
    const { contentType, sizeBytes, imageSha256, lat, lng, takenAt } = parsed.data;

    // Day-4 local testing: OPEN session (no owner yet)
    const uid = null; // claimed at completeSubmission

    const submissionId = nanoid();
    const nonce = crypto.randomUUID();
    // Put files under an "open" area so there's no uid dependency
    const objectName = `submissions/open/${submissionId}/original.jpg`;
    const expiresAtMs = Date.now() + SIGNED_URL_TTL_SECONDS * 1000;


    const file = storage.bucket(DEFAULT_BUCKET).file(objectName);

    const extensionHeaders: Record<string, string> = {
      'content-type': contentType,
      'x-goog-meta-image_sha256': imageSha256,
    };
    if (typeof lat === 'number') extensionHeaders['x-goog-meta-lat'] = String(lat);
    if (typeof lng === 'number') extensionHeaders['x-goog-meta-lng'] = String(lng);
    if (typeof takenAt === 'string') extensionHeaders['x-goog-meta-takenAt'] = takenAt;

    const [uploadUrl] = await file.getSignedUrl({
      version: 'v4',
      action: 'write',
      expires: expiresAtMs,
      contentType,
      extensionHeaders,
    });

    await db.collection('submissionSessions').doc(submissionId).set({
      uid: null,
      nonce,
      bucketPath: objectName,
      expiresAt: new Date(expiresAtMs),
      used: false,
      createdAt: new Date(),
      expected: { contentType, sizeBytes, imageSha256, lat: lat ?? null, lng: lng ?? null, takenAt: takenAt ?? null },
    });

    return res.status(200).json({
      submissionId,
      uploadUrl,
      nonce,
      expiresAt: new Date(expiresAtMs).toISOString(),
      bucketPath: objectName,
    });
  } catch (err: any) {
    console.error(err);
    return res.status(500).json({ error: 'Internal error', message: String(err?.message ?? err) });
  }
});

// ---------- helper: odometer extractor (simple heuristic) ----------
function extractOdometer(raw: string): { value: number | null; confidence: number } {
  // allow spaces/commas, pick largest 5–7 digit group
  const re = /(?:\b|^)(\d[\d ,]{4,10}\d)(?:\b|$)/g;
  let best: { n: number; digits: number } | null = null;

  for (const m of raw.matchAll(re)) {
    const cleaned = m[1].replace(/[ ,]/g, '');
    if (!/^\d{5,7}$/.test(cleaned)) continue;
    const n = parseInt(cleaned, 10);
    const digits = cleaned.length;
    if (!best || digits > best.digits || (digits === best.digits && n > best.n)) {
      best = { n, digits };
    }
  }

  if (!best) return { value: null, confidence: 0.0 };
  const conf = best.digits >= 6 ? 0.8 : 0.6;
  return { value: best.n, confidence: conf };
}

// ========================================================================
//  Day 4: completeSubmission  (AUTH REQUIRED)
//  - validate session (uid/nonce/expiry/used)
//  - check file & metadata (image_sha256)
//  - OCR with Cloud Vision
//  - write immutable submissions/{submissionId}
//  - mark session used
// ========================================================================
const CompleteSchema = z.object({
  submissionId: z.string().min(1),
  nonce: z.string().min(1),
});

app.post('/completeSubmission', authMiddleware, async (req: AuthedRequest, res) => {
  try {
    const parsed = CompleteSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'Invalid request body', details: parsed.error.issues });
    }
    const { submissionId, nonce } = parsed.data;
    const uid = req.user!.uid;

    // 1) Read + validate session
    const sessRef = db.collection('submissionSessions').doc(submissionId);
    const snap = await sessRef.get();
    if (!snap.exists) return res.status(404).json({ error: 'session not found' });

    const sess = snap.data() as any;
    // If the session already had an owner, it must match.
    // (Day-4: open sessions have uid === null and can be claimed at completion.)
    if (sess.uid && sess.uid !== uid) {
      return res.status(403).json({ error: 'forbidden (uid mismatch)' });
    }

    if (sess.used === true) return res.status(409).json({ error: 'session already used' });
    if (sess.nonce !== nonce) return res.status(400).json({ error: 'nonce mismatch' });

    const expiresAtMs: number = sess.expiresAt?.toMillis
      ? sess.expiresAt.toMillis()
      : (sess.expiresAt?.seconds ?? 0) * 1000;

    const now = Date.now();
    const graceMs = 5 * 60 * 1000; // allow small delay
    if (expiresAtMs < now - graceMs) return res.status(410).json({ error: 'session expired' });

    // 2) Check file + read metadata
    const objectName = sess.bucketPath as string;
    const file = storage.bucket(DEFAULT_BUCKET).file(objectName);
    const [exists] = await file.exists();
    if (!exists) return res.status(404).json({ error: 'uploaded file not found' });

    const [meta] = await file.getMetadata();
    const md = (meta.metadata || {}) as Record<string, string | undefined>;
    const imageSha256 = md.image_sha256 || md.imageSha256;
    if (!imageSha256) return res.status(400).json({ error: 'missing image_sha256 object metadata' });
    if (sess.expected?.imageSha256 && sess.expected.imageSha256 !== imageSha256) {
      return res.status(400).json({ error: 'image_sha256 mismatch' });
    }

    // 3) OCR (Vision API)
    const [result] = await vision.textDetection(`gs://${DEFAULT_BUCKET}/${objectName}`);
    const rawText = (result.fullTextAnnotation?.text || '').trim();

    // 4) Extract odometer
    const { value, confidence } = extractOdometer(rawText);

    // 5) Immutable write to submissions/{submissionId}
    const lat = md.lat ? parseFloat(md.lat) : null;
    const lng = md.lng ? parseFloat(md.lng) : null;

    const submissionDoc = {
      submissionId,
      uid,
      serverTimestamp: new Date(),
      bucketPath: objectName,
      imageSha256,
      gps: { lat, lng },
      takenAt: md.takenAt ?? null,
      ocr: {
        rawText: rawText.length > 4000 ? rawText.slice(0, 4000) : rawText,
        value,        // number or null
        confidence,   // 0..1
      },
      device: {
        platform: null,
        appVersion: null,
      },
    };

    const destRef = db.collection('submissions').doc(submissionId);
    await db.runTransaction(async (tx) => {
      const destSnap = await tx.get(destRef);
      if (destSnap.exists) throw new Error('submission already exists');

      tx.set(destRef, submissionDoc, { merge: false });
      tx.update(sessRef, {
        used: true,
        completedAt: new Date(),
        uid,
      });
    });

    return res.status(200).json({ status: 'ok' });
  } catch (err: any) {
    console.error(err);
    return res.status(500).json({ error: 'Internal error', message: String(err?.message ?? err) });
  }
});

export const api = functions
  .region('australia-southeast1')
  .runWith({ memory: '512MB', timeoutSeconds: 60 })
  .https.onRequest(app);
