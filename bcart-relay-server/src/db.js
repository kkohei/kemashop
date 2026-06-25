import Database from 'better-sqlite3';
import fs from 'node:fs';
import path from 'node:path';

const DATA_DIR = path.resolve('data');
fs.mkdirSync(DATA_DIR, { recursive: true });

const db = new Database(path.join(DATA_DIR, 'relay.sqlite'));
db.pragma('journal_mode = WAL');

// 会員ID ⇄ デバイストークンの対応表
// 1人の会員が複数端末を持てるよう (member_id, device_token) を一意にする
db.exec(`
  CREATE TABLE IF NOT EXISTS devices (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id     TEXT NOT NULL,
    device_token  TEXT NOT NULL,
    platform      TEXT NOT NULL DEFAULT 'ios',
    updated_at    TEXT NOT NULL,
    UNIQUE(member_id, device_token)
  );
  CREATE INDEX IF NOT EXISTS idx_devices_member ON devices(member_id);

  -- Webhook の冪等処理用(重複イベントを弾く)
  CREATE TABLE IF NOT EXISTS processed_events (
    event_key   TEXT PRIMARY KEY,
    created_at  TEXT NOT NULL
  );
`);

const stmtUpsertDevice = db.prepare(`
  INSERT INTO devices (member_id, device_token, platform, updated_at)
  VALUES (@member_id, @device_token, @platform, @updated_at)
  ON CONFLICT(member_id, device_token)
  DO UPDATE SET platform = excluded.platform, updated_at = excluded.updated_at
`);

const stmtTokensByMember = db.prepare(
  `SELECT device_token FROM devices WHERE member_id = ?`
);

const stmtDeleteToken = db.prepare(`DELETE FROM devices WHERE device_token = ?`);

const stmtSeenEvent = db.prepare(`SELECT 1 FROM processed_events WHERE event_key = ?`);
const stmtMarkEvent = db.prepare(
  `INSERT OR IGNORE INTO processed_events (event_key, created_at) VALUES (?, ?)`
);

export const store = {
  registerDevice({ memberId, deviceToken, platform = 'ios' }) {
    stmtUpsertDevice.run({
      member_id: String(memberId),
      device_token: deviceToken,
      platform,
      updated_at: new Date().toISOString(),
    });
  },

  tokensForMember(memberId) {
    return stmtTokensByMember.all(String(memberId)).map((r) => r.device_token);
  },

  // APNs から無効と返ったトークンを掃除する
  removeToken(deviceToken) {
    stmtDeleteToken.run(deviceToken);
  },

  // 既に処理済みのイベントなら true。未処理なら記録して false を返す
  isDuplicateEvent(eventKey) {
    if (!eventKey) return false;
    if (stmtSeenEvent.get(eventKey)) return true;
    stmtMarkEvent.run(eventKey, new Date().toISOString());
    return false;
  },
};

export default db;
