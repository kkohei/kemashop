# KEMA PRO SHOP — Androidアプリ

iOS版と同機能のAndroidアプリ(Kotlin / Jetpack Compose)。

```
Welcome画面(ゴールドの流れる背景 + ログイン/新規登録)
 → 生体認証(指紋/顔)でロック解除
 → WebViewでBカート表示(自動ログイン・フォーム最適化)
 → 下部バー: ホーム/ログイン/新規登録/注文履歴/設定
 → 設定: ログアウト / 退会申請
 → FCMプッシュ受信(出荷通知・一斉配信)・通知タップでページ遷移
```

## iOS版との違い(重要)

| 項目 | iOS | Android |
|------|-----|---------|
| プッシュ通知 | APNs | **FCM(Firebase)** ← 追加設定が必要 |
| 生体認証 | Face ID | 指紋/顔(BiometricPrompt) |
| 認証情報保存 | Keychain | EncryptedSharedPreferences(Keystore) |

中継サーバーは**両対応済み**: 端末登録時の `platform` によって APNs / FCM に自動振り分けされます。

---

## セットアップ手順

### 1. Firebaseプロジェクトを作成(FCMに必須)

1. https://console.firebase.google.com → 「プロジェクトを追加」(名前: kema-pro-shop など)
2. プロジェクト内で「Androidアプリを追加」
   - パッケージ名: **`hair.kema.proshop`**(app/build.gradle.kts の applicationId と一致させること)
3. **`google-services.json` をダウンロード** → このリポジトリの **`bcart-android-app/app/`** に置く
   (このファイルが無いとビルドできません)

### 2. 中継サーバーにFCM鍵を設定

1. Firebaseコンソール → プロジェクト設定 → **サービスアカウント** → 「新しい秘密鍵の生成」
   → JSONファイルがダウンロードされる
2. サーバーへ転送して設定:
   ```bash
   # Mac側
   scp ~/Downloads/xxxx-firebase-adminsdk-xxxx.json xserver:~/kemashop/bcart-relay-server/secrets/fcm-service-account.json
   # サーバー側
   ssh xserver
   cd ~/kemashop/bcart-relay-server
   git pull
   echo "FCM_SERVICE_ACCOUNT_PATH=./secrets/fcm-service-account.json" >> .env
   pm2 restart bcart-relay
   ```

### 3. Android Studioでビルド

1. Android Studio(最新版)をインストール: https://developer.android.com/studio
2. 「Open」で **`bcart-android-app` フォルダ**を開く(リポジトリのルートではない)
3. 初回はGradle同期が自動で走る(数分)
4. 実機をUSB接続(端末側で「開発者向けオプション → USBデバッグ」をON)
5. ▶ Run でインストール

### 4. 動作確認

1. アプリ起動 → Welcome画面(ゴールド) → ログイン
2. 通知を許可
3. 中継サーバーで端末登録を確認:
   ```bash
   ssh xserver
   cd ~/kemashop/bcart-relay-server && node check-devices.mjs
   ```
   → platform が `android` の行が増えていればOK
4. 管理画面(https://relay.kema.hair/admin)から一斉配信 → Android端末に届けば完成

---

## Google Playでの公開(リリース時)

1. **Google Play デベロッパーアカウント**(初回のみ $25): https://play.google.com/console
2. 署名付きAABを作成: Android Studio → Build → Generate Signed App Bundle
   (キーストアを新規作成 → **必ずバックアップ**。紛失すると更新不能)
3. Play Consoleでアプリ作成 → ストア情報(iOS版の文言・スクショを流用可)
   - プライバシーポリシー: https://kema.i17.bcart.jp/privacy.php
   - アカウント削除: アプリ内「設定 → 退会申請」+ 申告フォームに記載
4. 審査提出(通常1〜3日。Appleより緩めだが初回は時間がかかることあり)

## ファイル構成

```
app/src/main/java/hair/kema/proshop/
├── AppConfig.kt        設定(URL等)
├── MainActivity.kt     画面全体(Welcome/ロック/WebView/下部バー/設定)
├── BcartWeb.kt         WebView(JS注入・自動ログイン・email捕捉)
├── CredentialStore.kt  認証情報の暗号化保存
├── Api.kt              中継サーバー通信(端末登録・退会申請)
└── PushService.kt      FCM受信・通知表示
```
