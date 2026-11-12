import express from 'express';
import rateLimit from 'express-rate-limit';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from './config.js';
import { store } from './db.js';
import { sendToDevices } from './push.js';
import { safeEqual, redactKey, redactKeys } from './util.js';
import { verifyWebhook } from './webhook.js';
// bcart.js(受注API取得)は再入荷ポーリング等の将来拡張用。ここでは未使用。

export const app = express();
app.set('trust proxy', config.trustProxy);
app.disable('x-powered-by');

// HMAC検証のため生ボディを保持しつつ JSON もパースする
app.use(
  express.json({
    limit: '1mb',
    verify: (req, _res, buf) => {
      req.rawBody = buf.toString('utf8');
    },
  })
);

// async ハンドラの例外を Express のエラーハンドラ(500)へ流す
const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// ---- レート制限 ----
const limiter = (windowMs, limit, extra = {}) =>
  rateLimit({
    windowMs,
    limit,
    standardHeaders: true,
    legacyHeaders: false,
    message: { ok: false, error: 'too many requests' },
    // 万一 X-Forwarded-For が無い/設定不一致でも落ちないように検証警告を無効化
    validate: { xForwardedForHeader: false, trustProxy: false },
    ...extra,
  });
const MIN = 60 * 1000;
const limitDevices = limiter(MIN, 30);
const limitDeletion = limiter(MIN, 10);
const limitWebhook = limiter(MIN, 120); // Bカートの実トラフィックに余裕を持たせる
const limitAdminGeneral = limiter(MIN, 60);
const limitAdminStrict = limiter(MIN, 10);
// 認証失敗(401/503)だけを数える。成功リクエストは対象外 → ブルートフォース対策
const limitAuthFail = limiter(15 * MIN, 10, { skipSuccessfulRequests: true });
const limitPushTest = limiter(MIN, 10);

// ---- ヘルスチェック ----
app.get('/healthz', (_req, res) => res.json({ ok: true }));

// ---- 静的ファイル配信(告知記事の画像など) ----
const publicDir = fileURLToPath(new URL('../public', import.meta.url));
app.use('/assets', express.static(publicDir, { maxAge: '7d' }));

// ---- アプリ認証(段階移行) ----
// 新: X-App-Token == APP_REGISTER_SECRET なら認証済み。
// 旧(配布済みアプリはトークンを送らない): ALLOW_LEGACY_DEVICE_REGISTER=true の間は許可し、毎回警告ログ。
function appAuth(req, res, next) {
  const token = req.get('X-App-Token');
  if (token && config.devices.registerSecret && safeEqual(token, config.devices.registerSecret)) {
    req.appAuthed = true;
    return next();
  }
  if (config.devices.allowLegacy) {
    console.warn(
      `[devices] レガシー認証で受付(${token ? 'X-App-Token 不一致' : 'X-App-Token なし'}) ${req.method} ${req.path} ip=${req.ip}`
    );
    return next();
  }
  return res.status(401).json({ ok: false, error: 'unauthorized' });
}

const isStr = (v, max) => typeof v === 'string' && v.length > 0 && v.length <= max;
// APNs の :path やログに混入しないよう、空白・制御文字・スラッシュを拒否(FCMトークンは英数記号で / を含まない)
const isToken = (v) => isStr(v, 512) && !/[/\s\x00-\x1f]/.test(v);

// ---- デバイス登録 ----
// アプリがログイン成功時に呼ぶ: { memberId, deviceToken, platform }
app.post('/devices/register', limitDevices, appAuth, (req, res) => {
  const { memberId, deviceToken, platform } = req.body || {};
  const mid = typeof memberId === 'number' ? String(memberId) : memberId;
  if (!isStr(mid, 255) || !isToken(deviceToken)) {
    return res.status(400).json({ ok: false, error: 'memberId と deviceToken は必須です' });
  }
  store.registerDevice({
    memberId: mid,
    deviceToken,
    platform: platform === 'android' ? 'android' : 'ios',
  });
  res.json({ ok: true });
});

// ---- デバイス登録解除(ログアウト/退会時にアプリが呼ぶ想定) ----
app.post('/devices/unregister', limitDevices, appAuth, (req, res) => {
  const { deviceToken, memberId } = req.body || {};
  const mid = typeof memberId === 'number' ? String(memberId) : memberId;
  if (!isToken(deviceToken) || (mid != null && mid !== '' && !isStr(mid, 255))) {
    return res.status(400).json({ ok: false, error: 'deviceToken は必須です' });
  }
  const removed = store.unregisterDevice({ deviceToken, memberId: mid });
  res.json({ ok: true, removed });
});

