import 'dotenv/config';

function required(name) {
  const v = process.env[name];
  if (!v) {
    console.warn(`[config] 環境変数 ${name} が未設定です。.env を確認してください。`);
  }
  return v;
}

function num(v, d) {
  const n = Number(v);
  return v !== undefined && v !== '' && Number.isFinite(n) ? n : d;
}

function parseTrustProxy(v) {
  if (v === undefined || v === '') return 1; // 既定: nginx 1段
  if (String(v).toLowerCase() === 'false') return false;
  const n = Number(v);
  return Number.isInteger(n) ? n : v;
}

export const config = {
  port: Number(process.env.PORT || 8080),

  // DB パス(テスト時は :memory: や一時ファイルを指定可)。既定 data/relay.sqlite
  dbPath: process.env.RELAY_DB_PATH || '',

  webhook: {
    // Bカートの Bcart-Signature を検証するための署名シークレット(Webhook登録時に設定する値)
    signingSecret: process.env.BCART_WEBHOOK_SIGNING_SECRET || '',
    // 簡易フォールバック: URL ?token= / ヘッダー X-Relay-Token による共有シークレット
    sharedSecret: process.env.WEBHOOK_SHARED_SECRET || '',
    // true の場合、署名/トークン検証に失敗したリクエストを拒否する。
    // PoCの初回キャプチャ時は false にして実ペイロードを観察し、仕様確定後 true にする。
    // 既定は strict(fail closed)。明示的に文字列 "false" を指定した場合のみ緩める。
    strict: String(process.env.WEBHOOK_VERIFY_STRICT ?? '').trim().toLowerCase() !== 'false',
    // Bcart-Signature の date が現在時刻から何秒以内か(0 で無効化)
    maxAgeSec: num(process.env.WEBHOOK_MAX_AGE_SEC, 300),
    // 受信した生ペイロードを data/webhook-capture.log に記録する(調査用。既定 false)
    capture: String(process.env.WEBHOOK_CAPTURE ?? '').trim().toLowerCase() === 'true',
    // キャプチャログの最大サイズ(超えたら .1 へローテーションし古い方は破棄)
    captureMaxBytes: num(process.env.WEBHOOK_CAPTURE_MAX_BYTES, 1024 * 1024),
  },

  devices: {
    // 新方式: ヘッダー X-App-Token と比較する登録用シークレット
    registerSecret: process.env.APP_REGISTER_SECRET || '',
    // 旧アプリ(トークン無し)の登録を許可するか。既定 true。"false" のときのみ拒否。
    allowLegacy: String(process.env.ALLOW_LEGACY_DEVICE_REGISTER ?? '').trim().toLowerCase() !== 'false',
  },

  // processed_events の保持日数
  processedEventsRetentionDays: num(process.env.PROCESSED_EVENTS_RETENTION_DAYS, 30),

  // nginx 等のリバースプロキシ段数(レート制限のクライアントIP判定用)。直接公開なら false
  trustProxy: parseTrustProxy(process.env.TRUST_PROXY),

  // 管理画面(/admin)と一斉配信APIのパスワード
  adminSecret: process.env.ADMIN_SECRET || '',

  apns: {
    keyPath: required('APNS_KEY_PATH'),
    keyId: required('APNS_KEY_ID'),
    teamId: required('APNS_TEAM_ID'),
    bundleId: required('APNS_BUNDLE_ID'),
    production: String(process.env.APNS_PRODUCTION).toLowerCase() === 'true',
  },

  // FCM(Androidプッシュ)。Firebaseのサービスアカウント鍵JSONのパス
  fcm: {
    serviceAccountPath: process.env.FCM_SERVICE_ACCOUNT_PATH || '',
  },

  bcart: {
    token: process.env.BCART_API_TOKEN || '',
    apiBase: process.env.BCART_API_BASE || 'https://api.bcart.jp',
  },
};
