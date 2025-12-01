# SpeechAnalyzerSample

iOS 26.0 で導入された新しい `SpeechAnalyzer` API のサンプルプロジェクトです。従来の `SFSpeechRecognizer` API との比較ができる実装になっています。

## 概要
このプロジェクトは、iOS の音声認識機能を実装したサンプルアプリケーションです。以下の2つの音声認識APIを切り替えて使用できます：

- **SpeechAnalyzer** (iOS 26.0+): 新しい音声認識API
- **SFSpeechRecognizer**: 従来の音声認識API

## 主な機能
- リアルタイム音声認識（日本語対応）
- 2つのAPIの切り替え機能
- 音声入力の開始/停止
- 認識結果のリアルタイム表示
- 確定済みテキストと暫定テキストの区別表示（SpeechAnalyzer のみ）

## 要件
- iOS 26.0 以降
- Xcode 26.0.1 以降
- Swift 6.0
- マイクへのアクセス許可
- 音声認識へのアクセス許可

## プロジェクト構成
```
SpeechAnalyzerSample/
├── SpeechAnalyzerSample/
│   ├── SpeechAnalyzerSampleApp.swift    # アプリのエントリーポイント
│   ├── ContentView.swift                # メインUI（SwiftUI）
│   ├── SpeechAnalyzerManager.swift      # SpeechAnalyzer API の実装
│   ├── SpeechRecognizerManager.swift    # SFSpeechRecognizer API の実装
│   └── Locale+Ja.swift                  # 日本語ロケールの拡張
└── README.md
```

## 使用方法
1. プロジェクトを Xcode で開く
2. 実機またはシミュレーターで実行（マイクが必要なため実機推奨）
3. 右上の設定アイコンから使用するAPIを選択
4. 「音声入力」ボタンをタップして音声認識を開始

## 技術的な特徴

### SpeechAnalyzer API
- `SpeechTranscriber` を使用したモジュラーな設計
- `AsyncStream` を使用した非同期処理
- 音声フォーマットの自動変換（`BufferConverter`）
- 言語モデルの自動ダウンロード機能

### SFSpeechRecognizer API
- 従来のコールバックベースの実装
- より広範囲のiOSバージョンで動作

## 注意事項
- iOS 26.0 以降でのみ動作します
- 初回起動時、日本語の音声認識モデルが自動的にダウンロードされる場合があります
- インターネット接続が必要な場合があります（モデルのダウンロード時）

