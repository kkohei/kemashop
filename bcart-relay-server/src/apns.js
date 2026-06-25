import http2 from 'node:http2';
import fs from 'node:fs';
import jwt from 'jsonwebtoken';
import { config } from './config.js';

// APNs はトークンベース認証(.p8 + JWT/ES256)を使う。
// プロバイダトークンは最大1時間有効なので 50 分でキャッシュを更新する。
let cachedToken = null;
let cachedAt = 0;

function providerToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedAt < 50 * 60) return cachedToken;

  const key = fs.readFileSync(config.apns.keyPath);
  cachedToken = jwt.sign({ iss: config.apns.teamId, iat: now }, key, {
    algorithm: 'ES256',
    header: { alg: 'ES256', kid: config.apns.keyId },
  });
  cachedAt = now;
  return cachedToken;
}

function apnsHost() {
  return config.apns.production
    ? 'https://api.push.apple.com'
    : 'https://api.sandbox.push.apple.com';
}

/**
 * 1台のデバイスへプッシュを送る。
 * @returns {Promise<{ok: boolean, status: number, reason?: string, deviceToken: string}>}
 */
export function sendPush(deviceToken, { title, body, badge, data = {} }) {
  return new Promise((resolve) => {
    const client = http2.connect(apnsHost());
    client.on('error', (err) => {
      resolve({ ok: false, status: 0, reason: err.message, deviceToken });
    });

    const payload = JSON.stringify({
      aps: {
        alert: { title, body },
        sound: 'default',
        ...(badge != null ? { badge } : {}),
      },
      // 通知タップ時にアプリが開くURLなど、独自データはここに入れる
      ...data,
    });

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`,
      'apns-topic': config.apns.bundleId,
      'apns-push-type': 'alert',
      'content-type': 'application/json',
    });

    let status = 0;
    let respBody = '';

    req.on('response', (headers) => {
      status = headers[':status'];
    });
    req.setEncoding('utf8');
    req.on('data', (chunk) => (respBody += chunk));
    req.on('end', () => {
      client.close();
      if (status === 200) {
        resolve({ ok: true, status, deviceToken });
      } else {
        let reason = respBody;
        try {
          reason = JSON.parse(respBody).reason || respBody;
        } catch {}
        resolve({ ok: false, status, reason, deviceToken });
      }
    });
    req.on('error', (err) => {
      client.close();
      resolve({ ok: false, status: 0, reason: err.message, deviceToken });
    });

    req.write(payload);
    req.end();
  });
}

/**
 * 複数トークンへ送信し、無効トークン(410 / BadDeviceToken など)を呼び出し元へ返す。
 */
export async function sendPushToTokens(tokens, message) {
  const results = await Promise.all(tokens.map((t) => sendPush(t, message)));
  const invalid = results
    .filter((r) => !r.ok && (r.status === 410 || r.reason === 'BadDeviceToken' || r.reason === 'Unregistered'))
    .map((r) => r.deviceToken);
  return { results, invalid };
}
