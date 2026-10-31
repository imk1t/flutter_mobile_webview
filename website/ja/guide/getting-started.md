# はじめに

`advanced_webview` は **Android と iOS に絞った**、型安全な Flutter WebView プラグインです。`flutter_inappwebview` の機能設計を参考にしつつ、
小さな公開 API と、両プラットフォームで揃えた振る舞いを重視しています。

## 対応プラットフォーム

| Android | iOS |
| --- | --- |
| API 24+ | iOS 18+ |

iOS は Swift Package Manager と CocoaPods の両方に対応しています。
Flutter の設定（`flutter config --enable-swift-package-manager` /
`--no-enable-swift-package-manager`）に応じてどちらでもビルドされ、利用側で追加の作業は不要です。

## インストール

[pub.dev](https://pub.dev/packages/advanced_webview) から追加します。

```sh
flutter pub add advanced_webview
```

Flutter 3.47.8 以降が必要です。

## 最小の例

```dart
import 'package:flutter/material.dart';
import 'package:advanced_webview/advanced_webview.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final controller = AdvancedWebViewController(
    onPageFinished: (url) => debugPrint('loaded $url'),
  )..loadUrl('https://flutter.dev');

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdvancedWebView(controller: controller);
}
```

## 現在の機能

- URL / HTML 文字列の読み込み、再読み込み、停止、戻る・進む
- 現在の URL・タイトルの取得
- JavaScript の実行（戻り値あり・なし）
- JavaScript チャネル（JS → Dart のメッセージ）
- ナビゲーションの許可・拒否（メインフレーム）
- コールバック: ページ開始 / 完了、進捗、タイトル変更、読み込みエラー
- 設定: JavaScript 有効化、User-Agent、メディア自動再生、インライン再生（iOS）、
  ズーム（Android）、背景の透過
