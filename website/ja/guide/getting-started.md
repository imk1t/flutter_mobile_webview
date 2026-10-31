# はじめに

`advanced_webview` は **Android と iOS に絞った**、型安全な Flutter WebView プラグインです。`flutter_inappwebview` の機能設計を参考にしつつ、
小さな公開 API と、両プラットフォームで揃えた振る舞いを重視しています。

## 対応プラットフォーム

| Android | iOS |
| --- | --- |
| API 24+ | iOS 18+ |

iOS は Swift Package Manager と CocoaPods の両方に対応しています。
Flutter の設定（`flutter config --enable-swift-package-manager` /
`--no-enable-swift-package-manager`）に応じてどちらでもビルドされ、プラグイン独自の手動リンク設定は不要です。アプリの要件は後述の手順に従って設定してください。

## インストール

まだ pub.dev には公開していません。最初のリリースまでは Git リポジトリを直接指定してください。

```yaml
dependencies:
  advanced_webview:
    git:
      url: https://github.com/imk1t/advanced_webview.git
```

## プラットフォームの準備

- Flutter 3.47.8 以降と Dart 3.13.7 以降を使用してください。pubspec の Dart 制約も満たす必要があります。
- Android: 実行時は API 24 以降。ビルド時は compileSdk 36、JDK 17 と互換性のある Gradle/AGP が必要です。
  プラグインは AGP 9.1.0 を使用します。
- iOS: 実行時とアプリの deployment target は 18.0 以降。対応する iOS SDK を含む Xcode を使用してください。
  Xcode の Runner ターゲットの Minimum Deployments を設定し、CocoaPods の Podfile がある場合は
  `platform :ios, '18.0'` も設定してください。

Android アプリの `android/app/src/main/AndroidManifest.xml` の `<manifest>` 直下に追加してください。
デバッグ用 Manifest だけに宣言すると release ビルドには適用されません。

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

HTTPS を使用してください。HTTP の例外が必要な場合は Android の Network Security Config と iOS の ATS を
アプリの用途に合わせて設定してください。プラグインは通信制限や証明書エラーを回避しません。
ファイル選択時の Info.plist キーは[Controller](./controller#file-uploads)、
passkeys のドメイン関連付けは[設定](./settings#passkeys-webauthn)を参照してください。

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
