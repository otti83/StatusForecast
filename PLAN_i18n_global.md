# StatusForecast — 多言語化 + グローバル地点対応 計画書

作成日: 2026-05-24
対象バージョン: v2.0 (現行 v1.x は日本専用 / 日本語固定)

---

## 1. 背景と目的

現状の StatusForecast は以下の前提で実装されている。

- **言語**: UI 文言・天気カテゴリラベル・日付フォーマットがすべて日本語ハードコード
- **地点**: `Location` が JMA の `officeCode` / `class10Code` / `amedasStationId` / `tempAreaCode` を必須項目として持ち、日本国内の予報区にしか紐付けられない
- **データソース構成**:
  - JMA 予報 (3日 / 週間) — 日本専用
  - JMA AMeDAS 実況 — 日本専用
  - Yahoo! YOLP 降水ナウキャスト — 日本専用
  - Open-Meteo hourly — **唯一グローバル対応済み**

このため

1. 海外在住・出張ユーザーが利用できない
2. 英語圏ユーザーに展開できない

この計画では **(A) 多言語対応 (日 / 英)** と **(B) グローバル地点対応** を v2.0 として同時導入する。両者は密結合 (Location モデルが地域種別を持つ ⇒ UI 文言の出し分け) なので一括設計する。

---

## 2. 設計方針

### 2.1 地域モデル — Region の導入

```swift
enum Region: String, Codable, Sendable {
    case japan    // JMA + AMeDAS + Yahoo + Open-Meteo
    case global   // Open-Meteo のみ
}
```

`Location` を **共通フィールド + 地域固有フィールド** に再編する。

```swift
struct Location: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var displayName: String        // 例: "Tokyo" / "東京都 / 東京" / "San Francisco, CA"
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String // 例: "Asia/Tokyo", "America/Los_Angeles"
    var countryCode: String?       // ISO 3166-1 alpha-2 (例: "JP", "US")
    var region: Region
    var japan: JapanLocationData?  // region == .japan のときのみ
}

struct JapanLocationData: Codable, Hashable, Sendable {
    var officeCode: String
    var class10Code: String
    var class20Code: String?
    var amedasStationId: String?
    var tempAreaCode: String?
}
```

判断基準:
- `region == .japan` ⇒ JMA 予報 + AMeDAS + Yahoo + Open-Meteo を並列取得
- `region == .global` ⇒ Open-Meteo のみ取得 (+ Open-Meteo daily を週間予報に転用)

### 2.2 データソース戦略

| 機能 | Japan (region=.japan) | Global (region=.global) |
|---|---|---|
| 実況 (現在気温・湿度・風・気圧・降水) | AMeDAS | Open-Meteo `current_weather` + hourly 現在時刻 |
| 1h 気温推移 (Today) | Open-Meteo hourly | Open-Meteo hourly |
| 6h 降水確率 | JMA (今日・明日) + Open-Meteo fallback | Open-Meteo (1h pop を 6h max で集約) |
| 週間予報 (高低気温・天気・POP) | JMA weekly | Open-Meteo daily (`weather_code` / `temperature_2m_max/min` / `precipitation_probability_max`) |
| 降水ナウキャスト (1h, 5分刻み) | Yahoo! YOLP | **非対応** — Rain タブを隠すか、Open-Meteo 15-min precipitation を代替表示 |
| 信頼度 A-E | JMA | **非対応** — 週間カードで欄ごと非表示 |

### 2.3 Open-Meteo の拡張使用

現状は hourly のみ。global 対応では追加で:

- **`current_weather=true`** — グローバル実況用
- **`daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset`** — 週間カード用
- **`forecast_days=7`** (既存と同じ)
- **`timezone=auto`** — Location の `timeZoneIdentifier` で明示指定するのが安全

