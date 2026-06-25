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
