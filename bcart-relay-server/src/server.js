import express from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { store } from './db.js';
import { sendPushToTokens } from './apns.js';
// bcart.js(受注API取得)は再入荷ポーリング等の将来拡張用。
// 受注イベントの会員ID・出荷状況は Webhook ボディに含まれるため、ここでは未使用。

const app = express();

// HMAC検証のため生ボディを保持しつつ JSON もパースする
app.use(
  express.json({
    limit: '1mb',
    verify: (req, _res, buf) => {
      req.rawBody = buf.toString('utf8');
    },
  })
);

// ---- ヘルスチェック ----
app.get('/healthz', (_req, res) => res.json({ ok: true }));

// ---- デバイス登録 ----
// iOSアプリがログイン成功時に呼ぶ: { memberId, deviceToken, platform }
app.post('/devices/register', (req, res) => {
  const { memberId, deviceToken, platform } = req.body || {};
  if (!memberId || !deviceToken) {
    return res.status(400).json({ ok: false, error: 'memberId と deviceToken は必須です' });
  }
  store.registerDevice({ memberId, deviceToken, platform });
  res.json({ ok: true });
});

// ---- 管理画面(一斉配信) ----
const adminHtml = fs.readFileSync(new URL('./admin.html', import.meta.url), 'utf8');

function safeEqual(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
}

function requireAdmin(req, res, next) {
  if (!config.adminSecret) {
    return res.status(503).json({ ok: false, error: 'ADMIN_SECRET が未設定です(.env を確認)' });
  }
  if (!safeEqual(req.get('X-Admin-Token') || '', config.adminSecret)) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }
  next();
}

app.get('/admin', (_req, res) => res.type('html').send(adminHtml));

app.get('/admin/stats', requireAdmin, (_req, res) => {
  res.json({
    ok: true,
    devices: store.deviceCount(),
    pendingDeletions: store.pendingDeletionCount(),
    broadcasts: store.listBroadcasts(),
    deletionRequests: store.listDeletionRequests(),
  });
});

// 退会申請を「対応済み」にする(Bカート管理画面で会員削除を終えた後に押す)
app.post('/admin/deletion-handled', requireAdmin, (req, res) => {
  const { id } = req.body || {};
  if (!id) return res.status(400).json({ ok: false, error: 'id は必須です' });
  store.markDeletionHandled(id);
  res.json({ ok: true });
});

// 全端末への一斉配信
app.post('/admin/broadcast', requireAdmin, async (req, res) => {
  const { title, body } = req.body || {};
  if (!title || !body) {
    return res.status(400).json({ ok: false, error: 'title と body は必須です' });
  }
  const tokens = store.allTokens();
  if (tokens.length === 0) {
    return res.json({ ok: true, sent: 0, failed: 0, removed: 0 });
  }
  const { results, invalid } = await sendPushToTokens(tokens, { title, body, data: { url: '/' } });
  invalid.forEach((t) => store.removeToken(t));
  const sent = results.filter((r) => r.ok).length;
  store.addBroadcast({ title, body, sentCount: sent });
  console.log(`[broadcast] "${title}" 送信=${sent} 失敗=${results.length - sent} 無効削除=${invalid.length}`);
  res.json({ ok: true, sent, failed: results.length - sent, removed: invalid.length });
});

// ---- 退会(アカウント削除)申請 ----
// アプリの「退会申請」ボタンから呼ばれる。管理者が管理画面で実際に削除する運用。
app.post('/account/deletion-request', (req, res) => {
  const { memberId, deviceToken } = req.body || {};
  store.addDeletionRequest({ memberId, deviceToken });
  console.log('[deletion] 退会申請 member=', memberId || '(不明)');
  res.json({ ok: true });
});

// ---- 手動テスト送信 ----
app.post('/push/test', async (req, res) => {
  const { memberId, title = 'テスト通知', body = 'これはテストです' } = req.body || {};
  const tokens = store.tokensForMember(memberId);
  if (tokens.length === 0) {
    return res.status(404).json({ ok: false, error: 'この会員の端末が登録されていません' });
  }
  const { results, invalid } = await sendPushToTokens(tokens, { title, body });
  invalid.forEach((t) => store.removeToken(t));
  res.json({ ok: true, sent: tokens.length, results, removed: invalid.length });
});

// ---- Webhook 署名検証 ----
// Bカートは `Bcart-Signature: date=...,v1=<hex>` ヘッダーを付与する。
// 公式仕様(確定): date の値と Webhookボディを `.` で連結した文字列を、
// 管理画面で登録した Secret をキーに HMAC-SHA256 した hex 値が v1 と一致すれば正当。
function makeSigningString(date, rawBody) {
  return `${date}.${rawBody}`;
}

