# Bカート中継サーバー(PoC)

Bカートの **Webhook** を受信し、iOSアプリへ **APNs プッシュ通知** を送る中継サーバーです。
XServer VPS(Node.js)で常時稼働させる前提の最小実装(PoC)です。

```
Bカート ──Webhook(POST)──▶ この中継サーバー ──APNs──▶ iOSアプリ
                              │
                      会員ID⇄端末トークン(SQLite)
```

## 機能(PoC範囲)

- `POST /devices/register` … iOSアプリがログイン時に「会員ID + デバイストークン」を登録
- `POST /webhook/bcart` … BカートWebhookを受信し、対象会員の端末へプッシュ送信
- `POST /push/test` … 動作確認用の手動テスト送信
- `GET /healthz` … 死活監視
- SQLite による会員⇄端末の対応表 + Webhook冪等処理(重複イベント除去)

> ⚠️ PoCのため、Webhookペイロードのフィールド名は仮置きです。`src/server.js` の `TODO(フェーズ0)` を、実際のBカートWebhook仕様に合わせて確定してください。

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
# 端末を登録(実際は iOS アプリが叩く)
curl -X POST localhost:8080/devices/register \
  -H 'content-type: application/json' \
  -d '{"memberId":"1001","deviceToken":"<実機のデバイストークン>"}'

# テスト送信
curl -X POST localhost:8080/push/test \
  -H 'content-type: application/json' \
  -d '{"memberId":"1001","title":"テスト","body":"届きましたか？"}'
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