// ---- 管理画面(一斉配信) ----
const adminHtml = fs.readFileSync(new URL('./admin.html', import.meta.url), 'utf8');

function requireAdmin(req, res, next) {
  if (!config.adminSecret) {
    return res.status(503).json({ ok: false, error: 'ADMIN_SECRET が未設定です(.env を確認)' });
  }
  if (!safeEqual(req.get('X-Admin-Token') || '', config.adminSecret)) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }
  next();
}

app.get('/admin', limitAdminGeneral, (_req, res) => res.type('html').send(adminHtml));

app.get('/admin/stats', limitAdminStrict, limitAuthFail, requireAdmin, (_req, res) => {
  res.json({
    ok: true,
    devices: store.deviceCount(),
    pendingDeletions: store.pendingDeletionCount(),
    broadcasts: store.listBroadcasts(),
    deletionRequests: store.listDeletionRequests(),
  });
});

// 退会申請を「対応済み」にする(Bカート管理画面で会員削除を終えた後に押す)
app.post('/admin/deletion-handled', limitAdminStrict, limitAuthFail, requireAdmin, (req, res) => {
  const { id } = req.body || {};
  if (!id) return res.status(400).json({ ok: false, error: 'id は必須です' });
  store.markDeletionHandled(id);
  res.json({ ok: true });
});

// 全端末への一斉配信
app.post(
  '/admin/broadcast',
  limitAdminStrict,
  limitAuthFail,
  requireAdmin,
  wrap(async (req, res) => {
    const { title, body } = req.body || {};
    if (!title || !body) {
      return res.status(400).json({ ok: false, error: 'title と body は必須です' });
    }
    const devices = store.allDevices();
    if (devices.length === 0) {
      return res.json({ ok: true, sent: 0, failed: 0, removed: 0 });
    }
    const { results, invalid } = await sendToDevices(devices, { title, body, data: { url: '/' } });
    invalid.forEach((t) => store.removeToken(t));
    const sent = results.filter((r) => r.ok).length;
    store.addBroadcast({ title, body, sentCount: sent });
    console.log(`[broadcast] "${title}" 送信=${sent} 失敗=${results.length - sent} 無効削除=${invalid.length}`);
    res.json({ ok: true, sent, failed: results.length - sent, removed: invalid.length });
  })
);

// ---- 退会(アカウント削除)申請 ----
// アプリの「退会申請」ボタンから呼ばれる。管理者が管理画面で実際に削除する運用。
app.post('/account/deletion-request', limitDeletion, (req, res) => {
  const { memberId, deviceToken } = req.body || {};
  store.addDeletionRequest({ memberId, deviceToken });
  console.log('[deletion] 退会申請 member=', memberId ? redactKey(memberId) : '(不明)');
  res.json({ ok: true });
});

// ---- 手動テスト送信(管理者のみ) ----
app.post(
  '/push/test',
  limitPushTest,
  limitAuthFail,
  requireAdmin,
  wrap(async (req, res) => {
    const { memberId, title = 'テスト通知', body = 'これはテストです' } = req.body || {};
    if (!memberId) return res.status(400).json({ ok: false, error: 'memberId は必須です' });
    const devices = store.devicesForMember(memberId);
    if (devices.length === 0) {
      return res.status(404).json({ ok: false, error: 'この会員の端末が登録されていません' });
    }
    const { results, invalid } = await sendToDevices(devices, { title, body });
    invalid.forEach((t) => store.removeToken(t));
    res.json({ ok: true, sent: devices.length, results, removed: invalid.length });
  })
);

// ---- Webhook ----
// フェーズ0調査用: 検証を通過した(または非strictの)受信内容をファイルに追記。
// 顧客情報を含むため、サイズ上限を超えたら .1 にローテーションして古い分は破棄する。
function captureWebhook(req) {
  if (!config.webhook.capture) return;
  try {
    const dir = path.resolve('data');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'webhook-capture.log');
    try {
      if (fs.statSync(file).size >= config.webhook.captureMaxBytes) fs.renameSync(file, `${file}.1`);
    } catch {}
    const record = {
      at: new Date().toISOString(),
      signature: req.get('Bcart-Signature') || null,
      body: req.body,
    };
    fs.writeFileSync(file, JSON.stringify(record) + '\n', { flag: 'a', mode: 0o600 });
  } catch (err) {
    console.error('[capture] 失敗', err.message);
  }
}

const inflight = new Set(); // 同一イベントの並行処理を防ぐ

