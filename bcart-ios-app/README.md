# Bカート iOSアプリ(PoC)

Bカートを **WKWebView** で包み、**Face ID/Touch ID 解錠** と **APNs プッシュ通知** を追加した最小アプリです。
中継サーバー(`../bcart-relay-server`)と連携して「Bカート→中継→iPhone」のプッシュを実現します。

## 構成

```
BcartApp/
├── BcartApp.swift          @main エントリ + アプリ状態(AppState)
├── AppDelegate.swift       APNs登録・通知ハンドリング
├── AppConfig.swift         BカートURL・中継サーバーURL等の設定 ← 要編集
├── RootView.swift          ロック画面 + WebView の切替
├── BcartWebView.swift      WKWebView(Cookie保持/email捕捉/ディープリンク)
├── BiometricGate.swift     Face ID / Touch ID 解錠
├── KeychainStore.swift     会員キー(email)の安全な保存
└── DeviceRegistration.swift 中継サーバーへ端末登録
```

## 動作の流れ

1. アプリ起動 → **Face ID で解錠**(方式A: パスワードは保存せず、アプリのロックのみ)
2. WebView が Bカートを表示。初回はユーザーが手動ログイン+**「ログイン状態を保存する」にチェック**
3. ログイン時、フォームの**メールアドレスを捕捉** → 会員キーとして Keychain に保存
4. APNsデバイストークン取得済みなら、中継サーバーの `/devices/register` へ **「email + デバイストークン」を登録**
5. 以降、Bカートで受注/出荷が発生 → 中継サーバーが該当端末へプッシュ
6. 通知タップ → WebView が注文履歴ページへ遷移
7. 2回目以降は Cookie が残っているため、Face ID 解錠だけでログイン済み画面が開く

> 会員の識別は **email** を採用(ログインフォームから確実に取得できるため)。中継サーバーは Webhook の `customer_email` と `customer_id` の両方で端末を照合します。

---

## Xcode プロジェクトの作り方

このフォルダにはソースのみを置いています。`.xcodeproj` は各自の環境で作成してください。

1. Xcode → **Create New Project** → iOS → **App**
   - Interface: **SwiftUI** / Language: **Swift**
   - Product Name: `BcartApp` / Bundle ID: 例 `jp.kemashop.bcart`
2. 生成された雛形の `ContentView.swift` と `xxxApp.swift` を削除し、`BcartApp/` 内の `.swift` を全てプロジェクトに追加(Add Files to…)
3. `AppConfig.swift` を編集:
   - `bcartURL` … あなたのBカート店舗URL
   - `relayBaseURL` … 中継サーバー(XServer VPS)のURL
   - `KeychainStore.service` の `jp.example.bcart` を実際の Bundle ID に合わせる

### 必要な Capability / 権限

**Signing & Capabilities** で以下を追加:
- **Push Notifications**(`aps-environment` エンタイトルメントが付く)
- **Background Modes** → **Remote notifications** にチェック

**Info.plist** に以下を追加:
```xml
<key>NSFaceIDUsageDescription</key>
<string>ログインを保護するために Face ID を使用します</string>
```

> ATS(App Transport Security)は HTTPS のみで動くため、Bカートも中継サーバーも **https** であれば追加設定は不要です。

### APNs キーの準備(中継サーバー側で使用)
Apple Developer → Keys で **APNs用 .p8 キー** を発行し、Key ID / Team ID / Bundle ID とともに中継サーバーの `.env` に設定します(`../bcart-relay-server/README.md` 参照)。

---

## 通しテスト手順

1. 中継サーバーを起動(`../bcart-relay-server`、APNs設定済み)
2. アプリを**実機**で起動(プッシュはシミュレータ不可)→ Face ID 解錠 → Bカートにログイン(「ログイン状態を保存する」ON)
3. 中継サーバーのログに端末登録(`/devices/register`)が出ることを確認
4. Bカートでテスト受注のステータスを「発送済」に更新 → Webhook発火 → **iPhoneに「出荷しました」通知**が届けば成功

---

## このPoCで残している調整ポイント

