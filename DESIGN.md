# StatusForecast 設計書 (v2.0 — i18n + Global)

macOS メニューバーで世界の天気を一望できるネイティブアプリ。日英 UI 対応、日本国内は JMA / AMeDAS / Yahoo! の高精度情報、海外は Open-Meteo (JMA seamless 含む) を使用。

> **ステータス**: 2026-05-24 v2.0 (多言語・グローバル地点対応) 実装完了。詳細は `PLAN_i18n_global.md` 参照。
>
> **データ構成**:
> - **日本地点** (Region=.japan):
>   - 雨雲予測 (60 分) → Yahoo! 気象情報 API
>   - 1 日 / 3 日 / 週間 → 気象庁 `bosai/forecast` JSON
>   - 実況 → 気象庁 `bosai/amedas` JSON
>   - hourly 補完 → Open-Meteo
> - **海外地点** (Region=.global):
>   - current + daily + hourly → Open-Meteo 単独 (Rain タブは非表示)
>
> **多言語**: en (Base) / ja。Settings → 一般 → 言語 で system/en/ja 切替 (再起動要)。

---

## 1. プロジェクト概要

### 1.1 目的
Mac ユーザーがブラウザや天気アプリを開かずに、メニューバー上で「現在・1 日・週間」の天気を素早く把握でき、クリック一発で詳細（時系列の気温・降水確率・風速・降水強度予測）にアクセスできる常駐アプリを提供する。

### 1.2 命名
- アプリ名: **StatusForecast**
- バンドル ID（予定）: `com.statusforecast.app`
- 配布形態: 個人/社内利用想定の .app（Mac App Store 配布は非対象）

### 1.3 想定ユーザー
- 日本在住で日本の地名（都道府県・市区町村）で天気を見たい人
- メニューバー常駐の軽量 UI を好む人（macOS 標準「天気」アプリの "Show in Menu Bar" の代替・上位互換を狙う）

---

## 2. 競合・類似アプリ調査と機能比較

### 2.1 参考アプリ一覧
| アプリ | メニューバー表示 | 詳細 UI | 特徴 | StatusForecast への示唆 |
| --- | --- | --- | --- | --- |
| **macOS 標準「天気」** | アイコン + 気温 | 別ウインドウ（10 日先・時系列・降水・風） | 公式・OS 統合。日本語対応は普通 | "アイコン+気温" を出す最小フォーマットを踏襲 |
| **Carrot Weather (Mac)** | 気温 / アイコン / 風 などカスタム | フル UI（時系列・週間・レーダー・スナーク） | 高機能・有料。表示要素を細かくカスタム可 | メニューバーに何を出すかをユーザーに選ばせる |
| **Forecast Bar** | 気温・アイコン・降水確率 | ポップオーバー（時系列温度／降水／天気文） | NOAA データ、米国向き。日本データの粒度は弱い | レイアウト（時系列の横スクロール）の参考 |
| **MeteoBar** | 簡素なアイコン | 軽量ポップオーバー | OSS。OpenWeatherMap ベース | アーキテクチャと最小実装の参考 |
| **Yahoo!天気 (iOS/Android)** | — | 雨雲レーダー・1時間降水予測 | 60 分の降水強度を強く打ち出す | "60 分降水予測" を 1 級機能として扱う |

### 2.2 メニューバー天気アプリで「最低限」要求される機能
1. メニューバーに天気状態（アイコン）と現在気温を常時表示する
2. クリックでポップオーバーが開き、時系列気温・降水確率・風が見える
3. 自動更新（定期 fetch）、手動 Refresh、最終更新時刻表示
4. 表示地点の切替（複数都市・現在地）
5. 起動時自動起動、メニューバー上のアイコン以外で目立たない（LSUIElement）
6. 単位切替（℃/℉、m/s ↔ km/h、mm ↔ in）※今回は日本国内向けにつき ℃/m/s/mm 固定でも可
7. 設定画面（更新間隔・表示要素・地点管理）
8. 60 分の雨雲予測（日本国内アプリで強く期待される機能）

