import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cookie.dart';
import 'navigation.dart';
import 'platform/event_dispatcher.dart';
import 'platform/messages.g.dart';
import 'settings.dart';
import 'user_script.dart';

/// Controls one native WebView.
///
/// The native view is created as soon as the controller is constructed and
/// lives until [dispose] is called, independently of the [AdvancedWebView]
/// widget.
class AdvancedWebViewController {
  AdvancedWebViewController({
    WebViewSettings settings = const WebViewSettings(),
    Map<String, JavaScriptMessageCallback> javaScriptChannels = const {},
    List<UserScript> userScripts = const [],
    this.onPageStarted,
    this.onPageFinished,
    this.onProgress,
    this.onTitleChanged,
    this.onWebResourceError,
    this.onNavigationRequest,
    this.onNewWindow,
    @visibleForTesting AdvancedWebViewHostApi? hostApi,
    @visibleForTesting WebViewEventDispatcher? dispatcher,
  }) : webViewId = _nextWebViewId++,
       _settings = settings,
       _javaScriptChannels = Map.unmodifiable(javaScriptChannels),
       _hostApi = hostApi ?? AdvancedWebViewHostApi(),
       _dispatcher = dispatcher ?? WebViewEventDispatcher.instance {
    _dispatcher.register(webViewId, _EventListener(this));
    _created = _hostApi.create(
      CreationParamsMessage(
        webViewId: webViewId,
        settings: settings.toMessage(),
        javaScriptChannelNames: _javaScriptChannels.keys.toList(),
        hasNavigationDelegate: onNavigationRequest != null,
        hasNewWindowDelegate: onNewWindow != null,
        userScripts: [for (final script in userScripts) script.toMessage()],
      ),
    );
  }

  static int _nextWebViewId = 0;

  /// Identifies this WebView across the platform channel.
  final int webViewId;

  final AdvancedWebViewHostApi _hostApi;
  final WebViewEventDispatcher _dispatcher;
  final Map<String, JavaScriptMessageCallback> _javaScriptChannels;
  late final Future<void> _created;
  WebViewSettings _settings;
  bool _isDisposed = false;

  final PageEventCallback? onPageStarted;
  final PageEventCallback? onPageFinished;
  final ProgressCallback? onProgress;
  final TitleChangedCallback? onTitleChanged;
  final WebResourceErrorCallback? onWebResourceError;

  /// Called for main-frame navigations started by the page (links, forms,
  /// `window.location`, redirects). Android does not report POST requests.
  /// Loads started by this controller
  /// ([loadUrl], [loadHtmlString], [reload], [goBack], [goForward]) are not
  /// reported. On Android an allowed navigation is re-issued as a GET, so the original
  /// redirect flow and request metadata may change. Callback or platform-channel
  /// errors allow navigation; this is not a complete network filter.
  final NavigationRequestCallback? onNavigationRequest;

  /// Called when the page asks for a new window (`window.open`, links with
  /// `target="_blank"`) with the URL it wants to open.
  ///
  /// When set, the WebView does not load the URL itself; open it wherever
  /// suits the app, for example in another controller or the system browser.
  /// When `null`, the URL loads in this WebView (and goes through
  /// [onNavigationRequest] like any page-initiated navigation).
  ///
  /// Android: `WebChromeClient.onCreateWindow(WebView, boolean, boolean, Message)`
  /// with `WebSettings.setSupportMultipleWindows(true)`; the URL is read from a
  /// temporary WebView that is destroyed right away.
  /// iOS: `WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)`.
  final NewWindowCallback? onNewWindow;

  /// Completes once the native WebView exists.
  Future<void> get ready => _created;

  WebViewSettings get settings => _settings;

  bool get isDisposed => _isDisposed;

  Future<void> loadUrl(String url, {Map<String, String> headers = const {}}) =>
      _call(() => _hostApi.loadUrl(webViewId, url, headers));

  Future<void> loadHtmlString(String html, {String? baseUrl}) =>
      _call(() => _hostApi.loadHtmlString(webViewId, html, baseUrl));

  Future<void> reload() => _call(() => _hostApi.reload(webViewId));

  Future<void> stopLoading() => _call(() => _hostApi.stopLoading(webViewId));

  Future<void> goBack() => _call(() => _hostApi.goBack(webViewId));

  Future<void> goForward() => _call(() => _hostApi.goForward(webViewId));

  Future<bool> canGoBack() => _call(() => _hostApi.canGoBack(webViewId));

  Future<bool> canGoForward() => _call(() => _hostApi.canGoForward(webViewId));

  Future<String?> currentUrl() => _call(() => _hostApi.getUrl(webViewId));

  Future<String?> title() => _call(() => _hostApi.getTitle(webViewId));

  /// Runs [source] and returns its result decoded from JSON
  /// (`null`, `bool`, `num`, `String`, `List` or `Map`).
  Future<Object?> runJavaScriptReturningResult(String source) async {
    final json = await _call(
      () => _hostApi.evaluateJavaScript(webViewId, source),
    );
    return json == null ? null : jsonDecode(json);
  }

