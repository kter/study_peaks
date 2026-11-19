# Study Peaks

グローバル対応のバーチャル自習室アプリ。世界中のユーザーと一緒に勉強できます。

## 技術スタック

- **Frontend**: Flutter (Android/iOS)
- **Backend**: Go (Cloud Run)
- **Database**: Firestore
- **Infrastructure**: Terraform

## セットアップ

### 1. 依存関係のインストール

```bash
# Flutter依存関係
make flutter-get

# Go依存関係
make api-tidy
```

### 2. ローカル開発

```bash
# Flutterアプリ（開発版）を実行
make flutter-run

# APIをローカルで実行
make api-run
```

### 3. Androidの開発・本番環境の切り替え

`dev` は開発用APIとFirebaseプロジェクト `studypeaks-dev`、`prd` は本番用APIとFirebaseプロジェクト `studypeaks-prd` に接続します。各FirebaseプロジェクトのAndroid設定ファイルを次の場所に配置してください（Git管理対象外）。

| flavor | applicationId | Firebase設定ファイル |
| --- | --- | --- |
| `dev` | `com.studypeaks.app.dev` | `android/app/src/dev/google-services.json` |
| `prd` | `com.studypeaks.app` | `android/app/src/prd/google-services.json` |

設定ファイルは各applicationIdに対応するものを使ってください。開発版は「Study Peaks Dev」と表示され、本番版と同時にインストールできます。

```bash
make flutter-run           # 開発版（flutter-run-devの別名）
make flutter-run-dev       # flutter run --flavor dev
make flutter-run-prd       # flutter run --flavor prd
make flutter-build-apk-dev # 開発版のdebug APK
make flutter-build-apk     # 本番版のrelease APK
make flutter-build-aab     # 本番版のrelease App Bundle
```

Flutterコマンドを直接実行する場合も、`--flavor dev` または `--flavor prd` を指定してください。

GitHub ActionsでAndroidのAPKを作るには、本番用の `google-services.json` の内容をリポジトリのシークレット `GOOGLE_SERVICES_PRD_JSON` に登録してください。設定されている場合のみ `prd` のdebug APKをビルドし、アーティファクトに保存します。

## デプロイ

### ⚠️ 重要: APIデプロイについて

APIのデプロイは**必ず `make api-deploy`（本番）または `make api-deploy-dev`（開発）を使用**してください。

```bash
# 本番環境へデプロイ（ビルド + プッシュ + Terraform適用）
make api-deploy

# 開発環境へデプロイ（ビルド + プッシュ + Terraform適用）
make api-deploy-dev
```

**注意**: `terraform apply` を単独で実行しないでください。APIイメージのタグは `Makefile` で一元管理されています。

### APIタグのバージョンアップ

新しいバージョンをデプロイする場合：

1. `Makefile` の `API_TAG` を更新（例: v6 → v7）
2. `make api-deploy` を実行

### Terraform（インフラのみ）

APIイメージ以外のインフラ変更の場合：

```bash
# 開発環境
make tf-dev-plan
make tf-dev-apply

# 本番環境（APIイメージ指定が必要）
cd terraform
terraform workspace select prd
terraform plan -var-file="env/prd.tfvars" -var="api_image=..."
```

## テスト

```bash
# 全テスト実行
make flutter-test

# Goldenテスト除外（高速）
make flutter-test-fast

# Goldenテスト更新
make flutter-test-golden
```

## プロジェクト構成

```
study_peaks/
├── lib/                    # Flutterアプリ
│   ├── config/             # 設定
│   ├── models/             # データモデル
│   ├── providers/          # 状態管理
│   ├── screens/            # 画面
│   ├── services/           # APIサービス
│   └── widgets/            # UIコンポーネント
├── api/                    # Go APIサーバー
│   ├── main.go             # メインエントリポイント
│   └── cmd/seed/           # Firestoreシードスクリプト
├── terraform/              # インフラ定義
│   └── env/                # 環境別設定
└── test/                   # テスト
```