これを「ユーザー要望（週間天気／リアルタイム天気／1 日天気のアイコン切替＋詳細）」と突合し、機能要件を決定する。

---

## 3. データソース選定

### 3.1 ユーザー提供 API キー
- `Weather API.txt` の中身は **Yahoo! JAPAN デベロッパーネットワーク (YOLP) の Client ID** 
- Yahoo! JAPAN の "気象情報API" (YOLP) は **降水強度のみ** を返す API である:
  - エンドポイント: `https://map.yahooapis.jp/weather/V1/place`
  - 取得可能: 現在時刻〜60 分後までの降水強度予測値 (mm/h)、`past=2` 指定で過去 2 時間まで遡及可能
  - 取得間隔: 5 分 or 10 分
  - 出力: XML / JSON / JSONP（`output=json` で JSON）
  - 認証: クエリ `appid=<Client ID>`
  - レート制限: **1 アプリあたり 24 時間で 50,000 リクエスト**
  - **取得できないもの**: 気温・湿度・風速・天気状態・週間予報・降水確率
- 結論: Yahoo! 単独ではユーザー要望（週間／温度／降水確率／風速）を満たせない

### 3.2 補完データソース：気象庁 (JMA) オープンデータ
ユーザーが「他の日本国内の天気サービスでの代替は許容」と明言しているため、**気象庁 JSON** を併用する。JMA のオープンデータは政府標準利用規約に準拠して無料利用でき、登録不要、レート制限の公表なし（常識的範囲で利用）。

- **3 日／週間予報**: `https://www.jma.go.jp/bosai/forecast/data/forecast/{office_code}.json`
  - `office_code` 例: 東京都 `130000`、大阪府 `270000`、北海道宗谷 `011000` … 計 約 60 府県予報区
  - 取得可能フィールド:
    - 3 日予報ブロック: `weatherCodes` / `weathers`（天気文）/ `winds`（風） / `waves`（波）/ `pops`（降水確率 6h or 3h 単位）/ `temps`（最低・最高気温）
    - 週間予報ブロック (7 日分): `weatherCodes` / `pops` / `reliabilities` (A〜E)/ `tempsMin`/`tempsMax`/`tempsMin/MaxUpper/Lower`（信頼区間）/ `tempAverage`（平年値）
- **概況**: `https://www.jma.go.jp/bosai/forecast/data/overview_forecast/{office_code}.json`
- **地域コード**: `https://www.jma.go.jp/bosai/common/const/area.json`（centers / offices / class10s / class15s / class20s 階層）
- **AMeDAS 実況**: 
  - 最新時刻: `https://www.jma.go.jp/bosai/amedas/data/latest_time.txt`
  - 観測所一覧: `https://www.jma.go.jp/bosai/amedas/const/amedastable.json`（緯度経度・標高・観測要素）
  - 実況値: `https://www.jma.go.jp/bosai/amedas/data/map/{YYYYMMDDHHmmss}.json`
  - 取得可能: 気温・降水量・風向風速・湿度（観測所による）

### 3.3 役割分担
| 機能 | データソース | 備考 |
| --- | --- | --- |
| 60 分の降水強度予測 | **Yahoo! 気象情報API** | 5/10 分刻みで mm/h を取得、雨雲チャート表示 |
| 今日／明日／明後日の天気文・降水確率・気温 | JMA forecast 3 日予報 | 6 時間 or 3 時間粒度 |
| 週間天気・週間降水確率・週間最低/最高気温 | JMA forecast 週間予報 | 7 日分 |
| 現在の実況（気温・湿度・風向風速） | JMA AMeDAS 実況 | 最寄り観測所を緯度経度で選定 |
| 注意報・警報（任意・Phase 2） | JMA `/bosai/warning/data/warning/{office}.json` | 後続フェーズ |

### 3.4 利用規約・クレジット
- **Yahoo! JAPAN**: クレジット表記（"Web Services by Yahoo! JAPAN"）必須。設定→「このアプリについて」に表示する。
- **気象庁**: 政府標準利用規約 v2.0 準拠。「気象庁ホームページ」のクレジット表示。
- アプリ起動時の About ダイアログに両方のクレジットを表示する。

