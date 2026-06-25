import express from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { store } from './db.js';
import { sendPushToTokens } from './apns.js';
import { fetchOrder, extractOrderInfo } from './bcart.js';

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
// TODO(フェーズ0): 署名対象文字列の正確な仕様を公式ドキュメントで確認する。
//   ここでは Stripe 型 `${date}.${rawBody}` を HMAC-SHA256 する想定で仮実装。
//   実仕様が判明したら makeSigningString を差し替える。
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
    const eventType = event.event_type || event.event || event.type || 'unknown';
    // 冪等キー(Bカートは idempotency_key を付与する)
    const eventKey = event.idempotency_key || event.event_id || `${eventType}:${event?.data?.object?.id}`;

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
// TODO(フェーズ0): event_type の実値(受注の新規/更新を表す文字列)をキャプチャで確認し、
//   下の startsWith 判定を実値に合わせて確定する。
async function handleEvent(eventType, event) {
  const objectId = event?.data?.object?.id;

  // 受注関連イベント
  if (/order|受注/i.test(eventType)) {
    // Webhookは object.id のみ通知 → APIで詳細(会員ID・出荷ステータス)を取得
    const order = await fetchOrder(objectId);
    const { memberId, shippingStatus } = extractOrderInfo(order);

    // 出荷ステータスが「未発送」以外になった = 出荷完了とみなす(値はフェーズ0で確定)
    const isShipped = shippingStatus && shippingStatus !== '未発送';
    const isNew = /created|new|新規/i.test(eventType);

    let message = null;
    if (isShipped) {
      message = { title: '出荷しました', body: 'ご注文の商品を発送しました。', data: { url: '/order/history' } };
    } else if (isNew) {
      message = { title: 'ご注文を承りました', body: 'ご注文ありがとうございます。', data: { url: '/order/history' } };
    }

    await pushToMember(memberId, message, eventType);
    return;
  }

  console.log('[webhook] 通知対象外のイベント:', eventType);
}

async function pushToMember(memberId, message, eventType) {
  if (!memberId || !message) {
    console.log('[webhook] 送信なし type=', eventType, 'member=', memberId);
    return;
  }
  const tokens = store.tokensForMember(memberId);
  if (tokens.length === 0) {
    console.log('[webhook] 端末未登録 member=', memberId);
    return;
  }
  const { invalid } = await sendPushToTokens(tokens, message);
  invalid.forEach((t) => store.removeToken(t));
  console.log(`[webhook] 送信 type=${eventType} member=${memberId} 端末=${tokens.length}`);
}

app.listen(config.port, () => {
  console.log(`Bカート中継サーバー起動: http://localhost:${config.port}`);
  console.log(`APNs: ${config.apns.production ? '本番' : 'サンドボックス'} / topic=${config.apns.bundleId}`);
  console.log(`Webhook検証: strict=${config.webhook.strict} / capture=${config.webhook.capture}`);
});
