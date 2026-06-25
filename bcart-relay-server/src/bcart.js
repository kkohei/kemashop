import { config } from './config.js';

// Bカート API クライアント。
// Webhook は「対象データのID」だけを通知する設計のため、会員IDや出荷ステータスなど
// 通知判断に必要な詳細は、このクライアントで受注APIから取得する。
//
// TODO(フェーズ0): 実際のエンドポイントパスとレスポンス項目名を docs.api.bcart.jp で確定する。
//   - 受注取得のパス(例: /orders/{id} など)
//   - ?complete=1 で受注 + 受注商品 + 出荷(logistic)を一括取得できることを確認
//   - レスポンス内の会員ID項目名(member_id など)と logistic.status の値('未発送' 等)

export async function fetchOrder(orderId) {
  if (!config.bcart.token) {
    console.warn('[bcart] BCART_API_TOKEN 未設定のため受注取得をスキップ');
    return null;
  }
  const url = `${config.bcart.apiBase}/orders/${orderId}?complete=1`;
  try {
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${config.bcart.token}` },
    });
    if (!res.ok) {
      console.error('[bcart] 受注取得失敗', orderId, res.status);
      return null;
    }
    return await res.json();
  } catch (err) {
    console.error('[bcart] 受注取得エラー', orderId, err.message);
    return null;
  }
}

// 受注レスポンスから会員IDと出荷ステータスを取り出す(項目名はフェーズ0で確定して調整)。
export function extractOrderInfo(order) {
  if (!order) return {};
  return {
    memberId: order.member_id ?? order.customer_id ?? order?.member?.id,
    shippingStatus: order?.logistic?.status,
    arrivalDate: order?.logistic?.arrival_date,
  };
}