---

## 4. 機能要件

### 4.1 メニューバー (NSStatusItem)
- **F-MB-01**: メニューバーには `アイコン + 現在気温(°C)` を表示する（macOS 標準準拠）。
- **F-MB-02**: アイコンは現在天気を反映（晴 / 曇 / 雨 / 雪 / 雷 …、SF Symbols `sun.max`, `cloud`, `cloud.rain`, `cloud.snow`, `cloud.bolt` などを利用）。
- **F-MB-03**: ユーザーは設定でメニューバーの表示モードを切替可能:
  - `weeklyMode`: 7 日間の超ミニ天気アイコンを横並びに描画する (NSImage カスタム描画)
  - `realtimeMode`: 現在天気アイコン + 気温 + 降水強度バッジ
  - `dailyMode`: 今日の天気アイコン + 最低/最高気温（例: `☀ 18°/27°`）
- **F-MB-04**: クリックでポップオーバー (NSPopover)を開く（後述）。
- **F-MB-05**: 右クリック（または Option+クリック）で隠しメニュー: 設定・更新・終了。
- **F-MB-06**: 自動更新間隔（既定 10 分）。手動更新はポップオーバー内のリフレッシュボタン。
- **F-MB-07**: ネットワーク失敗時は最後の値をグレーアウト表示 + バッジ "!"。

### 4.2 ポップオーバー (詳細表示)
タブ or セグメント切替で 3 ビューを提供する。

#### 4.2.1 リアルタイム (Now)
- **F-PV-N-01**: AMeDAS 実況: 現在気温・湿度・風向風速（方位は 16 方位アイコン）
- **F-PV-N-02**: 60 分降水予測グラフ（Yahoo! 気象情報 API）: 横軸 -60 分〜+60 分（10 分刻み）、縦軸 mm/h。0.1 mm/h 未満は「降っていない」表示。
- **F-PV-N-03**: 体感気温・不快指数（湿度＋気温から計算、近似式）
- **F-PV-N-04**: 最終更新時刻と「更新」ボタン

#### 4.2.2 今日 (Today / Daily)
- **F-PV-D-01**: 今日の天気文（JMA `weathers`）
- **F-PV-D-02**: 1 日の気温推移チャート: 今日の最低・最高（JMA `temps`）と昨日比
- **F-PV-D-03**: 6 時間刻みの降水確率バー（JMA `pops` 0-6 / 6-12 / 12-18 / 18-24）
- **F-PV-D-04**: 風（JMA `winds` 文字列）
- **F-PV-D-05**: 注意報サマリー（Phase 2 で追加。Phase 1 は空）

#### 4.2.3 週間 (Weekly)
- **F-PV-W-01**: 7 日分の表: 日付 / 曜日 / 天気アイコン / 最低気温 / 最高気温 / 降水確率 / 信頼度 (A-E)
- **F-PV-W-02**: 気温の折れ線グラフ（最低・最高 2 本 + 平年値の薄線）。信頼区間 (Upper/Lower) を帯で表示。
- **F-PV-W-03**: 降水確率の縦棒グラフ
- **F-PV-W-04**: タップで Today タブに連動

#### 4.2.4 共通フッター
- 表示地点名（例: "東京都 / 東京"）、ロケーション切替プルダウン
- "設定" ボタン (歯車アイコン)

### 4.3 設定ウインドウ (NSWindow / SwiftUI Settings シーン)
タブ 4 つ。

| タブ | 設定項目 |
| --- | --- |
| 一般 (General) | 起動時自動起動 (LoginItem)、メニューバー表示モード (weekly/realtime/daily)、アイコンセット (mono / color)、温度の小数表示、ログイン時起動 |
| 地点 (Locations) | 地点リスト管理（追加・削除・並べ替え・既定地点設定）。各地点は `JMA office_code + class10/class20 + AMeDAS station id + 表示名` を保持。 |
| 更新 (Refresh) | 自動更新間隔（5 / 10 / 15 / 30 / 60 分）、Wi-Fi のみ更新（NWPathMonitor）、起動時即更新 |
| 詳細 (Advanced) | API 利用状況（Yahoo の本日リクエスト数）、キャッシュ消去、診断情報のコピー、データソースのクレジット表示 |

