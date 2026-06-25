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
  webhookSecret: required('WEBHOOK_SHARED_SECRET'),
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
