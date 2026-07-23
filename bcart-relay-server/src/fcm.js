import fs from 'node:fs';
import jwt from 'jsonwebtoken';
import { config } from './config.js';

// FCM HTTP v1 API で Android 端末へプッシュを送る。
// Firebase コンソールで発行したサービスアカウント鍵(JSON)を使い、
// OAuth2 アクセストークンを取得して messages:send を呼ぶ。

let sa = null;
function serviceAccount() {
  if (sa) return sa;
  const p = config.fcm.serviceAccountPath;
  if (!p || !fs.existsSync(p)) return null;
  sa = JSON.parse(fs.readFileSync(p, 'utf8'));
  return sa;
}

export function fcmConfigured() {
  return !!serviceAccount();
}

let cachedToken = null;
let cachedExp = 0;

async function accessToken() {
  const acct = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now < cachedExp - 300) return cachedToken;

  const assertion = jwt.sign(
    {
      iss: acct.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    acct.private_key,
    { algorithm: 'RS256' }
  );

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const j = await res.json();
  if (!j.access_token) throw new Error('FCMアクセストークン取得失敗: ' + JSON.stringify(j).slice(0, 200));
  cachedToken = j.access_token;
  cachedExp = now + (j.expires_in || 3600);
  return cachedToken;
}

/**
 * 複数のAndroid端末トークンへ送信。無効トークンは invalid で返す。
 */
export async function sendFcmToTokens(tokens, { title, body, data = {} }) {
  const results = [];
  const invalid = [];

  if (!fcmConfigured()) {
    console.warn('[fcm] FCM_SERVICE_ACCOUNT_PATH 未設定のためAndroid送信をスキップ');
    return {
      results: tokens.map((t) => ({ ok: false, status: 0, reason: 'fcm-not-configured', deviceToken: t })),
      invalid,
    };
  }

  const at = await accessToken();
  const project = serviceAccount().project_id;

  await Promise.all(
    tokens.map(async (t) => {
      try {
        const res = await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
          method: 'POST',
          headers: { authorization: `Bearer ${at}`, 'content-type': 'application/json' },
          body: JSON.stringify({
            message: {
              token: t,
              notification: { title, body },
              data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
              android: { notification: { channel_id: 'default' } },
            },
          }),
        });
        if (res.ok) {
          results.push({ ok: true, status: res.status, deviceToken: t });
        } else {
          const txt = await res.text();
          results.push({ ok: false, status: res.status, reason: txt.slice(0, 200), deviceToken: t });
          if (res.status === 404 || /UNREGISTERED/.test(txt)) invalid.push(t);
        }
      } catch (e) {
        results.push({ ok: false, status: 0, reason: e.message, deviceToken: t });
      }
    })
  );

  return { results, invalid };
}