### 4.4 地点の追加 UX
1. 「地点を追加」を押すと検索フィールド付きシートを開く
2. ユーザーが「東京」など入力 → JMA の `area.json` (offices/class10/class20)に対する**ローカルインデックス検索**でマッチを表示
3. 選択すると、その緯度経度（class20 の代表点）を保存し、近傍の AMeDAS 観測所を amedastable.json から自動選定（距離 km の昇順 + 観測要素フラグ）
4. オプションで Core Location による現在地取得（macOS 14+）にも対応

### 4.5 通知 (Phase 2 想定 / Phase 1 は仕様のみ確定)
- **F-NT-01**: 雨が降り始める前 N 分（既定 20 分）にローカル通知（"あと 20 分で雨が降り始めます"）
  - Yahoo! 降水強度予測の `forecast` 配列で `Rainfall >= 0.1` の最初の時刻を検出
- **F-NT-02**: 気象庁警報の発令通知（Phase 2）

---

## 5. 非機能要件

| 区分 | 要件 |
| --- | --- |
| パフォーマンス | 起動 → メニューバー表示まで 1.0 秒以内。fetch サイクル中の CPU 使用率は瞬間値で 5% 未満を目標 |
| 信頼性 | API エラー時もアプリは落ちない。指数バックオフ付きリトライ（最大 3 回） |
| キャッシュ | JMA レスポンスはディスクキャッシュ（`~/Library/Caches/com.statusforecast.app/`）。期限付き ETag/Last-Modified を尊重 |
| レート制限遵守 | Yahoo! は 24h あたり 50,000。10 分間隔 × 144 回 = 144 req/日/地点なので 5 地点でも余裕。安全弁として 1 アプリ 8,000 req/日を上限化 |
| プライバシー | 取得した緯度経度は端末内 (`UserDefaults` + `Application Support`) のみに保存。外部送信は API リクエストのみ |
| アクセシビリティ | VoiceOver: メニューバー文字列／ポップオーバーの数値はラベル化。色覚多様性: アイコンは形+色 |
| ローカライズ | 日本語（既定）/ 英語の 2 言語。気象状態の文字列は JMA の `weathers` 文字列をそのまま表示 |
| 配布 | Apple Developer ID 署名・公証（Notarization）想定 |
| サポート OS | macOS 13 Ventura 以降（MenuBarExtra と SwiftUI Settings シーンを使うため、できれば 14 Sonoma 以降） |

---

## 6. UI / UX ワイヤーフレーム

### 6.1 メニューバーアイコン

```
weeklyMode (7 日ミニ):
  ┌──────────────────────────┐
  │ ☀ ☀ ☁ ☂ ☁ ☀ ☀ │   ← 各アイコン 12pt、矢印形は曜日無
  └──────────────────────────┘

realtimeMode (リアルタイム):
  ┌──────────────┐
  │ ☂ 18° ●   │  ← ● = 降水中バッジ
  └──────────────┘

dailyMode (1 日):
  ┌──────────────┐
  │ ☀ 18°/27°  │
  └──────────────┘
```

### 6.2 ポップオーバー (320 × 420 px 目安)

```
┌─────────────────────────────────────┐
│  東京都 / 東京  ▾                ⟳  │ ← 地点プルダウン + 更新ボタン
├─────────────────────────────────────┤
│  [ Now ][ Today ][ Weekly ]          │ ← セグメントタブ
├─────────────────────────────────────┤
│   Now ビュー                          │
│   ┌─────────────────────────┐         │
│   │   ☀   18.2°C            │         │
│   │   湿度 62% / 南南西 3 m/s│         │
│   └─────────────────────────┘         │
│   60 分降水予測                       │
│   ┌─────────────────────────┐         │
│   │ ▁ ▁ ▂ ▃ ▆ █ █ ▇ ▅ ▃ ▁ ▁ │ mm/h    │
│   │-60       now        +60 │ 分      │
│   └─────────────────────────┘         │
│   体感 17.0°C  /  不快指数 60         │
├─────────────────────────────────────┤
│  最終更新: 12:34   ⚙ 設定            │
└─────────────────────────────────────┘
```