天気コードは WMO weather interpretation codes (0-99)。これを既存 `WeatherCategory` にマップする `WMOWeatherCodeMap` を新設し、JMA 専用の `WeatherCodeMap` と並列に持つ。`DailyForecast.weatherCode` を **String (JMA) で固定するのを止め**、

```swift
enum WeatherCodeRef: Hashable, Sendable {
    case jma(String)        // "100", "200" など既存
    case wmo(Int)           // 0..99
}
```

に切り替える (これは大きめのリファクタなので Section 6 のマイグレーション参照)。

### 2.4 地点追加 UX — ジオコーディング

現状: Preferences に手動で `officeCode` を埋め込み (実質ハードコード)。

新規: Settings に **地点検索フィールド** を追加する。

- **Japan 地点**: 既存の JMA `area.json` を埋め込み (バンドルリソース)。「東京」「Yokohama」等のテキスト検索で officeCode を引く。
- **Global 地点**: Open-Meteo Geocoding API (`https://geocoding-api.open-meteo.com/v1/search`) を使う。フリー / 無認証 / 多言語対応 (`language=en` / `ja`)。レスポンスから `latitude` / `longitude` / `timezone` / `country_code` / `name` / `admin1` を取得して `Location` を構築。
- 検索結果は両者を統合 (JP 内ヒットは region=.japan で officeCode を解決、それ以外は region=.global で構築)。

ジオコーディング応答に対応する JMA 予報区が無い場合 (例: 小笠原の細かい島など) はフォールバックで region=.global として登録する。

### 2.5 多言語化アーキテクチャ

**ローカライズ対象**:

1. UI 文言 (タブ名 / セクション名 / ボタン / 設定画面 / エラー文)
2. 天気カテゴリラベル (`WeatherCategory.label`)
3. 日付・時刻フォーマット (曜日 / "5月24日" 等)
4. 風向 (16方位 — JMA の「北北東」 vs "NNE")
5. 単位 (m/s vs mph、hPa vs inHg、mm vs in、°C vs °F)
6. メニューバー右クリックメニュー
7. システム通知 (Phase 2 で導入予定の雨開始通知含む)

**実装方式**:

- **String Catalog (`Localizable.xcstrings`)** を採用。Xcode 26 / Swift 6 系の推奨。SwiftUI `Text("key")` で自動引き、AppKit 側は `String(localized:)` を使う。
- 既定言語は **英語 (Base)**。`ja` を追加翻訳。
- 「天気カテゴリ」「風向」はテーブル分離 (`Weather.xcstrings`, `WindDirection.xcstrings`)。
- 日付フォーマットは `Date.FormatStyle` をロケール経由で使用 (固定フォーマット `"M月d日"` などは撤去)。
- ロケール解決順序:
  1. `Preferences.languageOverride` ("system" / "en" / "ja")
  2. システム言語
  3. en (フォールバック)

**Preferences 追加**:

```swift
enum LanguageOverride: String, Codable, CaseIterable { case system, en, ja }
enum UnitSystem: String, Codable, CaseIterable { case metric, imperial }

struct Preferences {
    // ...existing
    var languageOverride: LanguageOverride = .system
    var unitSystem: UnitSystem = .metric   // v2.0 では metric 固定、imperial は v2.1 に延期可
}
```

言語切り替えはアプリ再起動が必要 (`Bundle.main` を差し替える hack は使わない)。Settings に「変更を反映するには再起動が必要です」と注記する。

### 2.6 UI の出し分け

| コンポーネント | Japan | Global |
|---|---|---|
| Today: AMeDAS 6 タイル (湿度/風/気圧/1h雨/24h雨/日照) | 表示 | Open-Meteo current を流用、ただし「日照」「気圧」が無い項目は省略しグリッドを 4 タイルに縮約 |
| Today: 1h 気温チャート | 表示 | 表示 (同一) |
| Today: 6h POP 2行 | JMA POP | Open-Meteo POP |
| Weekly: 7 カード + 気温チャート | 表示 (信頼度バッジあり) | 表示 (信頼度バッジ無し) |
| Rain タブ | 表示 | **タブ自体を非表示** (TabView の `if` で出し分け) |
| 風向表記 | 「北北東」 (16 方位) | "NNE" / "45°" |