// 順序: 検証 → 重複チェック → 処理 → 成功したら処理済み記録 → 応答
//   401 検証NG(strict) / 200 成功or重複 / 500 処理失敗(未記録なので再送で再処理される)
app.post(
  '/webhook/bcart',
  limitWebhook,
  wrap(async (req, res) => {
    const verdict = verifyWebhook(
      {
        signatureHeader: req.get('Bcart-Signature'),
        token: req.query.token || req.get('X-Relay-Token'),
        rawBody: req.rawBody || '',
      },
      config.webhook
    );
    if (!verdict.ok) {
      console.warn('[webhook] 検証NG:', verdict.reason, config.webhook.strict ? '(拒否)' : '(継続: strict=false)');
      if (config.webhook.strict) return res.status(401).json({ ok: false, error: verdict.reason });
    }
    captureWebhook(req);

    const event = req.body || {};
    const eventType = event.event_type || 'unknown';
    // 冪等キー: Bカートの idempotency_key は null のことがあるため event_id(UUID)を優先
    const eventKey = event.event_id || event.idempotency_key || `${eventType}:${event?.data?.object?.id}`;

    if (store.isEventProcessed(eventKey)) {
      console.log('[webhook] 重複スキップ:', eventKey);
      return res.json({ ok: true, duplicate: true });
    }
    if (inflight.has(eventKey)) {
      // 処理中の同一イベント。Bカートに再送させる
      return res.status(503).set('Retry-After', '5').json({ ok: false, error: 'in-progress' });
    }
    inflight.add(eventKey);
    try {
      const { markKeys } = await handleEvent(eventType, event);
      store.markEventProcessed(eventKey);
      markKeys.forEach((k) => store.markEventProcessed(k));
      res.json({ ok: true });
    } catch (err) {
      console.error('[webhook] 処理エラー(未記録・再送で再処理可):', eventKey, err.message);
      res.status(500).json({ ok: false, error: 'processing-failed' });
    } finally {
      inflight.delete(eventKey);
    }
  })
);

// イベント種別ごとの処理。
// Bカートの実ペイロード(確定)に基づく:
//   - event_type: 'order.created' / 'order.updated'
//   - 会員ID:   data.object.customer_id
//   - 出荷状況: data.object.logistics[].status === '発送済'
//   - 受注番号: data.object.code
async function handleEvent(eventType, event) {
  const order = event?.data?.object;
  const markKeys = []; // 処理成功後に処理済みとして記録する追加キー
  if (!order) return { markKeys };

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
    } else if (shipped && !store.isEventProcessed(`shipped:${order.id}`)) {
      // order.updated は編集の度に飛ぶため、出荷通知は1受注につき1回だけ送る
      message = {
        title: '出荷しました',
        body: `ご注文(No.${order.code})を発送しました。`,
        data: { url: '/mypage.php', orderId: order.id },
      };
      markKeys.push(`shipped:${order.id}`);
    }

    await pushToKeys(keys, message, eventType);
    return { markKeys };
  }

  // 会員・配送先イベント等は現状通知対象外(必要になれば追加)
  console.log('[webhook] 通知対象外のイベント:', eventType);
  return { markKeys };
}

// 複数キー(customer_id / email)に紐づく端末を重複なく集める(platform込み)
function devicesForKeys(keys) {
  const seen = new Map();
  for (const k of keys) {
    for (const d of store.devicesForMember(String(k))) {
      seen.set(d.device_token, d);
    }
  }
  return [...seen.values()];
}

async function pushToKeys(keys, message, eventType) {
  if (!keys.length || !message) {
    console.log('[webhook] 送信なし type=', eventType, 'keys=', redactKeys(keys));
    return;
  }
  const devices = devicesForKeys(keys);
  if (devices.length === 0) {
    console.log('[webhook] 端末未登録 keys=', redactKeys(keys));
    return;
  }
  const { results, invalid } = await sendToDevices(devices, message);
  invalid.forEach((t) => store.removeToken(t));
  // 無効トークン以外の理由で全件失敗(APNs/FCM障害等)なら失敗扱い → 500 で再送させる
  const transientFail = results.filter((r) => !r.ok && !invalid.includes(r.deviceToken));
  if (results.length > 0 && !results.some((r) => r.ok) && transientFail.length > 0) {
    throw new Error(`push failed for all devices (${transientFail[0].reason || transientFail[0].status})`);
  }
  console.log(`[webhook] 送信 type=${eventType} keys=${redactKeys(keys).join(',')} 端末=${devices.length}`);
}


// ---- 共通エラーハンドラ(未捕捉の例外・不正JSON) ----
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (err?.type === 'entity.parse.failed' || err?.status === 400) {
    return res.status(400).json({ ok: false, error: 'bad request' });
  }
  if (err?.type === 'entity.too.large') return res.status(413).json({ ok: false, error: 'too large' });
  console.error('[error]', err?.message || err);
  res.status(500).json({ ok: false, error: 'internal error' });
});
