// SQLite ドライバのローダー。
// 本番は better-sqlite3(従来どおり)。ネイティブビルドできない環境(ビルドツール無しのCI/開発機)では
// Node 組み込みの node:sqlite に自動フォールバックする(テスト用途)。
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

export function openDatabase(file) {
  try {
    const Database = require('better-sqlite3');
    return new Database(file);
  } catch (err) {
    let DatabaseSync;
    try {
      ({ DatabaseSync } = require('node:sqlite'));
    } catch {
      throw err; // どちらも使えない場合は better-sqlite3 のエラーをそのまま出す
    }
    console.warn('[sqlite] better-sqlite3 を読み込めないため node:sqlite にフォールバックします:', String(err.message).split('\n')[0]);
    const raw = new DatabaseSync(file);
    return {
      exec: (sql) => raw.exec(sql),
      pragma: (s) => raw.exec(`PRAGMA ${s}`),
      prepare: (sql) => raw.prepare(sql),
      transaction: (fn) => (...args) => {
        raw.exec('BEGIN');
        try {
          const r = fn(...args);
          raw.exec('COMMIT');
          return r;
        } catch (e) {
          raw.exec('ROLLBACK');
          throw e;
        }
      },
    };
  }
}
