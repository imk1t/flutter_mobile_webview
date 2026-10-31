# Contributing to advanced_webview

Thanks for your interest in contributing! Issues and pull requests are welcome in
English or Japanese (日本語での Issue / PR も歓迎します).

## Before you start

- Search existing [issues](https://github.com/imk1t/advanced_webview/issues) first.
- For anything larger than a small fix (new APIs, behaviour changes), open an issue
  to discuss the design before writing code. The goal of this package is a **small,
  maintainable API for Android and iOS only**; please read
  [doc/architecture.md](doc/architecture.md) to understand the design decisions.
- Web, macOS, Windows and Linux support is out of scope.

## Development setup

Requirements: [mise](https://mise.jdx.dev) (the Flutter version is pinned in `mise.toml`; run `mise trust && mise install` once), Xcode for iOS, Android SDK + JDK 17 for Android. All Flutter / Dart commands below use the pinned version (activate mise in your shell, or prefix with `mise exec --`).

For native code you also need [ktlint](https://pinterest.github.io/ktlint/) 1.8.0 (Kotlin) and
[swift-format](https://github.com/swiftlang/swift-format) (Swift). swift-format ships with
Xcode 16+ as `swift format`; ktlint can be installed with Homebrew:

```sh
brew install ktlint     # check `ktlint --version` (CI uses 1.8.0)
swift format --version  # CI uses the Swift 6.4.1 toolchain
```

```sh
flutter pub get
flutter analyze
flutter test                                    # Dart unit tests
cd example && flutter test integration_test     # on a device or simulator

# Native unit tests (build the example once first so Gradle / Xcode are configured)
cd example && flutter build apk --debug && cd android && ./gradlew :advanced_webview:testDebugUnitTest
cd example && flutter build ios --simulator --debug && cd ios && \
  xcodebuild test -workspace Runner.xcworkspace -scheme Runner -only-testing:RunnerTests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Run the CI checks locally with mise (macOS runners are costly, so iOS CI is limited):

```sh
mise run check          # Dart format/Pigeon/analyze/test + ktlint + swift-format
mise run check:ios      # macOS only: SwiftPM build, integration test, XCTest (`tool/check-ios.sh cocoapods|all` for the podspec)
git config core.hooksPath .githooks   # optional pre-push hook running the above (SKIP_IOS=1 skips the simulator)
```

CI runs only the Dart and lint jobs on every PR. The Android and iOS build/test jobs run on a PR
labelled `full-ci`, or manually from the Actions tab (Run workflow).

Format and lint native code (generated Pigeon files are excluded):

```sh
ktlint --format $(git ls-files '*.kt' '*.kts' | grep -v '\.g\.kt$')
swift format --in-place $(git ls-files '*.swift' | grep -v '\.g\.swift$')
swift format lint --strict $(git ls-files '*.swift' | grep -v '\.g\.swift$')
```

Style is configured in `.editorconfig` (ktlint, `intellij_idea` code style) and
`.swift-format`. CI fails on any violation.

## Project rules

- **The platform contract lives only in `pigeons/messages.dart`.** After changing it,
  regenerate the bindings and commit the generated files:

  ```sh
  dart run pigeon --input pigeons/messages.dart
  ```

  Never edit `*.g.dart`, `Messages.g.kt` or `Messages.g.swift` by hand. CI fails if
  the generated code is out of date.
- **Keep Android and iOS mirrored.** Both platforms use the same class names
  (`AdvancedWebView`, `WebViewRegistry`, `WebViewHostApiImpl`, `AdvancedWebViewFactory`,
  `AdvancedWebViewPlugin`). A change on one side normally needs the same change on the other.
- **iOS supports both Swift Package Manager and CocoaPods.** Keep
  `ios/advanced_webview/Package.swift` and `ios/advanced_webview.podspec` in
  sync (minimum iOS version, sources, resources). CI builds the example with each.
- Only symbols exported from `lib/advanced_webview.dart` are public API.
- **Workflow dependencies are locked.** `.github/workflows/actions.lock` pins every GitHub
  Action (including transitive ones) to a commit SHA. After changing any `uses:` in
  `.github/workflows/`, install the extension once (`gh extension install
  github/gh-actions-lock`), run `gh actions-lock` and commit the updated lockfile.
  CI (`verify-lockfile`) fails if it is out of sync.
- **Keep the API mapping current.** `website/data/api-mapping.json` maps each public Dart API
  to the native Android and iOS APIs it uses. Update it (English and Japanese text) when you
  add, rename or remove a public member or change the native API behind it;
  `cd website && bun run check:mapping` fails when it drifts.
- Format Dart code with `dart format` (generated `*.g.dart` files are excluded).
- Add or update tests for behaviour changes (`test/` uses a fake HostApi).
- Update `CHANGELOG.md` under `## Unreleased` for user-visible changes.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, keeping the PR focused on one topic.
3. Make sure `flutter analyze`, `flutter test` and formatting (Dart, and ktlint /
   swift-format for native code) pass locally.
4. Fill in the pull request template. CI builds the example app for Android and iOS.

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).

## Releasing (maintainers)

1. In a PR, set `version` in `pubspec.yaml` and rename `## Unreleased` in `CHANGELOG.md` to
   `## X.Y.Z - YYYY-MM-DD` (leave an empty `## Unreleased` above it). Merge it.
2. Tag the merge commit and push the tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. `.github/workflows/publish.yml` checks that the tag matches `pubspec.yaml`, has a
   `CHANGELOG.md` section and is on `main`, then runs analyze and tests, publishes to pub.dev and
   creates a GitHub Release from the changelog section. If the exact version is already on
   pub.dev, it still runs analyze and tests, but skips pub.dev credentials and publication
   (including the publish dry-run) and proceeds to the GitHub Release. A missing package
   (HTTP 404) follows the normal publish path; other HTTP/network errors or invalid package
   metadata stop the workflow rather than assuming publication succeeded.
   The first release must be published manually (`mise exec -- flutter pub publish`) before pushing
   its tag, and automated publishing enabled on pub.dev for subsequent versions.

## Using AI coding agents

AI-assisted contributions are welcome. Agent instructions live in [AGENTS.md](AGENTS.md)
and are shared through [APM](https://github.com/microsoft/apm) (`apm.yml`); see
AGENTS.md for setup. You are responsible for reviewing and understanding every line
you submit.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating
you are expected to uphold it.
