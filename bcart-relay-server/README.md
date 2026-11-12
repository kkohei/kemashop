# Bカート中継サーバー(PoC)

Bカートの **Webhook** を受信し、iOSアプリへ **APNs プッシュ通知** を送る中継サーバーです。
XServer VPS(Node.js)で常時稼働させる前提の最小実装(PoC)です。

```
Bカート ──Webhook(POST)──▶ この中継サーバー ──APNs──▶ iOSアプリ
                              │
                      会員ID⇄端末トークン(SQLite)
```

## 機能(PoC範囲)

- `POST /devices/register` … アプリがログイン時に「会員ID + デバイストークン」を登録(1トークン=1会員。別会員で再登録すると前の紐付けは削除)
- `POST /devices/unregister` … `{ deviceToken, memberId? }` で端末を登録解除(更新版アプリがログアウト時に呼ぶ想定)
- `POST /webhook/bcart` … BカートWebhookを受信し、対象会員の端末へプッシュ送信
- `POST /push/test` … 動作確認用の手動テスト送信(**管理者のみ**: `X-Admin-Token` 必須)
- `GET /healthz` … 死活監視
- SQLite による会員⇄端末の対応表 + Webhook冪等処理(重複イベント除去)

> Webhook のフィールド名は Bカート実ペイロード(order.created / order.updated)に合わせて実装済みです。

---

## 必要なもの

1. **XServer VPS**(2GBプランで十分。OSは Ubuntu を推奨)
2. **独自ドメイン**(WebhookをHTTPSで受けるため。サブドメイン可)
3. **Apple Developer Program** で発行する以下:
   - APNs認証キー `.p8`(Key ID付き)
   - Team ID / アプリの Bundle ID

---

## ローカルでの動作確認

```bash
npm install
cp .env.example .env      # 値を埋める(.p8パス, KeyID, TeamID, BundleID 等)
mkdir -p secrets          # ここに AuthKey_XXXX.p8 を置く
npm start
```

別ターミナルでテスト:

```bash
# 端末を登録(実際はアプリが叩く。X-App-Token は APP_REGISTER_SECRET を設定した場合のみ必要)
curl -X POST localhost:8080/devices/register \
  -H 'content-type: application/json' \
  -H "X-App-Token: $APP_REGISTER_SECRET" \
  -d '{"memberId":"1001","deviceToken":"<実機のデバイストークン>","platform":"ios"}'

# 登録解除
curl -X POST localhost:8080/devices/unregister \
  -H 'content-type: application/json' \
  -H "X-App-Token: $APP_REGISTER_SECRET" \
  -d '{"deviceToken":"<実機のデバイストークン>"}'

# テスト送信(管理者のみ。ADMIN_SECRET を X-Admin-Token に)
curl -X POST localhost:8080/push/test \
  -H 'content-type: application/json' \
  -H "X-Admin-Token: $ADMIN_SECRET" \
  -d '{"memberId":"1001","title":"テスト","body":"届きましたか？"}'
```

テスト実行: `npm test`(Node 20+ の `node --test`。ポート不要)。

---

## セキュリティ設定(重要)

### 端末登録の認証(段階移行)
配布済みアプリ(iOS v1.0 / 現行Android)は秘密を送らないため、いきなり必須にすると登録できなくなります。

| 状態 | 挙動 |
|------|------|
| `X-App-Token` が `APP_REGISTER_SECRET` と一致 | 認証済みで受付 |
| 不一致/なし かつ `ALLOW_LEGACY_DEVICE_REGISTER=true`(**既定**) | レガシーとして受付し、毎回警告ログ(トークン値は出さない) |
| 不一致/なし かつ `ALLOW_LEGACY_DEVICE_REGISTER=false` | 401 |

**運用:** 更新版アプリ(`X-App-Token` を送る版)が行き渡るまでは **`true` のまま**にしてください。配布後に `false` へ変更し `pm2 restart bcart-relay --update-env`。早すぎると旧アプリの端末登録・プッシュが止まります。
`/devices/unregister` も同じ認証です。