  /// Runs [source] and ignores its result.
  Future<void> runJavaScript(String source) =>
      _call(() => _hostApi.evaluateJavaScript(webViewId, source));

  Future<void> updateSettings(WebViewSettings settings) async {
    await _call(() => _hostApi.updateSettings(webViewId, settings.toMessage()));
    _settings = settings;
  }

  /// Registers [script] to run in pages loaded from now on.
  ///
  /// It does not run in the page that is currently shown; load or reload a
  /// page afterwards. Scripts passed to the constructor are registered before
  /// the first load.
  ///
  /// Android: `WebViewCompat.addDocumentStartJavaScript(WebView, String, Set)`;
  /// requires `WebViewFeature.DOCUMENT_START_SCRIPT`. `atDocumentEnd` scripts
  /// are wrapped to wait for `DOMContentLoaded`.
  /// iOS: `WKUserContentController.addUserScript(_:)` with a `WKUserScript`.
  Future<void> addUserScript(UserScript script) =>
      _call(() => _hostApi.addUserScript(webViewId, script.toMessage()));

  /// Removes every script added with [addUserScript] or the constructor.
  ///
  /// Android: `ScriptHandler.remove()` for each registered script.
  /// iOS: `WKUserContentController.removeAllUserScripts()`; the JavaScript
  /// channel shims are registered again afterwards.
  Future<void> removeAllUserScripts() =>
      _call(() => _hostApi.removeAllUserScripts(webViewId));

  /// Stores [cookie] in the WebView's cookie store.
  ///
  /// Completes when the cookie has been stored; load or reload a page
  /// afterwards for it to be sent.
  ///
  /// Android and iOS differ: Android's cookie store is shared by all WebViews
  /// of the app, iOS's by all WebViews that use the default data store.
  ///
  /// Android: `CookieManager.setCookie(String, String, ValueCallback)`.
  /// iOS: `WKHTTPCookieStore.setCookie(_:)`.
  Future<void> setCookie(WebViewCookie cookie) =>
      _call(() => _hostApi.setCookie(webViewId, cookie.toMessage()));

  /// Returns the cookies the WebView would send to [url].
  ///
  /// Android and iOS differ: Android only reports [WebViewCookie.name] and
  /// [WebViewCookie.value]; the other fields are filled with the host of [url],
  /// `/` and `false`. iOS reports every attribute.
  ///
  /// Android: `CookieManager.getCookie(String)`.
  /// iOS: `WKHTTPCookieStore.allCookies()`, filtered by [url].
  Future<List<WebViewCookie>> getCookies(String url) async {
    final cookies = await _call(() => _hostApi.getCookies(webViewId, url));
    return cookies.map(WebViewCookie.fromMessage).toList();
  }

  /// Removes every cookie from the WebView's cookie store.
  ///
  /// Android: `CookieManager.removeAllCookies(ValueCallback)`.
  /// iOS: `WKHTTPCookieStore.allCookies()` and `deleteCookie(_:)` for each cookie.
  Future<void> clearCookies() => _call(() => _hostApi.clearCookies(webViewId));

  /// Destroys the native WebView. The controller cannot be used afterwards.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _dispatcher.unregister(webViewId);
    await _created;
    await _hostApi.dispose(webViewId);
  }

  Future<T> _call<T>(Future<T> Function() body) async {
    if (_isDisposed) {
      throw StateError('AdvancedWebViewController($webViewId) was disposed');
    }
    await _created;
    return body();
  }
}

/// Adapts platform messages to the public callbacks, keeping the
/// [WebViewEventListener] methods off the controller's public API.
class _EventListener implements WebViewEventListener {
  _EventListener(this._controller);

  final AdvancedWebViewController _controller;

  @override
  void onPageStarted(String url) => _controller.onPageStarted?.call(url);

  @override
  void onPageFinished(String url) => _controller.onPageFinished?.call(url);

  @override
  void onProgressChanged(int progress) =>
      _controller.onProgress?.call(progress);

  @override
  void onTitleChanged(String? title) => _controller.onTitleChanged?.call(title);

  @override
  void onReceivedError(WebResourceErrorMessage error) =>
      _controller.onWebResourceError?.call(
        WebResourceError(
          errorCode: error.errorCode,
          message: error.message,
          isMainFrame: error.isMainFrame,
          url: error.url,
        ),
      );

  @override
  Future<NavigationDecisionMessage> shouldOverrideUrlLoading(
    NavigationRequestMessage request,
  ) async {
    final callback = _controller.onNavigationRequest;
    if (callback == null) return NavigationDecisionMessage.navigate;
    final decision = await callback(
      NavigationRequest(url: request.url, isMainFrame: request.isMainFrame),
    );
    return switch (decision) {
      NavigationDecision.navigate => NavigationDecisionMessage.navigate,
      NavigationDecision.prevent => NavigationDecisionMessage.prevent,
    };
  }

  @override
  void onJavaScriptMessage(String channelName, String message) =>
      _controller._javaScriptChannels[channelName]?.call(message);

  @override
  void onNewWindowRequest(String url) => _controller.onNewWindow?.call(url);
}