`PopoverRootView` は `state.snapshot?.location.region` を見てタブ構成を切り替える。

---

## 3. 段階的実装プラン (フェーズ分け)

各フェーズは独立してコミット・テスト可能にする。

### Phase 0 — 準備 (~ 0.5d)
- 本計画書のレビュー＆承認
- `feature/v2-i18n-global` ブランチ作成 (本プロジェクトは現在 git 管理外なので git init を先に実施)
- 既存の日本固定スクリーンショットを `docs/v1_snapshots/` に退避

### Phase 1 — 国際化基盤 (1.5d)
- `Localizable.xcstrings` (Base=en, +ja) を追加し、UI 文言を全置換
  - 対象ファイル: `PopoverRootView`, `NowView`, `WeeklyView`, `RainView`, `AdvancedTab`, `MenuBarController` のメニュー
- `WeatherCategory.label` を localized key 化
- 日付フォーマッタを `Date.FormatStyle` (Locale 駆動) に置換
- 風向: 16 方位テーブルを localized key 化 (`wind.dir.nne` 等)
- Preferences に `languageOverride` を追加、Settings の「一般」タブに言語ピッカー設置
- アプリ起動時に override を `Bundle.main` の `appleLanguages` UserDefaults に注入 (executable target なので可能)
- **検証**: `defaults write` でシステム言語切替してスクリーンショット 2 種

### Phase 2 — Region モデル導入 (1d)
- `Location` を再編 (`JapanLocationData` 分離、`region` / `timeZoneIdentifier` / `countryCode` 追加)
- 既存 Preferences マイグレーション: `version` フィールドを Preferences に追加し、v1 → v2 で官庁コードを `JapanLocationData` 側に移送
- 既定 Location を引き続き「東京都 / 東京」(region=.japan) に
- `WeatherCodeRef` enum 導入、`DailyForecast.weatherCode` 型を差し替え
- `WMOWeatherCodeMap` 新設、`WeatherSymbol` 側で両ソースを受ける

### Phase 3 — Open-Meteo グローバル拡張 (1d)
- `OpenMeteoClient.fetchHourly` を `fetchAll` に拡張: current_weather + daily も同時取得
- `RefreshCoordinator.fetch` を分岐:
  - region=.japan ⇒ 4 並列 (現状通り)
  - region=.global ⇒ Open-Meteo 単独取得し、戻り値を `CurrentWeather` / `[DailyForecast]` / `[HourlyForecast]` にマッピング
- Yahoo / JMA / AMeDAS の呼び出しをスキップ
- Global の `SourceIssue` は Open-Meteo のみで判定

### Phase 4 — UI の region 出し分け (1d)
- `PopoverRootView` で Rain タブを region=.japan のみ表示
- `NowView.stationGrid` を「利用可能フィールドのみ表示」に変更 (湿度/風は両方、気圧/降水/日照は japan のみ等)
- `WeeklyView` の信頼度バッジを japan のみ表示
- 風向ラベルを localized 化 (`WindDirection.label(deg:locale:)`)
- メニューバー右クリックの「地点」サブメニューに region アイコン (🇯🇵 / 🌐) を付与

### Phase 5 — 地点検索 UI (1.5d)
- Settings に新タブ「地点」を追加 (既存の「Advanced」と分離)
- 検索フィールド入力 ⇒ Open-Meteo Geocoding API 呼び出し (debounce 300ms)
- ヒットを国名・行政区分付きで一覧表示、選択で `Location` 化して Preferences に追加
- JP の場合は内部で JMA `area.json` を引いて officeCode 解決 (国コード=JP & ジオコ結果と最近傍の class10 を bundle データから探索)
- 既存「東京固定」のハードコードを撤去

