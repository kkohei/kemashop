import { sendPushToTokens as sendApnsToTokens } from './apns.js';
import { sendFcmToTokens } from './fcm.js';

/**
 * プラットフォーム混在の端末リストへプッシュを送る。
 * iOS(platform !== 'android') → APNs / Android → FCM に自動振り分け。
 * @param devices [{ device_token, platform }]
 */
export async function sendToDevices(devices, message) {
  const iosTokens = devices.filter((d) => d.platform !== 'android').map((d) => d.device_token);
  const androidTokens = devices.filter((d) => d.platform === 'android').map((d) => d.device_token);

  const results = [];
  const invalid = [];

  if (iosTokens.length > 0) {
    const r = await sendApnsToTokens(iosTokens, message);
    results.push(...r.results);
    invalid.push(...r.invalid);
  }
  if (androidTokens.length > 0) {
    const r = await sendFcmToTokens(androidTokens, message);
    results.push(...r.results);
    invalid.push(...r.invalid);
  }

  return { results, invalid };
}
