import crypto from 'node:crypto';
import { safeEqual } from './util.js';

// ---- Bカート Webhook 検証(副作用なし・単体テスト可能) ----
//
// 署名: `Bcart-Signature: date=<date>,v1=<hex>`
//   HMAC-SHA256(secret, `${date}.${rawBody}`) の hex が v1 と一致すれば正当。
// 共有シークレット: `?token=` または `X-Relay-Token` ヘッダー(timingSafeEqual で比較)。
//
// date の形式(Bカート仕様書で未確定のため、次の順で解釈する):
//   1. 10桁の数値        → UNIX秒
//   2. 13桁の数値        → UNIXミリ秒
//   3. その他の数値      → UNIX秒(小数可)
//   4. それ以外の文字列  → Date.parse(ISO8601 / RFC2822 / HTTP-date)
//   解釈できなければ不正。タイムゾーン無しの文字列は Date.parse 次第(サーバーのTZ)で
//   ずれる可能性があるため、その場合は WEBHOOK_MAX_AGE_SEC=0 で鮮度チェックを無効化できる。

export function parseDateToMs(value) {
  if (value == null) return null;
  const s = String(value).trim();
  if (!s) return null;
  if (/^\d+(\.\d+)?$/.test(s)) {
    const n = Number(s);
    if (!Number.isFinite(n)) return null;
    return s.split('.')[0].length === 13 ? n : n * 1000;
  }
  const t = Date.parse(s);
  return Number.isNaN(t) ? null : t;
}

export function parseSignatureHeader(header) {
  const parts = {};
  // HTTP-date 内のカンマで分割しないよう、直後が key= のカンマのみ区切りとする
  for (const kv of String(header || "").split(/,(?=\s*[A-Za-z0-9_]+=)/)) {
    const i = kv.indexOf('=');
    if (i < 0) continue;
    parts[kv.slice(0, i).trim()] = kv.slice(i + 1).trim();
  }
  return parts;
}

export function verifySignature({ header, rawBody, secret, now = Date.now(), maxAgeSec = 300 }) {
  if (!header) return { ok: false, reason: 'no-signature' };
  const parts = parseSignatureHeader(header);
  if (!parts.date || !parts.v1) return { ok: false, reason: 'malformed-signature' };
  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${parts.date}.${rawBody || ''}`)
    .digest('hex');
  if (!safeEqual(parts.v1, expected)) return { ok: false, reason: 'signature-mismatch' };
  if (maxAgeSec > 0) {
    const ts = parseDateToMs(parts.date);
    if (ts == null) return { ok: false, reason: 'date-unparsable' };
    if (Math.abs(now - ts) > maxAgeSec * 1000) return { ok: false, reason: 'date-out-of-range' };
  }
  return { ok: true, reason: 'signature-ok' };
}

export function verifySharedSecret({ token, secret }) {
  if (!token) return { ok: false, reason: 'no-token' };
  return safeEqual(token, secret)
    ? { ok: true, reason: 'shared-secret-ok' }
    : { ok: false, reason: 'shared-secret-mismatch' };
}

/**
 * @param req { signatureHeader, token, rawBody }
 * @param cfg { signingSecret, sharedSecret, maxAgeSec }
 * 設定された方式のいずれかが通れば ok。どの秘密も未設定なら ok:false(fail closed)。
 * strict かどうかの扱い(拒否するか)は呼び出し側が決める。
 */
export function verifyWebhook(req, cfg, now = Date.now()) {
  if (!cfg.signingSecret && !cfg.sharedSecret) {
    return { ok: false, reason: 'no-secret-configured' };
  }
  let last = null;
  if (cfg.signingSecret) {
    last = verifySignature({
      header: req.signatureHeader,
      rawBody: req.rawBody,
      secret: cfg.signingSecret,
      now,
      maxAgeSec: cfg.maxAgeSec,
    });
    if (last.ok) return last;
  }
  if (cfg.sharedSecret) {
    const r = verifySharedSecret({ token: req.token, secret: cfg.sharedSecret });
    if (r.ok) return r;
    // 署名ヘッダーが付いていたなら、署名側の失敗理由を優先して返す
    if (!last || !req.signatureHeader) last = r;
  }
  return last;
}