function verifyWebhook(req) {
  // 1) 署名シークレットがあれば Bcart-Signature を検証
  if (config.webhook.signingSecret) {
    const header = req.get('Bcart-Signature');
    if (!header) return { ok: false, reason: 'no-signature' };
    const parts = Object.fromEntries(
      header.split(',').map((kv) => {
        const i = kv.indexOf('=');
        return [kv.slice(0, i).trim(), kv.slice(i + 1).trim()];
      })
    );
    const expected = crypto
      .createHmac('sha256', config.webhook.signingSecret)
      .update(makeSigningString(parts.date, req.rawBody || ''))
      .digest('hex');
    const v1 = parts.v1 || '';
    const ok =
      v1.length === expected.length &&
      crypto.timingSafeEqual(Buffer.from(v1), Buffer.from(expected));
    return { ok, reason: ok ? 'signature-ok' : 'signature-mismatch' };
  }
  // 2) フォールバック: 共有シークレット
  if (config.webhook.sharedSecret) {
    const token = req.query.token || req.get('X-Relay-Token');
    return { ok: token === config.webhook.sharedSecret, reason: 'shared-secret' };
  }
  return { ok: true, reason: 'no-verification-configured' };
}

// フェーズ0調査用: 受信内容をファイルに追記
function captureWebhook(req) {
  if (!config.webhook.capture) return;
  try {
    const dir = path.resolve('data');
    fs.mkdirSync(dir, { recursive: true });
    const record = {
      at: new Date().toISOString(),
      signature: req.get('Bcart-Signature') || null,
      body: req.body,
    };
    fs.appendFileSync(path.join(dir, 'webhook-capture.log'), JSON.stringify(record) + '\n');
  } catch (err) {
    console.error('[capture] 失敗', err.message);
  }
}

// ---- Bカート Webhook 受信 ----
app.post('/webhook/bcart', async (req, res) => {
  const verdict = verifyWebhook(req);
  captureWebhook(req);

  if (!verdict.ok) {
    console.warn('[webhook] 検証NG:', verdict.reason, config.webhook.strict ? '(拒否)' : '(継続: strict=false)');
    if (config.webhook.strict) return res.status(401).json({ ok: false, error: verdict.reason });
  }

  // 配信保証がないため、まず即時 200 を返してから処理する
  res.json({ ok: true });

  try {
    const event = req.body || {};
    const eventType = event.event_type || 'unknown';
    // 冪等キー: Bカートの idempotency_key は null のことがあるため event_id(UUID)を優先
    const eventKey = event.event_id || event.idempotency_key || `${eventType}:${event?.data?.object?.id}`;

    if (store.isDuplicateEvent(eventKey)) {
      console.log('[webhook] 重複スキップ:', eventKey);
      return;
    }

    await handleEvent(eventType, event);
  } catch (err) {
    console.error('[webhook] 処理エラー:', err);
  }
});

// イベント種別ごとの処理。
// Bカートの実ペイロード(確定)に基づく:
//   - event_type: 'order.created' / 'order.updated'
//   - 会員ID:   data.object.customer_id
//   - 出荷状況: data.object.logistics[].status === '発送済'
//   - 受注番号: data.object.code
async function handleEvent(eventType, event) {
  const order = event?.data?.object;
  if (!order) return;

  if (eventType === 'order.created' || eventType === 'order.updated') {
    // 端末は customer_id でも email でも登録され得るため、両方のキーで照合する
    const keys = [order.customer_id, order.customer_email].filter(Boolean);
    const shipped =
      Array.isArray(order.logistics) && order.logistics.some((l) => l.status === '発送済');

    let message = null;
    if (eventType === 'order.created') {
      message = {
        title: 'ご注文を承りました',
        body: 'ご注文ありがとうございます。内容をご確認ください。',
        data: { url: '/mypage.php', orderId: order.id },
      };
    } else if (shipped && !store.isDuplicateEvent(`shipped:${order.id}`)) {
      // order.updated は編集の度に飛ぶため、出荷通知は1受注につき1回だけ送る
      message = {
        title: '出荷しました',
        body: `ご注文(No.${order.code})を発送しました。`,
        data: { url: '/mypage.php', orderId: order.id },
      };
    }

    await pushToKeys(keys, message, eventType);
    return;
  }

  // 会員・配送先イベント等は現状通知対象外(必要になれば追加)
  console.log('[webhook] 通知対象外のイベント:', eventType);
}

// 複数キー(customer_id / email)に紐づく端末トークンを重複なく集める
function tokensForKeys(keys) {
  const set = new Set();
  for (const k of keys) {
    for (const t of store.tokensForMember(String(k))) set.add(t);
  }
  return [...set];
}

async function pushToKeys(keys, message, eventType) {
  if (!keys.length || !message) {
    console.log('[webhook] 送信なし type=', eventType, 'keys=', keys);
    return;
  }
  const tokens = tokensForKeys(keys);
  if (tokens.length === 0) {
    console.log('[webhook] 端末未登録 keys=', keys);
    return;
  }
  const { invalid } = await sendPushToTokens(tokens, message);
  invalid.forEach((t) => store.removeToken(t));
  console.log(`[webhook] 送信 type=${eventType} keys=${keys.join(',')} 端末=${tokens.length}`);
}

app.listen(config.port, () => {
  console.log(`Bカート中継サーバー起動: http://localhost:${config.port}`);
  console.log(`APNs: ${config.apns.production ? '本番' : 'サンドボックス'} / topic=${config.apns.bundleId}`);
  console.log(`Webhook検証: strict=${config.webhook.strict} / capture=${config.webhook.capture}`);
});
