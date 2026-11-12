import crypto from 'node:crypto';

// 長さが違っても例外を投げないタイミングセーフ比較
export function safeEqual(a, b) {
  const ba = Buffer.from(String(a ?? ''));
  const bb = Buffer.from(String(b ?? ''));
  if (ba.length !== bb.length) {
    // 長さ差でも処理時間がほぼ変わらないようダミー比較してから false
    crypto.timingSafeEqual(bb, bb);
    return false;
  }
  return crypto.timingSafeEqual(ba, bb);
}

// ログ用: メールアドレスは先頭1文字 + ドメインのみ表示(例: a***@example.com)
export function redactKey(value) {
  const s = String(value ?? '');
  const i = s.indexOf('@');
  if (i < 0) return s;
  return `${s.slice(0, 1)}***${s.slice(i)}`;
}

export function redactKeys(keys) {
  return keys.map(redactKey);
}
