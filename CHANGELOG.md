# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

- Android: disabling `passkeysEnabled` now resets WebAuthn support after it was enabled.
- iOS: `getCookies` matches cookie paths at slash boundaries instead of arbitrary prefixes.
- Clarify navigation and JavaScript channel trust boundaries in English and Japanese, and document app setup requirements.

- Add `WebViewSettings.passkeysEnabled` to enable WebAuthn / passkeys on Android
  (`WebSettingsCompat.setWebAuthenticationSupport`). iOS needs no setting; the app must have the
  Associated Domains `webcredentials` entitlement.
- Android: `<input type="file">` now opens the system file picker (it did nothing before). iOS
  already used WebKit's built-in picker.
- Add `AdvancedWebViewController.onNewWindow` for `window.open` and `target="_blank"`. Without it,
  the URL now loads in the same WebView on both platforms (previously nothing happened on iOS).
- CI: lock GitHub Actions dependencies with `gh actions-lock` (`.github/workflows/actions.lock`
  pins every action, including transitive ones, to a commit SHA), verify it in the new
  `verify-lockfile` workflow, and reference actions by exact release tag.
- Add user scripts: `UserScript`, the `userScripts` constructor parameter, and
  `AdvancedWebViewController.addUserScript` / `removeAllUserScripts`. Android uses
  `androidx.webkit` (`DOCUMENT_START_SCRIPT`).
- Add cookie management: `AdvancedWebViewController.setCookie`, `getCookies` and `clearCookies`
  with the `WebViewCookie` type. On Android `getCookies` only reports name and value.
- Docs site: pin npm dependencies to exact versions and harden installs against supply-chain
  attacks (`website/.npmrc`, `website/bunfig.toml`: no lifecycle scripts, 7-day minimum release
  age, frozen lockfile, Dependabot cooldown).
- Rename the package from `flutter_mobile_webview` to `advanced_webview` (Dart package,
  entry library `package:advanced_webview/advanced_webview.dart`, Android package/namespace,
  iOS module and Pigeon channel names) and the public classes from `MobileWebView` /
  `MobileWebViewController` to `AdvancedWebView` / `AdvancedWebViewController`.
- iOS: raise the minimum iOS version to 18.0.
- iOS: run `evaluateJavaScript` on the main thread; it could hang when called off it.
- Make `README.md` English and move the Japanese README to `README.ja.md`.
- Add MIT license, community health files, issue/PR templates and pub.dev metadata.
- Pin Flutter 3.47.8 with mise (`mise.toml`); CI uses the same version.
- Android: detach the WebView from its previous container when a controller is shown
  by a new `AdvancedWebView`, so re-attaching a controller does not fail.
- iOS: app-initiated loads (`loadUrl`, `loadHtmlString`, `reload`, `goBack`,
  `goForward`) no longer reach `onNavigationRequest`, matching Android.
- Add native unit tests (Robolectric on Android, XCTest on iOS) and run the integration
  tests on an Android emulator and an iOS simulator in CI.
- Lint and format native code in CI: ktlint for Kotlin and swift-format for Swift
  (Pigeon-generated files are excluded).
- iOS: support both Swift Package Manager and CocoaPods, and ship a privacy manifest
  (`PrivacyInfo.xcprivacy`) with either. CI builds the example app with each.
- Add AI agent configuration (`AGENTS.md`, APM with shared skills from `imk1t/apm-shared`).

## 0.0.1

- Initial scaffold: Pigeon-based platform contract, Android (Kotlin) and iOS (Swift)
  implementations, and an example app.
