# 動作確認シナリオ

[SKILL.md](SKILL.md) のステップ5から参照する。各シナリオは「操作 → 画面で見ること → サーバーで見ること」の順に書いてある。

## 画面操作のこつ

- 要素は `mobile_list_elements_on_screen` の ref で押す。座標は画面の状態で変わる（サインイン中と未サインインで設定画面の配置が違う）。
- システムのダイアログ（通知の許可など）はスクリーンショットに写らないことがある。画面が変わらないときは要素一覧で確かめる。
- 画面遷移のアニメーション中に撮ると重なった画像になる。2〜3秒待ってから撮る。
- 座標で押すときの目安（Pixel_10a、1080×2424、ライトテーマ）：

| 対象 | 座標 |
|---|---|
| ホーム右上のアバター（設定へ） | 1017, 216 |
| Mt. Fuji の Join | 408, 1460 |
| 座席 #6 | 412, 1305 |
| 着席・退席ダイアログの確定ボタン | 768, 1398（Sit Down）／ 827, 1398（Leave） |
| タイマーの再生・一時停止 | 793, 412 |
| タイマーの展開（∨） | 939, 412 |
| 展開後の Pomodoro / 再生 | 686, 561 ／ 546, 1278 |
| Leave Seat | 810, 634（タイマーを展開中は 807, 1630） |
| ルーム情報（i） | 1015, 215 |

## 確認の道具

```sh
DEV=https://study-peaks-api-dev-opjqzrfbbq-an.a.run.app
# 座席の実データ
curl -s $DEV/v1/rooms/fuji/seats | python3 -c "import sys,json;d=json.load(sys.stdin);[print(s['seatNumber'],s['user']['displayName'],s['user']['countryCode'],s['user']['userId']) for s in d['seats'] if s['isOccupied']]"
# ルームの人数
curl -s $DEV/v1/rooms | python3 -c "import sys,json;[print(r['roomId'],r['currentOccupancy']) for r in json.load(sys.stdin)['rooms']]"
# アプリから届いたリクエスト（User-Agent が Dart/）
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="study-peaks-api-dev" AND httpRequest.userAgent:"Dart"' --project=studypeaks-dev --freshness=5m --limit=10 --format='value(timestamp,httpRequest.requestMethod,httpRequest.requestUrl,httpRequest.status)'
# API のパニックやエラー（時刻は直前のリクエストに合わせる）
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="study-peaks-api-dev" AND timestamp>="<UTC時刻>"' --project=studypeaks-dev --limit=80 --order=asc --format='value(textPayload)'
# 端末に保存されたセッションとタイマーの状態（タイマーの sessionId がセッションと一致しているか）
adb -s emulator-5554 shell run-as com.studypeaks.app.dev cat shared_prefs/FlutterSharedPreferences.xml | grep -oE "persisted_(session_id|timer_state)[^<]*" | sed 's/&quot;/"/g'
# アプリのログ
adb -s emulator-5554 logcat -d -s flutter | tail -20
# フォアグラウンドサービスの通知
adb -s emulator-5554 shell dumpsys notification --noredact | grep -A3 "pkg=com.studypeaks.app.dev"
```

## S1. 起動とルーム一覧

- 操作：アプリを起動する。
- 画面：ルームが4件（Denali、Mt. Everest、Mt. Fuji、Mt. Kilimanjaro）表示され、人数が dev の実データと一致する。
- サーバー：`GET /v1/rooms` が `Dart/` から 200。

## S2. 座席マップ

- 操作：Mt. Fuji の Join を押す。
- 画面：50席が並び、「N studying」が実データと一致する。
- サーバー：`GET /v1/rooms/fuji/seats` が 200。500 ならモックに切り替わっているので、ログでパニックを確認する。

## S3. 着席

- 操作：空席を押し、Sit Down。初回は通知の許可ダイアログが出るので Allow。
- 画面：自分の席に名前と国旗、タイマーが動き出す、Leave Seat が押せる。
- サーバー：`POST /sit` が 200、座席 API にその席が載る。通知（`study_peaks_session`、ONGOING）が出ている。

## S4. タイマー

- 操作：一時停止 → 展開して Pomodoro に切り替え → 再生。
- 画面：一時停止で止まる。Pomodoro は Focus Time 25:00 から減る。
- 注意：動作中はモードを切り替えられない。先に一時停止する。

## S5. プロセス強制終了からの復元

- 操作：Pomodoro を動かしたまま `adb shell run-as com.studypeaks.app.dev kill -9 <pid>` し、ランチャーから起動し直す（最近使ったアプリの画面はエミュレーターで開かないことがある）。
- 画面：Mt. Fuji の座席マップに戻り、席に座ったまま。タイマーが Pomodoro のまま、止めていた間の時間も進んでいる。
- 端末：kill の前に、保存されたタイマー状態の `sessionId` が `persisted_session_id` と同じであること（モード切り替えのあとも）。
- ログ：`Session restored: ... in room Mt. Fuji`。

## S6. 退席と人数の同期

- 操作：Leave Seat → Leave。続けてルーム情報（i）を開き、戻ってルーム一覧を見る。
- 画面：情報シートが「Currently: 0 studying」、一覧が「0 / 50」。引っ張って更新しなくても正しい。
- サーバー：`POST /leave` が 200、座席 API が `occupied: []`、通知が消える。
- 端末：`persisted_session_id` と `persisted_timer_state` が両方消えている。

## S7. プロフィール

- 操作：設定で表示名と国を変え、もう一度着席する。
- 画面とサーバー：座席の名前と国コードが変わっている。国のリストは行間が狭いので、押したあと国旗で確かめる。
- 後片付け：退席し、表示名と国を元に戻す。

## S8. サインアウトとゲスト

- 操作：Sign Out → アイコンの再生成 → ゲストのまま着席して退席。
- 画面：「Signed out successfully」、アイコンが変わる。
- サーバー：ゲストの席の `userId` が `anon_...` であること。Google アカウントの UID が出たら、古いトークンが送られている不具合。

## S9. サインイン（Credential Manager）

- 操作：Sign in with Google → アカウントを選ぶ。
- 画面：アカウント選択に「to continue to Study Peaks Dev」と出て、「Signed in with Google」になる。
- ログ：`CredentialManager: starting executeGetCredential` が出て、`deprecated legacy Google Sign-In` が0件。`not registered to use OAuth` が出たら、debug 鍵の SHA-1 が Firebase に登録されていない（`keytool -list -v -keystore ~/.android/debug.keystore` で確かめる）。

## S10. オフライン

- 操作：アプリを止め、`svc wifi disable; svc data disable` してから起動する。
- 画面：約30秒以内にエラーカード（「Unable to connect to the internet…」）と Retry が出る。下のルームは debug のモックデータ。
- 操作：ネットワークを戻して Retry。
- 画面：実データに切り替わり、エラーカードが消える。

## S11. テーマ

- 操作：設定で Dark → ホーム・座席マップ・設定を見る → System Default に戻す。
- 画面：どの画面も暗色になり、文字が読める。

## S12. prd 版の読み取り確認（必要なときだけ）

- 操作：`flutter build apk --debug --flavor prd` を入れて起動し、一覧と座席マップを見るだけにする。着席やサインインはしない（本番データを書き換えるため）。
