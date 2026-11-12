import { app } from './app.js';
import { config } from './config.js';
import { store } from './db.js';

process.on('unhandledRejection', (err) => console.error('[unhandledRejection]', err));

// processed_events の保持期間クリーンアップ(起動時 + 6時間ごと)
function cleanup() {
  try {
    const n = store.cleanupProcessedEvents(config.processedEventsRetentionDays);
    if (n > 0) console.log(`[cleanup] processed_events ${n} 件削除`);
  } catch (err) {
    console.error('[cleanup] 失敗', err.message);
  }
}
cleanup();
setInterval(cleanup, 6 * 60 * 60 * 1000).unref();

app.listen(config.port, () => {
  console.log(`Bカート中継サーバー起動: http://localhost:${config.port}`);
  console.log(`APNs: ${config.apns.production ? '本番' : 'サンドボックス'} / topic=${config.apns.bundleId}`);
  console.log(`Webhook検証: strict=${config.webhook.strict} / capture=${config.webhook.capture}`);
  if (!config.webhook.signingSecret && !config.webhook.sharedSecret) {
    console.warn('[config] Webhook の秘密(BCART_WEBHOOK_SIGNING_SECRET / WEBHOOK_SHARED_SECRET)が未設定です。strict では全Webhookを拒否します');
  }
  if (config.devices.allowLegacy) {
    console.warn('[config] ALLOW_LEGACY_DEVICE_REGISTER=true: トークン無しの端末登録を許可中(更新アプリ配布後に false へ)');
  } else if (!config.devices.registerSecret) {
    console.warn('[config] ALLOW_LEGACY_DEVICE_REGISTER=false ですが APP_REGISTER_SECRET が未設定: 端末登録は全て拒否されます');
  }
});
