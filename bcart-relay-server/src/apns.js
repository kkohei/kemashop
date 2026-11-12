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

function hostFor(production) {
  return production
    ? 'https://api.push.apple.com'
    : 'https://api.sandbox.push.apple.com';
}

/**
 * 1台のデバイスへプッシュを送る。
 * まず設定環境(本番/サンドボックス)へ送り、トークンの環境違い(BadDeviceToken)なら反対環境で再試行する。
 * これで開発ビルド(サンドボックス)とTestFlight/App Storeビルド(本番)の両方に届く。
 * @returns {Promise<{ok: boolean, status: number, reason?: string, deviceToken: string}>}
 */
export async function sendPush(deviceToken, message) {
  const primary = config.apns.production;
  let res = await sendToHost(hostFor(primary), deviceToken, message);
  if (!res.ok && (res.reason === 'BadDeviceToken' || res.status === 400)) {
    res = await sendToHost(hostFor(!primary), deviceToken, message);
  }
  return res;
}

const APNS_TIMEOUT_MS = 10_000;

function sendToHost(host, deviceToken, { title, body, badge, data = {} }) {
  return new Promise((resolve) => {
    const client = http2.connect(host);
    // APNs が応答しなくても永久に待たないよう全体でタイムアウトを設ける
    const timer = setTimeout(() => {
      resolve({ ok: false, status: 0, reason: 'timeout', deviceToken });
      client.destroy();
    }, APNS_TIMEOUT_MS);
    const done = (r) => {
      clearTimeout(timer);
      resolve(r);
    };
    client.on('error', (err) => {
      done({ ok: false, status: 0, reason: err.message, deviceToken });
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

    let token;
    try {
      token = providerToken();
    } catch (err) {
      done({ ok: false, status: 0, reason: err.message, deviceToken });
      client.destroy();
      return;
    }

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${encodeURIComponent(deviceToken)}`,
      authorization: `bearer ${token}`,
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
        done({ ok: true, status, deviceToken });
      } else {
        let reason = respBody;
        try {
          reason = JSON.parse(respBody).reason || respBody;
        } catch {}
        done({ ok: false, status, reason, deviceToken });
      }
    });
    req.on('error', (err) => {
      client.close();
      done({ ok: false, status: 0, reason: err.message, deviceToken });
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
