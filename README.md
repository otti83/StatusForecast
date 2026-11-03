# StatusForecast

macOSのメニューバーで天気を確認できるSwiftUIアプリです。現在の天気、時間別・週間予報、周辺の天気、大気質を表示します。日本語と英語に対応しています。天気データは[Open-Meteo](https://open-meteo.com/)を使用します。

## インストール

macOS 14以降、Apple Silicon（arm64）に対応しています。

1. [Releases](https://github.com/otti83/StatusForecast/releases)からDMGをダウンロードします。
2. DMGを開き、StatusForecast.appをApplicationsへドラッグします。
3. アプリを起動するとメニューバーに表示されます。

配布版はアドホック署名で、Appleの公証は行っていません。初回起動がブロックされた場合は「システム設定 → プライバシーとセキュリティ」でアプリ名と入手元を確認して「このまま開く」を選択してください。

## ビルド

Swift 5.10以降とmacOS SDKが必要です。

```sh
bash scripts/build-app.sh release
open build/StatusForecast.app
```

DMGとSHA-256チェックサムの作成:

```sh
bash scripts/build-dmg.sh
```

出力先は `dist/` です。APIキーは不要です。データ提供元の利用条件は[Open-Meteo](https://open-meteo.com/en/terms)を参照してください。