### Webhook 検証(既定 strict / fail closed)
- `WEBHOOK_VERIFY_STRICT` は **未設定でも true**。文字列 `false` のときだけ検証失敗を通します。
- 署名(`BCART_WEBHOOK_SIGNING_SECRET`)または共有シークレット(`WEBHOOK_SHARED_SECRET`、`?token=` / `X-Relay-Token`)のどちらかが通れば OK。両方未設定なら strict では全拒否。
- 比較はすべて timingSafeEqual。署名の `date` は既定で現在時刻 ±300秒(`WEBHOOK_MAX_AGE_SEC`)。date は UNIX秒/ミリ秒/ISO8601/HTTP-date を解釈し、解釈不能なら拒否(Bカートの正確な形式は未確定。タイムゾーン無しの文字列でずれる場合は `WEBHOOK_MAX_AGE_SEC=0`)。
- 応答: 検証NG→401 / 成功・重複→200 / 処理失敗→500(処理済み記録は成功後のみなので再送で再処理)。
- `WEBHOOK_CAPTURE` 既定 false。true の間は `data/webhook-capture.log` が1MBでローテーション(`.1` に退避、さらに古い分は破棄)。
- `processed_events` は30日超を起動時と6時間ごとに削除。ログ上のメールアドレスは `a***@domain` に伏せます。

### レート制限(IPごと・1分あたり、メモリ内)
`/webhook/bcart` 120 / `/devices/*` 30 / `/account/deletion-request` 10 / `/push/test` 10 / `/admin/stats`・`/admin/broadcast`・`/admin/deletion-handled` 10 / `/admin` 60。加えて管理トークン認証の失敗は 15分で10回まで(超過で 429)。
nginx 背後を前提に `TRUST_PROXY=1`(既定)でクライアントIPを判定します。

### 本番 .env で必要な変更
1. `WEBHOOK_VERIFY_STRICT=true`(または削除)、`BCART_WEBHOOK_SIGNING_SECRET` か `WEBHOOK_SHARED_SECRET` を必ず設定(**既に設定済みの値はそのまま動作**)
2. `WEBHOOK_CAPTURE=false`
3. `ADMIN_SECRET` を設定(`/push/test` も使用)
4. `APP_REGISTER_SECRET` を生成して設定(`ALLOW_LEGACY_DEVICE_REGISTER=true` のまま)
5. 新規依存(express-rate-limit)のため `npm install --omit=dev` が必要

### VPS への反映
`main` にはコードがほぼありません。ブランチを明示して反映します:
```bash
ssh xserver
cd ~/kemashop/bcart-relay-server
git fetch && git checkout <branch> && git pull && npm install --omit=dev && pm2 restart bcart-relay
```

実機にプッシュが届けば PoC 成功です(デバイストークンは実機アプリから取得)。

---

## XServer VPS へのデプロイ手順

### 1. VPSを用意
XServer VPS のパネルから **Ubuntu** イメージでサーバーを作成。SSHでログイン。

### 2. Node.js を入れる
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install 20
```

### 3. アプリを配置
```bash
git clone <このリポジトリ> && cd bcart-relay-server
npm install --omit=dev
cp .env.example .env && nano .env       # 本番値を設定(APNS_PRODUCTION は配布形態に合わせる)
mkdir -p secrets                         # AuthKey_XXXX.p8 を配置(scp等で転送)
```

### 4. PM2 で常駐化
```bash
npm install -g pm2
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup        # 表示されたコマンドを実行 → サーバー再起動後も自動起動
```

### 5. HTTPS(nginxリバースプロキシ + Let's Encrypt)
```bash
sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx
# /etc/nginx/sites-available/ に relay.example.com → http://127.0.0.1:8080 のプロキシ設定を作成
sudo certbot --nginx -d relay.example.com    # 無料SSL発行
```

nginx の proxy 設定例:
```nginx
server {
  server_name relay.example.com;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

### 6. ファイアウォール
XServer VPS のパケットフィルター(または `ufw`)で **80 / 443** を開放。アプリの 8080 は外部公開せず nginx 経由のみにする。

### 7. Bカート側に Webhook を登録
Bカート管理画面 → 外部連携 → Webhook で、エンドポイントに以下を登録:
```
https://relay.example.com/webhook/bcart?token=<WEBHOOK_SHARED_SECRETの値>
```
通知イベントは「受注の新規・更新」などを有効化。

---

## このあとの拡張(設計書フェーズ3以降)

- 出荷ステータス判定(`order.shipped` を実際のペイロードから判定)
- 再入荷通知(Bカート在庫APIの定期ポーリング → cron）
- 定期発注リマインド(発注履歴から算出してスケジュール送信）
- お知らせ一斉配信用の管理画面
- DBを SQLite → PostgreSQL へ(端末数・履歴が増えた場合)
