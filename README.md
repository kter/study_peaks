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
# Flutterアプリを実行
make flutter-run

# APIをローカルで実行
make api-run
```

## デプロイ

### ⚠️ 重要: APIデプロイについて

APIのデプロイは**必ず `make api-deploy` を使用**してください。

```bash
# 本番環境へデプロイ（ビルド + プッシュ + Terraform適用）
make api-deploy
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
