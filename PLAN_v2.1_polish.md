# StatusForecast — v2.1 / v2.2 計画書 (磨き込み + 中規模機能)

作成日: 2026-05-24
対象: v2.0 release後の追加リリース。大規模リファクタを伴わない範囲。

---

## 1. 監査で見つかった既存バグ / 未配線箇所

優先度: **B** = Bug、半完成・配線忘れ。新規実装より先に潰すべき。

| # | 場所 | 問題 | 修正案 | 工数 |
|---|---|---|---|---|
| B1 | `AppState.yahooRequestsToday` | in-memory のみ、起動毎にリセット、日付跨ぎ管理なし | `(date, count)` ペアを UserDefaults に永続化。`AppState.refresh()` で JST 日付が変われば count=0 にリセット | 0.5h |
| B2 | `Preferences.wifiOnly` | 設定 UI はあるが `RefreshCoordinator` で参照されない (完全に no-op) | `NWPathMonitor` でステータス監視、Wi-Fi 接続時のみ refresh。Cellular はスキップ | 1h |
| B3 | `DiskCache` | 古いキャッシュが永久に蓄積。バージョン管理なし。SwiftPM の `.build/` 経由じゃないユーザー領域に書くため野放し | (a) 起動時に 7 日以上古いファイル削除 (b) cache key にバージョン (`"v2:"`) を含める | 1h |
| B4 | `GeneralTab.applyLaunchAtLogin` | `SMAppService` エラーを `print()` で握りつぶす | エラー文をユーザー可視に (Toggle 下に赤字注記)。"System Settings → Login Items" へのリンク追加 | 1h |
| B5 | `MenuBarController.handleClick` | 右クリックで AXShowMenu を踏まれた時の挙動が曖昧。`event` が nil の場合 togglePopover に落ちる | 防御コードのコメント明文化 + 既存 e2e で問題ないか確認 | 0.5h |
| B6 | Popover position on multi-monitor | NSStatusItem の screen にしか出ない。マウスのある画面に出ない | macOS の挙動上正常 (status item の位置は固定) なので、これは **仕様** とする | 0h |
| B7 | `OpenMeteoClient.fetchAll` | `timezone` を Location から渡しているが、ロード時にユーザーが override すると mismatch | TimeZone 変更時は cache invalidate | 0.5h |
| B8 | NowView の `apparentBlock` | wind が nil でも `cur.windSpeedMps ?? 0` で計算。風速 0 と「データ無し」が区別されない | windSpeedMps が nil の場合は wind=0 で計算継続 (体感気温に風が支配的に効くケースは僅か)、これは **許容** | 0h |
| B9 | `WeatherCodeRef.Codable` | enum 値を JSON 化したとき `pops: [PrecipChance]` 等含めた DailyForecast 全体が Codable と言えない (Codable conformance 怪しい)。但し現状 snapshot は永続化していないので実害無し | 永続化機能を追加する時に対処 (将来の forecast キャッシュ) | 0h |
| B10 | `JMAAreaIndex.search` 重複候補 | "東京" で検索すると東京都 / 東京 (class10) / 千代田区 等が重複。dedupeはdisplayName単位 | currently OK | 0h |
| B11 | NowView ヘッダの時間表示 | `dateFormat = "MMM d, HH:mm"` だが Locale 切替で月名が ja 環境で英語混じり可能性 | `.dateTime.month().day().hour().minute()` の FormatStyle に置換 | 0.5h |

**合計 B 系工数**: ~5h

---

## 2. 既存データで実装できる小規模機能

優先度: **S** = Small。既存 API レスポンスを利用、UI 追加のみ。

