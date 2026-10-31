# Getting started

`advanced_webview` is a Flutter WebView plugin for **Android and iOS only**, with a typed
Dart API. It borrows feature ideas from
`flutter_inappwebview`, but favours maintainability with a small public API and identical behaviour on both
platforms.

## Supported platforms

| Android | iOS |
| --- | --- |
| API 24+ | iOS 18+ |

On iOS, both Swift Package Manager and CocoaPods are supported. The plugin builds with
either, depending on your Flutter setting (`flutter config --enable-swift-package-manager` /
`--no-enable-swift-package-manager`); no extra setup is needed in your app.

## Installation

Add the package from [pub.dev](https://pub.dev/packages/advanced_webview):

```sh
flutter pub add advanced_webview
```

It needs Flutter 3.47.8 or later.

## A minimal example

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

## Current features

- Load a URL or an HTML string; reload, stop, go back and forward
- Get the current URL and title
- Run JavaScript (with or without a return value)
- JavaScript channels (messages from JS to Dart)
- Navigation decisions (main frame)
- Callbacks: page started / finished, progress, title changed, load errors
- Settings: JavaScript enabled, User-Agent, media autoplay, inline playback (iOS),
  zoom (Android), transparent background
