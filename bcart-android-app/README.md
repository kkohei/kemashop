# KEMA PRO SHOP — Androidアプリ

iOS版と同機能のAndroidアプリ(Kotlin / Jetpack Compose)。

```
Welcome画面(アイボリー・ミニマル「デザインB」: 公式ロゴ + 黒カプセルのログイン/新規登録)
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

### 3. 中継サーバーとのトークン(APP_REGISTER_SECRET)

`AppConfig.appRegisterSecret` は中継サーバーの `APP_REGISTER_SECRET`(.env)と**必ず同じ値**にします。
リポジトリ上は空文字(実値はコミットしない)。空の間は `X-App-Token` を送りません。
設定すると端末登録・登録解除・退会申請の3リクエストに `X-App-Token` ヘッダが付きます。

### 4. Android Studioでビルド

1. Android Studio(最新版)をインストール: https://developer.android.com/studio
2. 「Open」で **`bcart-android-app` フォルダ**を開く(リポジトリのルートではない)
3. 初回はGradle同期が自動で走る(数分)。`google-services.json`(手順1)が `app/` に無いと失敗します(gitignore済みでリポジトリには含まれない)
4. 実機をUSB接続(端末側で「開発者向けオプション → USBデバッグ」をON)
5. ▶ Run でインストール

コマンドラインなら `./gradlew assembleDebug`(Gradle 8.9 ラッパー同梱。JDK 17 とAndroid SDKが必要)。

### 5. 動作確認

1. アプリ起動 → Welcome画面(アイボリー) → ログイン
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

## デザイン・ロゴ

- Welcome / ロック画面は「デザインB(アイボリー・ミニマル)」。背景は #f7f1e6 → #f3ead9 → #efe4d0 のグラデーション+上部ハイライト。
  端末がダークモードでも同じ見た目(テーマ・色を固定、強制ダークも無効)。
- ロゴは公式の黒ロゴ画像(`res/drawable-xxhdpi|xxxhdpi/kema_logo.png`、元PNGをLanczos縮小のみ)。
  **KEMA・タグライン(Advanced · Quality · Oriented)をテキストで再描画しないこと。** 「PRO SHOP」だけが小さなテキストキャプション。
- ランチャーアイコン: 公式のアダプティブアイコン素材が無いため、既存の `mipmap-xxxhdpi/ic_launcher.png` のまま(新しいマークは作っていない)。
  アダプティブアイコン(foreground/background)の公式素材が揃ったら差し替えてください。

## セキュリティ挙動

- WebViewはショップ(`kema.i17.bcart.jp` 完全一致)のみ内部表示。他ホストのhttp(s)は外部ブラウザ、`mailto:`/`tel:`/`sms:` は各アプリ、その他スキーム(`intent:` 等)は遮断。
- JS注入(自動ログイン・認証情報捕捉)はショップのページ(ホスト一致)でのみ。`KemaBridge.capture` はメインフレームがショップ以外なら無視。
- 認証情報は送信時には保存しない。メモリに最大120秒だけ保持し、ログイン画面以外のショップページ読み込み完了で初めて保存+端末登録。ログイン画面に留まれば破棄(正しい保存値を上書きしない)。
- 自動ログインはショップの `login` ページでのみ、パスワードはJSON文字列エスケープで注入。
- 通知extra・ディープリンクは「/ 始まりの相対パス」または `https://kema.i17.bcart.jp` のみ受理。
- アプリを離れる(ON_STOP)と、認証情報があれば再ロック。WebViewは破棄せずロック画面を重ねる(ロック中の通知遷移は解錠後に実行)。ファイル選択中は再ロックしない。
- 戻る: WebViewに履歴があれば戻る。なければアプリを終了せずバックグラウンドへ。
- ログアウト・退会申請(受理後)で `/devices/unregister` を呼び、認証情報とCookieを消してWelcomeへ。
- ダウンロードはショップのURLのみ DownloadManager(アプリ専用領域、ストレージ権限不要)で保存し完了後に開く。

## テストチェックリスト(実機)

- [ ] Welcome: 公式ロゴが崩れず中央、「PRO SHOP」が小さく金色、黒カプセル/細枠ボタン。端末ダークモードでも同じ配色
- [ ] ロゴの文字(KEMA・タグライン)が画像のまま(フォントで描き直されていない)
- [ ] ログイン成功 → ホームへ → アプリを他アプリへ切替して戻る → ロック画面 → 解錠でWebの状態が維持されている
- [ ] ロック中に通知を送る → タップ/受信しても解錠まで中身が見えず、解錠後に該当ページが開く
- [ ] 戻るボタン: ページ履歴があれば戻る、無ければバックグラウンドへ(アプリが即終了しない)。ロック画面でも同様
- [ ] `mailto:`/`tel:` リンクがメール/電話アプリで開く。外部サイトのリンクが外部ブラウザで開く
- [ ] `<input type=file>`(問い合わせ添付等)でファイル選択でき、選択後に再ロックされない
- [ ] 請求書等のダウンロード: 通知が出て完了後に開ける。JSのalert/confirmが表示される
- [ ] パスワードを打ち間違えてログイン失敗 → 保存済み認証情報が変わらない(再起動後も正しい資格情報で自動ログイン)
- [ ] ログアウト: 中継サーバーのログに `/devices/unregister` が来て端末が外れ、Welcomeに戻る
- [ ] 退会申請: 受理後に自動ログアウトされ、unregisterが呼ばれる(失敗時はログアウトされずエラー表示)
- [ ] `appRegisterSecret` 設定時、サーバー側で `X-App-Token` が検証される(未設定時は従来どおり動く)

## ファイル構成

```
app/src/main/java/hair/kema/proshop/
├── AppConfig.kt        設定(URL等)
├── MainActivity.kt     ルーティング・再ロック・WebView画面・下部バー・設定
├── BrandUi.kt          Welcome / ロック画面(デザインB・公式ロゴ)
├── BcartWeb.kt         WebView(遷移制限・DL・ファイル選択・JS注入・自動ログイン・認証情報の確定保存)
├── CredentialStore.kt  認証情報の暗号化保存
├── Api.kt              中継サーバー通信(端末登録・解除・退会申請)
└── PushService.kt      FCM受信・通知表示
```