### 6.3 設定ウインドウ (640 × 480 px)

```
┌─ StatusForecast 設定 ───────────────────────┐
│ [General][Locations][Refresh][Advanced]      │
├──────────────────────────────────────────────┤
│ ▷ メニューバー表示モード:                    │
│     ( ) Weekly   (●) Realtime  ( ) Daily     │
│ ▷ アイコンセット:                            │
│     (●) Monochrome  ( ) Color                │
│ ▷ [✓] ログイン時に自動起動                   │
│ ▷ [✓] 起動時に即更新                         │
├──────────────────────────────────────────────┤
│ クレジット: Web Services by Yahoo! JAPAN     │
│            Data: 気象庁 / Japan Meteorological Agency │
└──────────────────────────────────────────────┘
```

---

## 7. アーキテクチャ

### 7.1 全体構成（クリーンアーキテクチャ風 3 レイヤー）

```
┌──────────────────────────────────────────┐
│ Presentation (SwiftUI)                   │
│  - MenuBarView / PopoverView / Settings  │
├──────────────────────────────────────────┤
│ Domain (純Swift)                          │
│  - Models (CurrentWeather / DailyForecast│
│    / WeeklyForecast / RainfallForecast)  │
│  - Use Cases (FetchWeatherForLocation 等)│
│  - LocationResolver                      │
├──────────────────────────────────────────┤
│ Data                                     │
│  - YahooWeatherClient (降水強度)         │
│  - JMAForecastClient  (3 日 + 週間)      │
│  - JMAAmedasClient    (実況)             │
│  - JMAAreaIndex       (地域コード探索)   │
│  - Cache / Persistence                   │
└──────────────────────────────────────────┘
```

### 7.2 主要シーケンス（メニューバー更新）

```
Timer (10 min)
   │
   ▼
RefreshCoordinator.refreshAll(selectedLocation)
   ├─▶ JMAForecastClient.fetch(office_code) ─────▶ Cache
   ├─▶ JMAAmedasClient.fetchNearest(lat,lon) ────▶ Cache
   └─▶ YahooWeatherClient.fetch(lat,lon,past=1) ─▶ Cache
                │
                ▼
         WeatherSnapshot を組み立て
                │
                ▼
       MenuBarStatusController に通知
       PopoverViewModel に @Published で反映
```

### 7.3 主要モジュール (Swift Package 構成)

```
StatusForecast/
├── App/
│   ├── StatusForecastApp.swift     (LSUIElement, MenuBarExtra, Settings シーン)
│   └── AppDelegate.swift           (起動時のサービス初期化)
├── MenuBar/
│   ├── MenuBarStatusController.swift
│   ├── MenuBarIconRenderer.swift   (weekly モードのカスタム描画)
│   └── PopoverPresenter.swift
├── Popover/
│   ├── PopoverRootView.swift
│   ├── NowView.swift
│   ├── TodayView.swift
│   ├── WeeklyView.swift
│   └── Components/
│       ├── RainfallChart.swift     (Yahoo 降水強度の棒グラフ)
│       ├── TemperatureChart.swift  (Swift Charts)
│       └── PopBar.swift
├── Settings/
│   ├── SettingsScene.swift
│   ├── GeneralTab.swift
│   ├── LocationsTab.swift
│   ├── RefreshTab.swift
│   └── AdvancedTab.swift
├── Domain/
│   ├── Models.swift                (WeatherSnapshot, RainfallForecast 等)
│   ├── WeatherCode.swift           (JMA コード → SF Symbol + 表示文字列)
│   └── UseCases/
│       └── RefreshCoordinator.swift
├── Data/
│   ├── Network/
│   │   ├── HTTPClient.swift
│   │   ├── YahooWeatherClient.swift
│   │   ├── JMAForecastClient.swift
│   │   ├── JMAAmedasClient.swift
│   │   └── JMAAreaIndex.swift
│   ├── Cache/
│   │   ├── DiskCache.swift
│   │   └── CachePolicy.swift
│   └── Persistence/
│       └── PreferencesStore.swift  (UserDefaults + Codable)
├── Resources/
│   ├── Assets.xcassets             (アイコン)
│   ├── area.json                   (バンドル同梱の JMA 地域インデックス)
│   ├── amedastable.json            (バンドル同梱、起動時にディスクキャッシュと比較)
│   └── ja.lproj / en.lproj
└── Tests/
    ├── YahooWeatherClientTests.swift (XML/JSON パース)
    ├── JMAForecastClientTests.swift
    └── WeatherCodeMappingTests.swift
```

