---
name: study-peaks-test
description: Study Peaks アプリの動作確認・テストの手順。「動作確認して」「テストして」「全機能を試して」「修正後に確認して」など、このリポジトリのアプリやAPIを検証するときは必ず使う。静的チェック、dev flavor のビルド、エミュレーター操作、dev API での実データ確認、報告までを含む。
---

# Study Peaks 動作確認

このアプリ（Flutter / Android、Go API on Cloud Run）を検証する手順。上から順に進め、各ステップの完了条件を満たしてから次へ進む。画面操作の詳細は [SCENARIOS.md](SCENARIOS.md) にある。

## 守ること

- 書き込みを伴う操作（着席・退席・タイマー・サインイン・プロフィール変更）は **dev flavor（`com.studypeaks.app.dev`）と dev API だけ**で行う。prd に対しては GET で見るだけにする。
- dev へのデプロイ（`terraform apply`）や GCP の設定変更は、plan を見せてユーザーの承認を得てから行う。
- ユーザーの未コミット変更、特に `pubspec.yaml` / `pubspec.lock` を壊さない。`flutter pub get` や `flutter build`（内部で pub get が走る）の前に `pubspec.lock` を scratchpad に退避し、終わったら差分を確認して戻す（Flutter のバージョン差で SDK 固定パッケージが書き換わる）。

## 1. 環境を用意する

```sh
export PATH="$HOME/development/flutter/bin:$PATH"   # Flutter 3.35.7（PATH に入っていない）
gcloud config configurations activate studypeaks-dev
```

- JDK は `flutter config` の `jdk-dir`（mise の temurin-17）で設定済み。Java 25 では Gradle 8.12 が動かない。
- Flutter を新しくしない。3.50 系は Gradle 9.3.1 以上を要求し、移行ツールが `analysis_options.yaml` などを書き換える。
- エミュレーターは `android-emulator-start` スキルで起動する（AVD `Pixel_10a`、serial は通常 `emulator-5554`、mobile-mcp の device id は `Pixel_10a`）。

完了条件：エミュレーターが `ready`、かつ下のネットワーク確認が通る。

### エミュレーターのネットワーク確認

```sh
adb -s emulator-5554 shell ping -c5 -W3 8.8.8.8 | tail -1
```

平均がおおむね 150ms 以下なら次へ進む。ホストのスリープ後などで遅い・不達のときは、順に試す。

1. `svc wifi disable; svc data disable` → `enable` で切り替え直す
2. 直らなければ `adb -s emulator-5554 emu kill` してスキルで再起動する（ゲストの `adb reboot` では直らなかった）

ネットワークが壊れたまま確認すると、アプリの不具合と見分けがつかなくなる。

## 2. 静的チェックとユニットテスト

```sh
flutter analyze --no-pub          # 件数を変更前と比べる（既存の指摘が残っている。増えていなければよい）
flutter test --no-pub --exclude-tags golden
(cd api && "$(mise where go)/bin/go" vet ./... && "$(mise where go)/bin/go" test ./...)   # API を変えたとき
```

ARB を変えたら先に `flutter gen-l10n` を実行する（生成物 `lib/l10n/app_localizations*.dart` はコミット対象）。

完了条件：テストが全件成功し、analyze の件数が増えていない。

## 3. ビルドしてインストールする

```sh
flutter build apk --debug --flavor dev
adb -s emulator-5554 install -r -d build/app/outputs/flutter-apk/app-dev-debug.apk
```

- `-d` を付ける。ユーザーの作業ツリーと HEAD で versionCode が違い、ダウングレード扱いで失敗することがある。
- dev 版は `google-services.json` を `android/app/src/dev/` から読む。ないとビルドが `No matching client found for package name 'com.studypeaks.app.dev'` で止まる。

完了条件：`Success` が出る。

## 4. dev API が生きているか確かめる

```sh
DEV=https://study-peaks-api-dev-opjqzrfbbq-an.a.run.app
curl -s -o /dev/null -w "%{http_code}\n" $DEV/health
for r in denali everest fuji kilimanjaro; do curl -s -o /dev/null -w "$r %{http_code}\n" $DEV/v1/rooms/$r/seats; done
```

500 のときは Cloud Run のログでパニックを探す（SCENARIOS.md の「確認の道具」）。

完了条件：すべて 200。

## 5. シナリオを実行する

[SCENARIOS.md](SCENARIOS.md) の該当シナリオを実行する。「全機能」「フル機能」なら全シナリオ、修正の確認なら修正に関わるシナリオと、その周辺（着席→退席の往復）を必ず含める。

各シナリオは**画面とサーバーの両方**で確かめる。debug ビルドは API 失敗時にモックデータへ切り替わるので（`kUseMockData` が既定で true）、画面にデータが出ていても実データとは限らない。Cloud Run のログに `Dart/` の User-Agent のリクエストが来ているか、座席 API の中身が画面と一致するかで判断する。

完了条件：対象の全シナリオで、期待結果を画面とサーバーの両方で確認した。確認できなかったものは理由を記録した。

## 6. 後片付けと報告

- 席を立った状態に戻す（座席 API で `occupied: []`）。
- 表示名・国・テーマなど、変えた設定を元に戻す。サインイン状態もテスト前に戻す。
- 報告は日本語で、次をまとめる：シナリオごとの結果の表、見つかった不具合（再現手順・根拠・該当コード）、確認できなかった項目とその理由、環境で変えたこと。
