# ECMAP Flutter アプリ セットアップ手順

## 動作環境
- Flutter SDK 3.3.0 以上
- iOS: macOS + Xcode 15 以上
- Windows: Windows 10 以上

---

## 手順

### 1. Flutter プロジェクトを作成（ローカルマシンで実行）

```bash
flutter create ecmap_flutter --platforms ios,windows
cd ecmap_flutter
```

### 2. このリポジトリの `ecmap_app/` の中身をコピー

```bash
# lib/ を置き換え
rm -rf lib
cp -r /path/to/ecmap_repo/ecmap_app/lib ./lib

# pubspec.yaml を置き換え
cp /path/to/ecmap_repo/ecmap_app/pubspec.yaml ./pubspec.yaml

# analysis_options.yaml を置き換え
cp /path/to/ecmap_repo/ecmap_app/analysis_options.yaml ./analysis_options.yaml
```

### 3. Firebase 設定を生成

```bash
# Firebase CLI をインストール（未インストールの場合）
npm install -g firebase-tools
firebase login

# FlutterFire CLI をインストール
dart pub global activate flutterfire_cli

# 既存の Firebase プロジェクトで設定ファイルを自動生成
flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID
```

→ `lib/firebase_options.dart` が自動生成されます（既存ファイルを上書き）。

### 4. パッケージをインストール

```bash
flutter pub get
```

### 5. iOS 追加設定

1. `ios/Runner.xcworkspace` を Xcode で開く
2. Bundle ID を Firebase コンソールの iOS アプリと一致させる
3. `GoogleService-Info.plist` が `ios/Runner/` に存在することを確認

Google ログインを有効にするには、Xcode で URL スキームを追加：
- `Info.plist` に `REVERSED_CLIENT_ID`（GoogleService-Info.plist から取得）を追加

### 6. Windows 追加設定

Firebase コンソール → プロジェクト設定 → ウェブアプリを追加し、
`flutterfire configure` で Windows 向け設定が生成されます。

> ⚠️ Windows では `google_sign_in` が非対応のため、メール/パスワード認証のみ利用可能です。

### 7. 実行

```bash
# iOS シミュレーター
flutter run -d ios

# Windows
flutter run -d windows
```

---

## ファイル構成

```
lib/
  main.dart               # エントリーポイント・認証ルーティング
  theme.dart              # ダークテーマ定義
  firebase_options.dart   # Firebase 設定（flutterfire configure で生成）
  models/
    score_result.dart     # Firestore ドキュメントのモデル
  services/
    auth_service.dart     # Firebase Auth 操作
    score_service.dart    # Firestore スコア保存・取得
  screens/
    login_screen.dart     # ログイン・新規登録画面
    home_screen.dart      # ダッシュボード画面
    nback_screen.dart     # N-Back ゲーム画面（完全実装）
  widgets/
    score_chart.dart      # スコア推移グラフ（fl_chart）
```

## Firestore セキュリティルール（推奨）

Firebase コンソール → Firestore → ルールに以下を設定：

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /results/{doc} {
      allow read, write: if request.auth != null
        && request.auth.uid == resource.data.userId;
      allow create: if request.auth != null
        && request.auth.uid == request.resource.data.userId;
    }
  }
}
```
