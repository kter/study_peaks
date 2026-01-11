# プロジェクト：Flutterによるバーチャル自習室アプリ「Global Study Peaks」

## 1. 概要
世界中のユーザーが仮想の「座席」に座り、互いの気配を感じながら自習に励むFlutterアプリの開発。直接のチャット機能は持たず、視覚的なプレゼンス（他人の勉強時間や一言メッセージ）のみでモチベーションを高め合う。

## 2. 技術スタック・インフラ制約
- **Frontend:** Flutter (Android優先、将来的にiOS)
- **Design Style:** クリーン＆シンプル（白、ライトグレー、アクセントのネイビー）
- **Backend API:** Google Cloud Run (REST API)
- **Database:** Google Cloud Firestore (Native Mode)
- **Auth:** Google Cloud Identity Platform
- **Infrastructure:** すべてTerraformで構築・管理（Firebase SDK/コンソールは使用不可）

## 3. 主要な画面・機能仕様
### A. ルームと座席UI
- ルーム名は世界の名峰（Everest, Fuji, Matterhorn等）を冠し、1ルーム50〜100席。
- 座席はGridViewによるシアター（映画館）形式のレイアウト。
- **座席コンポーネント:**
  - **ユーザーアイコン:** flutter_identicon等を使用した幾何学模様の自動生成。
  - **国旗バッジ:** アイコンの右下隅にオーバーレイ表示。
  - **ステータス表示:** アイコンの隣に「ユーザー名」「一言メッセージ」「現在の継続学習時間」を表示。

### B. 学習管理ロジック
- **タイマー:** 通常タイマーとポモドーロ（集中25分/休憩5分）の切り替え。
- **Android常駐通知:** Foreground Serviceを利用し、アプリを閉じても「着席中」であることと「経過時間」を通知欄に表示。
- **最適化:** バッテリー保護のため、Firestoreへの学習時間更新は「5分に1回」または「退席時」のみAPI経由で行う。

### C. 着席・退出管理
- ユーザーが明示的に「退席」を押すまで着席を維持。
- サーバーサイド（Cloud Scheduler + Cloud Run）で24時間更新がないセッションを強制終了（自動退席）させる。

## 4. 依頼内容（フェーズ1）
まずは以下の実装から始めてください：
1. **データモデル設計:** `rooms`, `seats`, `users` のFirestoreスキーマ設計案の提示。特に5分おきの更新と24時間自動退席を判定するためのタイムスタンプ（Server Timestamp）の持たせ方を考慮してください。
2. **座席Widgetの実装:** Identicon、国旗バッジ（Stack利用）、テキスト情報を含む、1つの座席を表示するFlutter Widgetのコード。
3. **Terraform構成案:** Cloud Run, Firestore Native Mode, Identity Platformを定義するHCLコードの基本テンプレート。
4. **APIエンドポイント定義:** `/sit` (着席), `/sync` (5分更新), `/leave` (退席), `/rooms` (一覧取得) のIF定義。
