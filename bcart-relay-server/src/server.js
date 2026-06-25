import express from 'express';
import { config } from './config.js';
import { store } from './db.js';
import { sendPushToTokens } from './apns.js';

const app = express();
app.use(express.json({ limit: '1mb' }));

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
// PoC確認用: { memberId, title, body }
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

// ---- Bカート Webhook 受信 ----
// Bカートの管理画面で、このURL(?token=共有シークレット)を登録する。
function verifyWebhook(req) {
  const token = req.query.token || req.get('X-Relay-Token');
  return token && token === config.webhookSecret;
}

app.post('/webhook/bcart', async (req, res) => {
  if (!verifyWebhook(req)) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }

  // Bカートは配信を保証しないため、まず即時 200 を返して取りこぼしを減らす
  res.json({ ok: true });

  try {
    const event = req.body || {};

    // TODO(フェーズ0): 実際のWebhookペイロード構造に合わせて下記を確定する。
    //   - イベント種別を表すフィールド名(例: event / type)
    //   - 受注に紐づく会員IDのフィールド名(例: member_id / customer_id)
    //   - 一意なイベントIDのフィールド名(冪等処理に使用)
    const eventType = event.event || event.type || 'unknown';
    const memberId = event.member_id || event.customer_id || event?.data?.member_id;
    const eventKey = event.id || event.event_id || `${eventType}:${memberId}:${event.updated_at || ''}`;

    if (store.isDuplicateEvent(eventKey)) {
      console.log('[webhook] 重複イベントをスキップ:', eventKey);
      return;
    }

    const message = buildMessage(eventType, event);
    if (!message || !memberId) {
      console.log('[webhook] 通知対象外:', eventType, 'member=', memberId);
      return;
    }

    const tokens = store.tokensForMember(memberId);
    if (tokens.length === 0) {
      console.log('[webhook] 端末未登録の会員:', memberId);
      return;
    }

    const { invalid } = await sendPushToTokens(tokens, message);
    invalid.forEach((t) => store.removeToken(t));
    console.log(`[webhook] 送信 type=${eventType} member=${memberId} 端末=${tokens.length}`);
  } catch (err) {
    console.error('[webhook] 処理エラー:', err);
  }
});

// イベント種別 → 通知文。リピート発注向けの主要通知をここで定義する。
function buildMessage(eventType, event) {
  switch (eventType) {
    case 'order.created':
      return { title: 'ご注文を承りました', body: 'ご注文ありがとうございます。内容をご確認ください。',
        data: { url: '/order/history' } };
    case 'order.shipped':
      return { title: '出荷しました', body: 'ご注文の商品を発送しました。', data: { url: '/order/history' } };
    case 'order.updated':
      return { title: '注文内容が更新されました', body: '注文の状態が変わりました。', data: { url: '/order/history' } };
    default:
      // 未定義のイベントは通知しない(null を返すと送信されない)
      return null;
  }
}

app.listen(config.port, () => {
  console.log(`Bカート中継サーバー起動: http://localhost:${config.port}`);
  console.log(`APNs: ${config.apns.production ? '本番' : 'サンドボックス'} / topic=${config.apns.bundleId}`);
});
