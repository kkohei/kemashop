# iPhone Duo 対応ガイド(KEMA PRO SHOP)

作成日: 2026-10-24
対象: iPhone Duo(2026-10-23発売、外側5.4インチ/内側7.6インチの折りたたみ)

## 結論

アプリのコードはすでにDuo対応要件を満たしている(サイズ決め打ち・画面向き判定・
デバイス種別判定なし)。必要なのは **Xcode 27.1でのリビルドとテストのみ**。

SDKごとの見え方(Apple公式):

| ビルドSDK | iPhone Duoでの表示 |
|-----------|-------------------|
| iOS 26以前 | 中央に小さく表示(余白だらけ) |
| iOS 27 | 内側ディスプレイの大部分を使用 |
| **iOS 27.1以降** | **端から端まで最適表示(推奨)** |

## Mac側の作業手順

1. **Xcodeを27.1以降に更新**(App Store または developer.apple.com)
2. `cd ~/kemashop && git pull`
3. Xcodeでプロジェクトを開き、そのままビルド(iOS 27.1 SDKでビルドされる)
4. **Info.plistの確認**: `UIRequiresFullScreen`(フルスクリーンを必要とする)が
   もし `YES` になっていたら削除または `NO` に(リサイズを妨げるため)
5. **iPhone Duoシミュレータでテスト**(Xcode 27.1に付属):
   - 外側ディスプレイ(5.4インチ)でログイン〜注文の一連操作
   - 内側ディスプレイ(7.6インチ)で同様に確認
   - **操作の途中で折りたたみ/展開**(セッション中のリサイズでWebViewと
     Welcome画面が崩れないこと)
   - Welcome画面(ゴールド背景)・ロック画面・下部バー・設定シートの表示確認
6. 実機があれば iPhone Mirroring(macOS 27)でウィンドウを極端にリサイズして確認

## App Store Connect側(任意・推奨)

- **iPhone Duo用スクリーンショットを追加登録** → プロダクトページに
  「iPhone Duoに最適化」バッジが付く
- 提出中の v1.02 に間に合うならそのビルドを27.1 SDKでアップロードし直すのが効率的

## このアプリが追加対応不要な理由(確認済み)

- `UIScreen.main.bounds` 不使用(レイアウトはすべてSwiftUIの自動サイズ)
- 画面向き(orientation)による分岐なし
- `userInterfaceIdiom`(iPhone/iPad判定)による分岐なし
- サイズ決め打ち(`bounds.height == 844` 等)なし
- WKWebViewは親ビューいっぱいに追従、Bカートはレスポンシブサイト
- Welcome画面のMeshGradient背景は任意サイズに追従