| # | 機能 | 内容 | 必要 API | 工数 |
|---|---|---|---|---|
| S1 | **日の出・日の入り** | NowView ヒーロー下に "☀️ 4:30 / 🌙 18:54" を追加。Weekly カードの 8 行目にも | Open-Meteo daily `sunrise,sunset` (既に `forecast?` から取得可能だが現在 daily fields に含めていない) | 1.5h |
| S2 | **気圧トレンド** | 過去 3h vs 現在の差分で ↑/↓/→ 表示 ("1014.4 hPa ↑1.2") | AMeDAS の 1h ごと過去値スナップショット (ローカル保持) | 2h |
| S3 | **タイトル風向矢印** | 風タイルに 16 方位の方向を示す回転矢印 (`location.north.fill` を rotate) | 既存 windDirection / windDirectionDeg | 1h |
| S4 | **タップで時刻別気温詳細** | HourlyTempChart の上でマウス移動 → tooltip でその時刻の気温・天気アイコン・POP | SwiftUI `chartOverlay` + `DragGesture` | 3h |
| S5 | **昨日比** | "21°C (昨日比 +2°)" | 前日 snapshot を DiskCache から復元 | 2h |
| S6 | **JMA 詳細ページを開く** | popover 右上に "詳細を JMA で開く" リンク | URL pattern `https://www.jma.go.jp/bosai/forecast/#area_type=class20s&area_code={class20Code}` | 0.5h |
| S7 | **About ダイアログ** | バージョン、Open Source ライセンス、クレジット、コピー機能 | 既存 | 1h |
| S8 | **Keyboard ショートカット** | Cmd+R 更新、Cmd+1/2/3 タブ切替、Cmd+, 設定 (既にある) | NSEvent.localMonitor | 1.5h |
| S9 | **menu bar カラーアイコン に外気温による色変化** | < 0° 青系, > 30° 赤系 | Preferences で toggle、`IconStyle.color` 時に動的色 | 1.5h |
| S10 | **Weekly card の信頼度ラベルツールチップ** | A=高い 等の説明を help() で | UI 追加のみ | 0.5h |

**合計 S 系工数**: ~14.5h

---

## 3. 中規模機能

優先度: **M** = Medium。新 API 統合や永続化を伴う。

| # | 機能 | 内容 | 工数 |
|---|---|---|---|
| M1 | **雨開始通知** (DESIGN.md Phase 2 残置) | Yahoo nowcast の forecast samples で 0.1mm/h を初検出 → `UNUserNotificationCenter` で "30 分後に雨が降り出します"。1 日 1 回まで | 4h |
| M2 | **猛暑/寒波通知** | 当日最高/最低が閾値超え (デフォ 35° / -5°) で起動時に通知。設定で閾値編集 | 3h |
| M3 | **UV index** | Open-Meteo daily `uv_index_max` を取得し Weekly カード / Today に表示 | 1.5h |
| M4 | **空気質 (PM2.5)** | Open-Meteo air-quality API (`api.open-meteo.com/v1/air-quality`) を別 client で取得。日本は環境省そらまめ君の方が良いが unofficial。Open-Meteo で十分 | 3h |
| M5 | **JMA 防災気象情報** | `jma.go.jp/bosai/warning/data/warning/{office}.json` から警報・注意報を取得 → popover ヘッダにバナー表示 | 4h |
| M6 | **過去 24h の気温/降水履歴** | AMeDAS の `point/{station}/{stamp}.json` (1h単位 max 24h) を取得し Today タブ下に "過去 24h" タブ | 5h |
| M7 | **現在地ベース自動追加** | `CLLocationManager` で起動時に現在地取得 → 最寄り class10 を resolveFromOffice で解決 → "現在地" として登録 | 4h |
| M8 | **アイコン整備** | プロジェクト共通の app icon (.icns) を作成。SF Symbols compose で雲+太陽の合成画像 | 3h |
| M9 | **Sparkle 自動更新** | Sparkle SDK 統合、appcast.xml ホスティング先決定 (GitHub Pages?) | 6h |
| M10 | **オンボーディング** | 初回起動時にウェルカム → 言語選択 → 地点選択 → 完了 のシート表示 | 5h |