### Phase 6 — 仕上げ・QA (1d)
- 英語 / 日本語 × Japan / Global の 4 パターンを目視確認
- README / DESIGN.md を v2.0 に更新
- スクリーンショット差し替え
- `scripts/build-app.sh` の plist (CFBundleLocalizations) に en/ja を明記

**想定総工数**: 約 6–7 開発日

---

## 4. リスクと未決事項

| # | 項目 | リスク | 対応 |
|---|---|---|---|
| R1 | Open-Meteo geocoding の精度 | 田舎・小島で誤判定の可能性 | 「手動で緯度経度入力」のフォールバック UI を Phase 5 に含める |
| R2 | JMA `area.json` のサイズ | ~150KB だが起動コストに影響薄 | バンドル同梱で OK |
| R3 | 言語切替に再起動が必要 | UX 上の摩擦 | Settings に明示的なボタン「再起動して反映」を置く |
| R4 | WMO ⇄ JMA カテゴリ整合 | 「快晴」「晴れ時々曇り」等の粒度差 | 共通 9 カテゴリ (現状の `WeatherCategory`) にまとめ、両方からそこに射影 |
| R5 | Imperial 単位対応 | v2.0 に含めると工数膨張 | v2.1 に分離、`unitSystem` プロパティだけ先行投入し UI 側は metric 固定で出荷 |
| R6 | メニューバーアイコン (週間モード) の 7 国旗化等は想定外 | 既存ロジック流用で OK | 変更なし |
| R7 | Yahoo クライアント ID が global 地点で「未設定」警告を出す | UX 劣化 | region=.global のロケーションのみが選択中のときは Yahoo 警告を抑制 |

未決:
- 風速単位を日本語 UI でも「m/s」固定にするか、英語 UI ではデフォルト mph にするか → Phase 6 までに決定
- AMeDAS の項目ラベル ("湿度" / "1h降水量") を英語 UI でどう訳すか → Phase 1 のレビュー対象

---

## 5. データモデルマイグレーション戦略

既存ユーザー (≒ 開発者本人 + α) の Preferences ファイル (`~/Library/Application Support/StatusForecast/preferences.json`) は v1 形式。

```jsonc
// v1
{ "locations": [ { "officeCode": "130000", "class10Code": "130010", ... } ] }

// v2
{ "version": 2, "locations": [ { "region": "japan", "japan": { "officeCode": "130000", ... }, "latitude": ..., "timeZoneIdentifier": "Asia/Tokyo" } ] }
```

`PreferencesStore.load()` でデコード失敗時に v1 デコードを試み、成功すれば v2 に変換して書き戻す。失敗時は default Preferences にフォールバックし、`SourceIssue` 風の警告をユーザーに通知。

---

## 6. 完了の定義 (Definition of Done)

- [ ] 英語システムで起動 → すべての UI 文言が英語表示
- [ ] 日本語システムで起動 → すべての UI 文言が日本語表示
- [ ] Settings で言語を明示切替し、再起動後に反映される
- [ ] Settings「地点」タブで "San Francisco" を検索・追加でき、Today / Weekly タブが Open-Meteo データで描画される
- [ ] San Francisco 選択時に Rain タブが非表示になる
- [ ] 東京を選択し直すと Rain タブが再表示される
- [ ] v1 の Preferences ファイルが自動移行され、既存ユーザーが東京を失わない
- [ ] DESIGN.md / README が更新済
- [ ] 英 / 日 × Japan / Global の 4 スクリーンショットが docs/ に保存済

---

## 7. 次のアクション

ユーザー承認後、Phase 0 として:

1. プロジェクトを git 管理下に置く (`git init` + 初期コミット)
2. `feature/v2-i18n-global` ブランチを切る
3. Phase 1 (国際化基盤) から着手

承認可否、および Section 4 の未決項目 (風速単位デフォルト / AMeDAS 英訳の方針) について方針指定をお願いします。
