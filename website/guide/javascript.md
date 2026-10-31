# JavaScript

## Running JavaScript

```dart
// Ignore the result
await controller.runJavaScript('document.body.style.background = "red"');

// The result is JSON-encoded natively and decoded in Dart:
// null, bool, num, String, List or Map. `undefined` becomes null.
final title = await controller.runJavaScriptReturningResult('document.title');
```

## JavaScript channels

Channels send messages from the page to Dart. Register them when you create the controller:

```dart
final controller = AdvancedWebViewController(
  javaScriptChannels: {'Bridge': (message) => print(message)},
);
```

On both platforms the page calls the same API:

```js
window.Bridge.postMessage('hello');
```

Messages are strings. Use `JSON.stringify` on the JavaScript side if you need to send
structured data.

## User scripts

User scripts are injected into every page the WebView loads, before or after the DOM is parsed.

```dart
final controller = AdvancedWebViewController(
  userScripts: const [
    UserScript(source: 'window.isApp = true;'), // before the page's own scripts
    UserScript(
      source: 'document.body.classList.add("in-app");',
      injectionTime: UserScriptInjectionTime.atDocumentEnd, // after DOMContentLoaded
    ),
  ],
);

await controller.addUserScript(const UserScript(source: '...'));
await controller.removeAllUserScripts();
```

Scripts only affect pages loaded after they are added. `mainFrameOnly` defaults to `true`.

Android needs a WebView that supports `DOCUMENT_START_SCRIPT` (the system WebView on current
devices does); the plugin wraps the source so `mainFrameOnly` and `atDocumentEnd` behave like iOS.

## Channel trust boundary

Channels are exposed to every frame, including iframes. Android uses `addJavascriptInterface`;
iOS injects the channel shim with `forMainFrameOnly: false`.
Dart receives the channel name and string message, with no sender origin or frame information.
`UserScript.mainFrameOnly` controls user scripts only; it does not restrict channel exposure.

Load only trusted content, including its iframes, in a WebView with channels. Validate message
formats and requested operations; do not authorize privileged actions or return credentials based
on a message alone. JavaScript is enabled by default. If it is unnecessary, use
`javaScriptEnabled: false` and omit channel registration.
The navigation delegate also has [limitations](./navigation#security-boundary).
