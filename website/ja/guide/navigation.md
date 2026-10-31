# ナビゲーション

`onNavigationRequest` で遷移を許可・拒否できます。

```dart
final controller = AdvancedWebViewController(
  onNavigationRequest: (request) => request.url.startsWith('https://')
      ? NavigationDecision.navigate
      : NavigationDecision.prevent,
);
```

コールバックは `Future<NavigationDecision>` を返しても構いません。

## 通知される遷移

以下が基本の通知範囲です。Android 固有の制約は後述します。

- **メインフレーム**の遷移だけが通知されます。
- ページ起点の遷移だけが通知されます（リンク、GET フォーム、`window.location`、リダイレクト）。
- コントローラから始めた読み込み（`loadUrl`、`loadHtmlString`、`reload`、`goBack`、`goForward`）は通知されません。

::: warning Android
Android は同期的に答える必要があるため、いったん遷移をキャンセルして Dart に問い合わせ、許可されたら
読み込み直します。読み込み直しは GET になるため、元のリダイレクトの流れやリクエスト情報が変わる場合があります。
:::

## 新しいウィンドウ

`window.open` や `target="_blank"` のリンクは新しいウィンドウを要求します。`onNewWindow` で処理します。

```dart
final controller = AdvancedWebViewController(
  onNewWindow: (url) => launchUrlString(url), // または別のコントローラで開く
);
```

`onNewWindow` を指定すると、WebView 自身は URL を読み込みません。指定しない場合は、両プラットフォームとも
同じ WebView で URL を読み込みます(`onNavigationRequest` も通ります)。Android では、一時的な WebView から
URL を取得し、すぐに破棄します。

## セキュリティ上の境界

Android の `shouldOverrideUrlLoading` は POST リクエストでは呼ばれません。
そのため POST フォーム送信は `onNavigationRequest` の対象外です。iOS と同一の判定範囲ではありません。
メインフレーム以外の遷移やサブリソースの要求もこの判定では制御しません。
両 OS とも Dart の判定コールバックが例外やプラットフォーム通信エラーで失敗した場合は遷移を許可します。
コールバックの Future が完了しない場合のタイムアウトも設けていません。

このデリゲートはすべてのネットワーク通信を制限する仕組みではありません。アプリからの `loadUrl` などは
呼出し前に scheme と host を検証し、`onNewWindow` の URL も処理前に検証してください。
JavaScript チャネルを利用する場合は iframe を含むコンテンツを信頼できる範囲に限定してください。
詳細は [JavaScript チャネルの信頼境界](./javascript#channel-trust-boundary)を参照してください。