---

## 8. データモデル（主要部分のドメインモデル）

```swift
struct Location: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String        // 例: "東京都 / 東京"
    var officeCode: String         // JMA office_code 例 "130000"
    var class10Code: String        // 例 "130010"（東京地方）
    var class20Code: String?       // より細分の市区町村コード
    var latitude: Double
    var longitude: Double
    var amedasStationId: String?   // 例: "44132"
}

struct WeatherSnapshot {
    let location: Location
    let fetchedAt: Date
    let current: CurrentWeather?           // AMeDAS 実況（取得失敗時 nil）
    let today: DailyForecast?              // JMA 今日
    let upcoming: [DailyForecast]          // 明日・明後日
    let weekly: [DailyForecast]            // 7 日
    let rainfall: RainfallForecast?        // Yahoo!
}

struct CurrentWeather {
    let observedAt: Date
    let temperatureC: Double?
    let humidity: Double?
    let windDirectionDeg: Double?
    let windSpeedMps: Double?
    let precip1hMm: Double?
}

struct DailyForecast {
    let date: Date
    let weatherCode: String            // JMA コード "100" 等
    let weatherText: String            // JMA `weathers`（晴れ 一時 雨 …）
    let tempMinC: Double?
    let tempMaxC: Double?
    let popsByPeriod: [PrecipChance]   // 6 時間ブロックの確率
    let windText: String?
    let reliability: String?           // 週間予報の信頼度 A〜E
}

struct PrecipChance {
    let startHour: Int                 // 0/6/12/18
    let endHour: Int
    let percent: Int?
}

struct RainfallForecast {
    let observedAt: Date
    let samples: [RainfallSample]      // 過去〜未来 60 分、10 分刻み
}

struct RainfallSample {
    let date: Date
    let kind: Kind                     // .observation / .forecast
    let mmPerHour: Double
    enum Kind { case observation, forecast }
}
```

---

## 9. ネットワーク仕様（実装側のリクエスト例）

### 9.1 Yahoo! 気象情報 API
- リクエスト
  ```
  GET https://map.yahooapis.jp/weather/V1/place
        ?coordinates=139.7670,35.6810
        &appid=<Client ID>
        &output=json
        &past=1
        &interval=10
  ```
- レスポンス（XML がデフォルトだが `output=json` で JSON）
  ```jsonc
  {
    "ResultInfo": {"Count":1,"Total":1,"Status":200,...},
    "Feature": [{
      "Property": {
        "WeatherAreaCode": "4410",
        "WeatherList": {
          "Weather": [
            {"Type":"observation","Date":"202605211200","Rainfall":0.00},
            ...
            {"Type":"forecast","Date":"202605211300","Rainfall":0.85}
          ]
        }
      }
    }]
  }
  ```
- パース時は `past=1` で過去 60 分の observation と未来 60 分の forecast を取得。
- 失敗時 (400 / 503) はキャッシュを保持し、UI 上は "降水情報を取得できませんでした" を表示。

