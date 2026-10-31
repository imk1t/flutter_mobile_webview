# 設定

`WebViewSettings` は不変オブジェクトです。コンストラクタで渡すか、後から `updateSettings` で置き換えます。

```dart
final controller = AdvancedWebViewController(
  settings: const WebViewSettings(userAgent: 'MyApp/1.0'),
);

await controller.updateSettings(const WebViewSettings(javaScriptEnabled: false));
```

| 設定 | 既定値 | Android | iOS |
| --- | --- | --- | --- |
| `javaScriptEnabled` | `true` | 対応 | 対応 |
| `mediaPlaybackRequiresUserGesture` | `true` | 対応 | 生成時のみ |
| `allowsInlineMediaPlayback` | `false` | 無視 | 生成時のみ |
| `supportZoom` | `true` | 対応 | 無視 |
| `transparentBackground` | `false` | 対応 | 対応 |
| `passkeysEnabled` | `false` | 対応 | 無視（下記参照） |
| `userAgent` | `null`（プラットフォーム既定） | 対応 | 対応 |

「生成時のみ」の設定はネイティブビューの生成時に適用され、そのプラットフォームでは `updateSettings` で変更しても無視されます。

## パスキー（WebAuthn） {#passkeys-webauthn}

パスキーは、ドメインがアプリと関連付けられたサイトでのみ使えます。

- **Android:** `passkeysEnabled: true` を指定し、`/.well-known/assetlinks.json` に
  `delegate_permission/common.get_login_creds`、パッケージ名、署名証明書の SHA-256 を記載します。
  `androidx.webkit` 1.12 以上と WebAuthn 対応の WebView が必要で、非対応なら設定は無視されます。
- **iOS（16 以上）:** 設定は不要です。Associated Domains capability に `webcredentials:example.com`
  を追加し、`/.well-known/apple-app-site-association` にアプリ ID を記載します。
- 外部 IdP（Google など）のパスキーと `mediation: "conditional"` は WebView 内では使えません。

各設定が使うネイティブ API は[ネイティブ API 対応表](./api-mapping#設定)を参照してください。

Android の WebAuthn 対応 WebView では、`updateSettings` でパスキーを有効・無効に切り替えられます。
