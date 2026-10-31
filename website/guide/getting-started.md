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
`--no-enable-swift-package-manager`); no plugin-specific manual linking is needed. Configure your app requirements below.

## Installation

The package is not on pub.dev yet. Until the first release, depend on the Git repository:

```yaml
dependencies:
  advanced_webview:
    git:
      url: https://github.com/imk1t/advanced_webview.git
```

## Platform setup

- Use Flutter 3.47.8+ and Dart 3.13.7+, satisfying the Dart constraint in pubspec as well.
- Android: API 24+ at runtime; builds need compileSdk 36, JDK 17 and compatible Gradle/AGP.
  The plugin uses AGP 9.1.0.
- iOS: 18.0+ at runtime and as the app deployment target. Use Xcode with a compatible iOS SDK.
  Set Minimum Deployments on the Runner target in Xcode and, when using a CocoaPods Podfile,
  set `platform :ios, '18.0'` there too.

Add this directly under `<manifest>` in the app's `android/app/src/main/AndroidManifest.xml`.
A permission declared only in a debug Manifest does not apply to release builds.

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Use HTTPS. If HTTP exceptions are necessary, configure Android Network Security Config and iOS
ATS for the app's specific use case. The plugin does not bypass transport restrictions or certificate errors.
See [Controller](./controller#file-uploads) for file-picker Info.plist keys and
[Settings](./settings#passkeys-webauthn) for passkey domain associations.

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