### 9.2 JMA 3 日 + 週間予報
- `GET https://www.jma.go.jp/bosai/forecast/data/forecast/130000.json`
- レスポンスは配列で、`[0]` が 3 日予報・`[1]` が週間予報。本仕様では:
  - `[0].timeSeries[0]`: 天気コード/天気文/風/波
  - `[0].timeSeries[1]`: 降水確率 (6h or 3h 単位)
  - `[0].timeSeries[2]`: 気温 (今日の最低 or 明日の最低/最高)
  - `[1].timeSeries[0]`: 週間 weatherCodes / pops / reliabilities
  - `[1].timeSeries[1]`: 週間 tempsMin/Max + 信頼区間
  - `[1].tempAverage`: 平年値

### 9.3 JMA AMeDAS 実況
1. `GET /bosai/amedas/data/latest_time.txt` → 最新時刻 ISO8601
2. その時刻を `YYYYMMDDHHmmss` に整形して `GET /bosai/amedas/data/map/<ts>.json`
3. 観測所 ID で気温/風/湿度を取り出す（観測所が湿度未対応なら nil）

### 9.4 地域コード解決
- ビルド時に `area.json` を同梱しておき、起動時に `~/Library/Application Support/StatusForecast/area.json` と差分更新（HEAD で `Last-Modified` を確認）
- 検索は `class20s` (市区町村レベル) を入力文字列で部分一致 → 結果をスコアリング

---

## 10. UI 詳細 / 状態遷移

### 10.1 状態
- `idle` : 起動直後、まだ何も取得していない
- `loading(initial | refreshing)` : ネットワーク中
- `ready(snapshot)` : 表示可能
- `stale(snapshot, lastError)` : 取得失敗、古い値を出す
- `error(reason)` : 一度も取得できていない（地点未設定など）

### 10.2 状態遷移図
```
idle ──(launch)──▶ loading(initial) ──ok──▶ ready
                       │
                       └──fail──▶ error

ready ──(timer/refreshTap)──▶ loading(refreshing) ──ok──▶ ready
                                           │
                                           └──fail──▶ stale

stale ──(retry success)──▶ ready
```

### 10.3 メニューバーアイコン描画（weekly モード）
- カスタム NSImage を生成: 7 個の 12pt SF Symbol を 2pt スペースで横並びにし、合成画像を `NSStatusItem.button.image` にセット
- 解像度: Retina 用に 2x の CGContext で描画
- 単色テンプレート (`image.isTemplate = true`) でダーク/ライト自動対応

### 10.4 ポップオーバー
- `NSPopover` ベース。SwiftUI を `NSHostingView` で乗せる
- アニメーションは標準。フォーカスを失うと自動 close (`behavior = .transient`)
- 設定からは別ウインドウとして `NSWindow` を開く（モーダルではない）

---

## 11. エラー / キャッシュ / バックグラウンド戦略

| シナリオ | 動作 |
| --- | --- |
| Yahoo! 5xx | バックオフ (2/4/8 秒) で 3 回まで再試行。最終的に失敗したら "降水情報を取得できませんでした" バナー表示。直近の forecast はキャッシュから |
| Yahoo! 400 (パラメータ不正) | クレデンシャル設定ミスとみなし、設定→Advanced に赤バッジ |
| JMA 404 | office_code 不正の可能性 → 地点を再選択するダイアログ |
| ネットワーク断 | NWPathMonitor で検出。復帰時に即 refresh |
| スリープからの復帰 | NSWorkspace.didWakeNotification を購読し refresh |
| キャッシュ | JMA: 30 分間 / Yahoo!: 5 分間 / AMeDAS: 10 分間 を上限とする (TTL 経過後は通信、失敗時は TTL 超過でも提示) |

---

## 12. レート制限・コスト試算

### Yahoo! 気象情報 API (24h 50,000 req / app)
- デフォルト 10 分間隔 → 144 req / 日 / 地点
- 5 地点でも 720 req / 日 → 余裕
- ユーザーが最短 5 分間隔（288 req/日/地点）を設定しても、上限の 50,000 に対して 174 地点まで安全。アプリ側でも `8,000 req/日/アプリ` を硬上限とし、超過しそうなら間隔を強制的に伸ばす