- `BcartWebView.captureJS`: 実際のログインフォームのフィールド名に合わせて精緻化(現状は input[type=email] / name に "mail" を含む入力を汎用的に検出)
- `AppConfig.loggedInPathHints`: ログイン後URLの実パスに合わせて調整
- 通知タップ後の遷移先URL(`/order/history`)を実際の注文履歴パスに合わせる
- App Store審査用に、アプリアイコン・スクリーンショット・プライバシー情報を別途用意

---

## ロゴ画像の追加(新しいウェルカム画面用)

ウェルカム画面(アイボリー・ミニマル)は公式ロゴ `Image("kema-logo")` を使います。Mac側で次の手順を行ってください。

1. `cd ~/kemashop && git pull`
2. Xcode で `Assets.xcassets` を開く
3. リポジトリの `bcart-ios-app/BcartApp/Resources/kema-logo.imageset` フォルダを `Assets.xcassets` にドラッグ
   (または、名前をちょうど `kema-logo` にした Image Set を作成し、`@2x` / `@3x` の PNG を入れる)
4. セット名が `kema-logo` であることを確認(コードの `Image("kema-logo")` と一致が必要)
5. ビルドして実行

既存の `logo` セットがある場合はそのままで構いません(新コードでは使用しません)。

---

## ロック・WebView・セキュリティ仕様(fix/ios-webview)

### ロックのオーバーレイ動作
- Welcome を抜けた後(`.web` / `.locked`)は WebView と下部バーを**常にマウント**し、`LockView` はその上に重ねるオーバーレイです。
  バックグラウンド移行でロックしても WebView は破棄されないため、カートやフォームの入力状態が保たれます(ログアウトで Welcome に戻ったときのみ破棄)。
- ロック時は設定シート/ダウンロードのプレビューも閉じ、ロック中はWebViewへのタップを無効化します。
- 通知タップ/下部バーの遷移先は `AppState.pendingPath` に保持し、**解錠後に1度だけ**開きます。
  許可するのは相対パスか、ホストが `kema.i17.bcart.jp` と完全一致する URL のみ(`AppConfig.shopURL(from:)` に一本化)。
- WebView内の遷移は店舗ホストのみ。他ホストの http(s) は Safari で開きます。
- 認証情報は送信時に一時保持するだけで、`/mypage` 系ページ(`AppConfig.loggedInPathHints`)へ到達してから Keychain に保存・端末登録します。
  ログイン失敗(ログイン画面に留まる)では保存せず、既存の認証情報も上書きしません。
- PDF/添付ファイルは `WKDownload` で一時フォルダに保存し、QuickLook でプレビューします(閉じると削除)。

### `AppConfig.appRegisterSecret`
中継サーバーの環境変数 `APP_REGISTER_SECRET` と**完全に一致**させてください。空文字のままなら `X-App-Token` を送らず、
サーバー側が `ALLOW_LEGACY_DEVICE_REGISTER=true` の間のみ動作します。実値はリポジトリにコミットしないこと。
端末登録解除(`POST /devices/unregister`)はログアウト時と退会申請時に呼ばれます。

### Mac実機テスト チェックリスト
- [ ] カートに商品を入れてバックグラウンド → 復帰して Face ID 解錠 → カート/ページが残っている
- [ ] ロック中に通知が届き、タップ → Face ID 解錠後に該当ページが開く(解錠前は開かない)
- [ ] 外部リンク(他ホスト)を踏むと Safari が開き、アプリ内には留まらない
- [ ] 誤ったパスワードでログイン → Keychain に保存されない(再起動後も以前の認証情報のまま)
- [ ] 正しいログイン → マイページ到達後に保存され、次回から自動ログインできる
- [ ] PDF / 添付ファイルのリンク → QuickLook でプレビュー・共有できる(失敗時はアラート)
- [ ] 設定 → ログアウトで `/devices/unregister` が呼ばれ、Welcome に戻る
- [ ] 退会申請 → 「申請を受け付けました」→ OK で Welcome に戻り、Keychain/Cookie が消えている