**合計 M 系工数**: ~38h

---

## 4. 類似アプリ機能比較 (参考)

調査対象: Carrot Weather, Hello Weather, macOS 標準, Tempest, Living Earth, Forecast Bar

| 機能 | Carrot | Hello | macOS 標準 | Tempest | SF v2.0 | SF 提案 |
|---|---|---|---|---|---|---|
| メニューバー気温 | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| メニューバー天気アイコン | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| 時間別気温チャート | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| 週間予報 | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| 降水ナウキャスト | ✓ | △ | ✓ | ✓ | ✓ (JP) | — |
| 日の出/日の入り | ✓ | ✓ | ✓ | ✓ | ✗ | **S1** |
| UV index | ✓ | ✓ | ✓ | ✓ | ✗ | **M3** |
| 空気質 | ✓ | ✓ | ✓ | ✓ | ✗ | **M4** |
| 雨開始通知 | ✓ | ✓ | ✓ | ✓ | ✗ | **M1** |
| 警報・注意報 | ✓ | ✓ | ✓ | ✓ | ✗ | **M5** |
| 体感温度 | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| 気圧トレンド | ✓ | ✗ | ✗ | ✓ | ✗ | **S2** |
| 風コンパス | ✓ | ✓ | ✓ | ✓ | ✗ | **S3** |
| 月相 | ✓ | ✗ | ✗ | ✓ | ✗ | (見送り) |
| 多地点切替 | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| 言語切替 | ✓ | ✓ | (system) | ✓ | ✓ | — |
| 自動更新 | ✓ | ✓ | ✓ | ✓ | ✗ | **M9** |
| ショートカット | ✓ | ✗ | ✗ | ✓ | ✗ | **S8** |

**StatusForecast の差別化**: 日本特化 (JMA / AMeDAS / Yahoo の同時利用)、無料、Mac ネイティブ、メニューバー専有。Carrot/Hello は$5-15で多機能だが日本データの粒度では劣る。

---

## 5. 推奨実装順序

### v2.1 (短期 / 1 週間以内): バグ修正 + 既存データ機能

**Phase A**: B1, B2, B3, B4, B11 — 半完成箇所を完成
**Phase B**: S1 (日の出日の入り), S6 (JMA リンク), S7 (About), S8 (ショートカット)

工数合計: ~10h

### v2.2 (中期 / 2-3 週間): 通知 + UV + 警報

**Phase C**: M1 (雨通知)
**Phase D**: M3 (UV), M5 (警報)
**Phase E**: S2 (気圧), S3 (風コンパス), S4 (チャート tooltip)

工数合計: ~14h

### v2.3 (長期 / 1 ヶ月+): 自動更新 + オンボーディング + 現在地

**Phase F**: M9 (Sparkle), M10 (オンボーディング)
**Phase G**: M7 (現在地), M8 (アイコン)
**Phase H**: M4 (空気質), M6 (過去24h)

工数合計: ~25h

---

## 6. 着手の判断材料

優先するべき視点:
- **Daily friction の最大化を狙う**: 通知 (M1)・気圧トレンド (S2) は毎日の意思決定に直結。一方 UV/空気質は日本ユーザー需要が低い (Carrot Weather 国内レビュー参照)
- **完成度を上げる**: B1-B5 のバグは目立たないが見つけたユーザーの信頼を損なう。先に潰す
- **配布準備**: M9 (Sparkle) は配布前提なら必須

**個人推奨スタート**: Phase A (バグ群) → Phase B (S1/S6/S7/S8) を v2.1 として 1 週間でまとめてリリース。その後ユーザー反応見て v2.2 着手。

---

## 7. 次のアクション

ユーザー承認待ち。承認後、Phase A から着手予定。それぞれの作業はブランチ `feature/v2.1-polish` 上で 1 PR / 機能の粒度。
