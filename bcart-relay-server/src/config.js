import 'dotenv/config';

function required(name) {
  const v = process.env[name];
  if (!v) {
    console.warn(`[config] 環境変数 ${name} が未設定です。.env を確認してください。`);
  }
  return v;
}

export const config = {
  port: Number(process.env.PORT || 8080),

  webhook: {
    // Bカートの Bcart-Signature を検証するための署名シークレット(Webhook登録時に設定する値)
    signingSecret: process.env.BCART_WEBHOOK_SIGNING_SECRET || '',
    // 簡易フォールバック: URL ?token= / ヘッダー X-Relay-Token による共有シークレット
    sharedSecret: process.env.WEBHOOK_SHARED_SECRET || '',
    // true の場合、署名/トークン検証に失敗したリクエストを拒否する。
    // PoCの初回キャプチャ時は false にして実ペイロードを観察し、仕様確定後 true にする。
    strict: String(process.env.WEBHOOK_VERIFY_STRICT).toLowerCase() === 'true',
    // 受信した生ペイロードを data/webhook-capture.log に記録する(フェーズ0の調査用)
    capture: String(process.env.WEBHOOK_CAPTURE).toLowerCase() === 'true',
  },

  // 管理画面(/admin)と一斉配信APIのパスワード
  adminSecret: process.env.ADMIN_SECRET || '',

  apns: {
    keyPath: required('APNS_KEY_PATH'),
    keyId: required('APNS_KEY_ID'),
    teamId: required('APNS_TEAM_ID'),
    bundleId: required('APNS_BUNDLE_ID'),
    production: String(process.env.APNS_PRODUCTION).toLowerCase() === 'true',
  },

  bcart: {
    token: process.env.BCART_API_TOKEN || '',
    apiBase: process.env.BCART_API_BASE || 'https://api.bcart.jp',
  },
};
