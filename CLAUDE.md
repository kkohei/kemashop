# KEMA プロジェクトメモ

## 重要なURL・ドメイン(忘れないこと)

| 用途 | URL |
|------|-----|
| **Bカートのショップ(買い手向けサイト)** | **https://kema.i17.bcart.jp/** |
| 同・ログイン | https://kema.i17.bcart.jp/login.php |
| 同・新規会員登録 | https://kema.i17.bcart.jp/regist.php |
| 同・マイページ(注文履歴) | https://kema.i17.bcart.jp/mypage.php |
| 同・プライバシーポリシー | https://kema.i17.bcart.jp/privacy.php |
| **App Store(KEMA PRO SHOP)** | **https://apps.apple.com/jp/app/kema-pro-shop/id6791068342** |
| 中継サーバー(XServer VPS) | https://relay.kema.hair |
| 通知管理画面(一斉配信・退会申請) | https://relay.kema.hair/admin |
| サポートメール | info@kema.hair |

※「bcart.jp」はBカート(BtoB EC SaaS)の共通ドメイン。当プロジェクトのショップは上記サブドメイン。

## プロジェクト構成

- `bcart-relay-server/` … 中継サーバー(Node.js/Express)。XServer VPS(162.43.49.229)でPM2常駐。
  BカートWebhook受信 → 署名検証 → APNsプッシュ送信。管理画面 `/admin` で一斉配信・退会申請管理。
- `bcart-ios-app/` … iOSアプリ「KEMA PRO SHOP」(SwiftUI)。Bundle ID: `kema.Bcartapp`。
  WKWebViewでBカートを表示 + Face ID自動ログイン + プッシュ受信。App Store公開済み(v1.0)。
- `bcart-android-app/` … Androidアプリ(Kotlin/Jetpack Compose)。パッケージ: `hair.kema.proshop`。
  プッシュはFCM(Firebase設定が必要。google-services.json は app/ に配置、リポジトリには含めない)。
- `docs/bcart-ios-app/` … 設計書・申請ガイド・告知記事HTML。

## 運用メモ

- 出荷通知: Bカートで発送状況を「発送済」にすると自動でプッシュ送信(logistics[].status === '発送済')
- 会員の識別キー: customer_id と customer_email の両方で端末照合
- サーバー反映手順: `ssh xserver` → `cd ~/kemashop/bcart-relay-server && git pull && pm2 restart bcart-relay`
- iOSアプリはXcodeがリポジトリのファイルを「参照」しているため、Mac側は `cd ~/kemashop && git pull` → Xcodeで再ビルドのみ

## 注意

- この開発環境(Claude Codeクラウド)からは kema.i17.bcart.jp へ直接アクセス不可(ネットワークポリシー制限)。
  Bカート管理画面の操作はユーザーに依頼すること。
- シークレット類(.env / APNs .p8 / トークン)はリポジトリに含めない。
