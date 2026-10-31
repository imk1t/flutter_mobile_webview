# Settings

`WebViewSettings` is immutable. Pass it to the constructor, or replace it later with
`updateSettings`:

```dart
final controller = AdvancedWebViewController(
  settings: const WebViewSettings(userAgent: 'MyApp/1.0'),
);

await controller.updateSettings(const WebViewSettings(javaScriptEnabled: false));
```

| Setting | Default | Android | iOS |
| --- | --- | --- | --- |
| `javaScriptEnabled` | `true` | Yes | Yes |
| `mediaPlaybackRequiresUserGesture` | `true` | Yes | Creation only |
| `allowsInlineMediaPlayback` | `false` | Ignored | Creation only |
| `supportZoom` | `true` | Yes | Ignored |
| `transparentBackground` | `false` | Yes | Yes |
| `passkeysEnabled` | `false` | Yes | Ignored (see below) |
| `userAgent` | `null` (platform default) | Yes | Yes |

"Creation only" settings are applied when the native view is created and ignored by
`updateSettings` on that platform.

## Passkeys (WebAuthn)

Passkeys work only for sites whose domain is associated with your app.

- **Android:** set `passkeysEnabled: true` and publish `/.well-known/assetlinks.json` with
  `delegate_permission/common.get_login_creds`, your package name and signing certificate
  SHA-256. Requires `androidx.webkit` 1.12+ and a WebView that supports WebAuthn; otherwise the
  setting is ignored.
- **iOS (16+):** no setting is needed. Add the Associated Domains capability with
  `webcredentials:example.com` and serve `/.well-known/apple-app-site-association` with your app ID.
- Passkeys of third-party identity providers (e.g. Google) and `mediation: "conditional"` are not
  supported inside a WebView.

See [Platform API mapping](./api-mapping#settings) for the native API behind each setting.

On Android, `updateSettings` can enable and disable passkeys on a WebView that supports WebAuthn.
