// 退会(アカウント削除)申請の一覧を表示する。
// 使い方(サーバー上で): node list-deletion-requests.mjs
import Database from 'better-sqlite3';

const db = new Database('data/relay.sqlite');
const rows = db.prepare(
  'SELECT id, member_id, created_at, handled FROM deletion_requests ORDER BY created_at DESC'
).all();

if (rows.length === 0) {
  console.log('退会申請はありません。');
} else {
  console.log(`退会申請 ${rows.length}件:`);
  for (const r of rows) {
    console.log(`  [${r.handled ? '対応済' : '未対応'}] ${r.created_at}  会員: ${r.member_id || '(不明)'}`);
  }
  console.log('\n※ 未対応の会員をBカート管理画面で削除してください。');
}