### JMA
- 公開規約上のレート制限なし。マナーとして 5 分以上のキャッシュ + 起動時 1 回 + 自動更新間隔 (>=5 分) を遵守

---

## 13. セキュリティ・プライバシー

- API Key (Yahoo! Client ID) は、ビルド時はソース埋め込みを避け、ユーザーの `Application Support/StatusForecast/credentials.json` に保存する。初回起動時に `Weather API.txt` から自動移入する初期化フローを用意する。
- Keychain は Phase 2（ユーザーがマシン間で共有する想定が出たら）に格上げ検討
- 送信先ドメインは `map.yahooapis.jp` と `www.jma.go.jp` のみ。ATS で TLS1.2+ を強制
- App Sandbox: `com.apple.security.network.client = YES` のみ ON。File / Camera 等は無効

---

## 14. テスト戦略

| レイヤー | 内容 |
| --- | --- |
| Unit | YahooWeatherClient: 固定 JSON 入力 → モデル変換のテーブルテスト。JMA*Client: 取得済み JSON フィクスチャでパース検証。WeatherCode マッピング全件 |
| Integration | 実 API への smoke test を `#if INTEGRATION_TEST` 下で実行 |
| UI | スナップショットテスト (SwiftUI Preview ベース) を Now / Today / Weekly について保存 |
| 手動 | リリース前に晴れ/雨/雪/警報日のシナリオで確認、AMeDAS が湿度を返さない観測所での挙動確認 |

---

## 15. 開発フェーズ / マイルストーン

| フェーズ | スコープ | 完了条件 |
| --- | --- | --- |
| **Phase 0** プロトタイプ | NSStatusItem に固定文字列表示／JMA 130000 を fetch しコンソール出力 | メニューバーに東京の最高/最低が出る |
| **Phase 1** MVP | 機能要件 F-MB-01〜07 / F-PV-N/D/W すべて, 設定 General/Locations/Refresh | 任意の都市で Now/Today/Weekly が完全表示、Yahoo!の 60 分予測が反映 |
| **Phase 2** 拡張 | 通知（雨が降る予告）、警報表示、Wi-Fi のみ更新、現在地（CoreLocation） | 通知設定 ON で雨開始 20 分前に通知される |
| **Phase 3** 配布 | 署名・公証・自動アップデート (Sparkle 等) | `.app` の zip を Notarization 済みで配布 |

---

## 16. 既知のリスク・未解決事項

1. **Yahoo! 気象情報 API は降水強度のみ**: 仮にユーザーが「Yahoo! API のみ使え」と将来希望した場合、機能要件の大半が満たせない。本書は JMA 併用を前提とする。
2. **JMA API は公式には "API" を名乗っていない**: 仕様変更の事前告知が無いリスクあり。バージョン差分検出機構（フィールド欠落時の defensive parsing）を Data 層に組み込む。
3. **AMeDAS の観測要素は観測所ごとに異なる**: 湿度や日照を返さない観測所がある。UI 側は nil safe に描画する。
4. **macOS のメニューバー残り幅**: 長い表示モード（weekly）は外部ディスプレイのノッチ環境で見切れる可能性。最大長を実測で 28pt × 7 ≒ 196pt 程度に抑える。
5. **アクセサリビューの NSImage 制限**: メニューバーアイコンは高さ 22pt が上限。weekly モードで 7 アイコンを並べる際の最小描画サイズを 12pt に固定する。

---

## 17. クレジット表記（最終版）

```
This app uses:
- Web Services by Yahoo! JAPAN (https://developer.yahoo.co.jp/)
- 気象庁 / Japan Meteorological Agency オープンデータ
  (政府標準利用規約 v2.0 準拠)
```

---

以上をもって StatusForecast の初期設計書 v0.1 を完了とする。次の作業は、本設計に沿った Xcode プロジェクトの雛形 (Swift Package + Xcode 16) 作成と、Phase 0 プロトタイプの実装である。
