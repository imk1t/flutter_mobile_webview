import Flutter
import UIKit
import WebKit

/// One native WKWebView plus the delegates that forward its callbacks to Dart.
final class AdvancedWebView: NSObject, FlutterPlatformView {
  let id: Int64
  let webView: WKWebView

  private let flutterApi: AdvancedWebViewFlutterApi
  private let hasNavigationDelegate: Bool
  private let hasNewWindowDelegate: Bool
  private var javaScriptChannelNames: [String] = []
  private var observations: [NSKeyValueObservation] = []
  private var isDestroyed = false
  /// URL of the load started by `load(_:)` / `loadHTMLString(_:baseURL:)`
  /// whose policy decision has not arrived yet.
  private var pendingAppInitiatedURL: String?

  init(params: CreationParamsMessage, flutterApi: AdvancedWebViewFlutterApi) {
    self.id = params.webViewId
    self.flutterApi = flutterApi
    self.hasNavigationDelegate = params.hasNavigationDelegate
    self.hasNewWindowDelegate = params.hasNewWindowDelegate

    // Some WKWebView options can only be set at creation time.
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = params.settings.allowsInlineMediaPlayback
    configuration.mediaTypesRequiringUserActionForPlayback =
      params.settings.mediaPlaybackRequiresUserGesture ? .all : []
    // Same as Android: let scripts call window.open without a user gesture.
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    self.webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()

    webView.navigationDelegate = self
    webView.uiDelegate = self
    apply(settings: params.settings)
    params.javaScriptChannelNames.forEach(addJavaScriptChannel)
    params.userScripts.forEach(addUserScript)
    observeProperties()
  }

  func view() -> UIView {
    return webView
  }

  func apply(settings: WebViewSettingsMessage) {
    webView.configuration.defaultWebpagePreferences.allowsContentJavaScript =
      settings.javaScriptEnabled
    webView.customUserAgent = settings.userAgent
    webView.isOpaque = !settings.transparentBackground
    webView.backgroundColor = settings.transparentBackground ? .clear : .white
    webView.scrollView.backgroundColor = webView.backgroundColor
  }

  /// Loads a request started by the app. Like Android, it does not consult
  /// the navigation delegate.
  func load(_ request: URLRequest) {
    pendingAppInitiatedURL = request.url?.absoluteString
    webView.load(request)
  }

  /// Loads an HTML string started by the app without consulting the
  /// navigation delegate.
  func loadHTMLString(_ html: String, baseURL: URL?) {
    pendingAppInitiatedURL = (baseURL ?? URL(string: "about:blank"))?.absoluteString
    webView.loadHTMLString(html, baseURL: baseURL)
  }

  /// WKWebView must be used on the main thread. Without `@MainActor` this
  /// `async` function runs on the global executor, calls WKWebView off the
  /// main thread and can hang.
  @MainActor
  func evaluateJavaScript(_ source: String) async throws -> String? {
    // The completion-handler API is used on purpose: the async overload
    // cannot represent `undefined`/`null` results.
    let result: Any? = try await withCheckedThrowingContinuation { continuation in
      webView.evaluateJavaScript(source) { value, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: value)
        }
      }
    }
    guard let value = result, !(value is NSNull) else { return nil }
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    return String(data: data, encoding: .utf8)
  }

  @MainActor
  func setCookie(_ cookie: CookieMessage) async throws {
    var properties: [HTTPCookiePropertyKey: Any] = [
      .name: cookie.name,
      .value: cookie.value,
      .domain: cookie.domain,
      .path: cookie.path,
    ]
    if let millis = cookie.expiresMillis {
      properties[.expires] = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
    if cookie.isSecure { properties[.secure] = "TRUE" }
    if cookie.isHttpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
    guard let httpCookie = HTTPCookie(properties: properties) else {
      throw PigeonError(
        code: "invalid-cookie", message: "Invalid cookie: \(cookie.name)", details: nil)
    }
    await webView.configuration.websiteDataStore.httpCookieStore.setCookie(httpCookie)
  }

  /// Returns the cookies WebKit would send to `url`.
  @MainActor
  func cookies(for url: URL) async -> [CookieMessage] {
    let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    let host = url.host?.lowercased() ?? ""
    // URL.path can strip a trailing slash; cookie matching needs the request path verbatim.
    let requestPath =
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
    let path = requestPath.isEmpty ? "/" : requestPath
    let isSecureScheme = url.scheme?.lowercased() == "https"
    return all.filter { cookie in
      let domain = cookie.domain.lowercased()
      let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
      let hostMatches = host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare))
      let cookiePath = cookie.path
      let pathMatches =
        path == cookiePath
        || (path.hasPrefix(cookiePath)
          && (cookiePath.hasSuffix("/") || path.hasPrefix(cookiePath + "/")))
      return hostMatches && pathMatches && (!cookie.isSecure || isSecureScheme)
    }.map { cookie in
      CookieMessage(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
        isSecure: cookie.isSecure,
        isHttpOnly: cookie.isHTTPOnly,
        expiresMillis: cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) })
    }
  }

  @MainActor
  func clearCookies() async {
    let store = webView.configuration.websiteDataStore.httpCookieStore
    for cookie in await store.allCookies() {
      await store.deleteCookie(cookie)
    }
  }

  func destroy() {
    guard !isDestroyed else { return }
    isDestroyed = true
    observations.removeAll()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeAllScriptMessageHandlers()
  }

  func addUserScript(_ script: UserScriptMessage) {
    let time: WKUserScriptInjectionTime =
      script.injectionTime == .atDocumentStart ? .atDocumentStart : .atDocumentEnd
    webView.configuration.userContentController.addUserScript(
      WKUserScript(
        source: script.source, injectionTime: time, forMainFrameOnly: script.mainFrameOnly))
  }

  /// Removes the scripts added by the app. WebKit has no way to remove a single
  /// script, so the JavaScript channel shims are registered again.
  func removeAllUserScripts() {
    webView.configuration.userContentController.removeAllUserScripts()
    javaScriptChannelNames.forEach(addChannelShim)
  }

  private func addJavaScriptChannel(_ name: String) {
    javaScriptChannelNames.append(name)
    webView.configuration.userContentController.add(WeakScriptMessageHandler(self), name: name)
    addChannelShim(name)
  }

  private func addChannelShim(_ name: String) {
    let controller = webView.configuration.userContentController
    // Expose the same `window.<name>.postMessage(String)` shape as Android.
    let source = """
      window['\(name)'] = { postMessage: function(m) { \
      window.webkit.messageHandlers['\(name)'].postMessage(String(m)); } };
      """
    controller.addUserScript(
      WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
  }

  private func observeProperties() {
    observations = [
      webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
        let progress = Int64((webView.estimatedProgress * 100).rounded())
        self?.send { api, id in try await api.onProgressChanged(webViewId: id, progress: progress) }
      },
      webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
        let title = webView.title
        self?.send { api, id in try await api.onTitleChanged(webViewId: id, title: title) }
      },
    ]
  }

  /// Fire-and-forget call into Dart. Failures are logged, never thrown.
  private func send(_ block: @escaping (AdvancedWebViewFlutterApi, Int64) async throws -> Void) {
    let api = flutterApi
    let id = self.id
    Task { @MainActor [weak self] in
      guard let self = self, !self.isDestroyed else { return }
      do {
        try await block(api, id)
      } catch {
        NSLog("AdvancedWebView: failed to deliver event to Dart: \(error)")
      }
    }
  }

  private func reportError(_ error: Error, url: URL?) {
    let nsError = error as NSError
    // Navigations cancelled by us (e.g. a delegate decision) are not errors.
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
    let message = WebResourceErrorMessage(
      errorCode: Int64(nsError.code),
      message: nsError.localizedDescription,
      isMainFrame: true,
      url: url?.absoluteString
    )
    send { api, id in try await api.onReceivedError(webViewId: id, error: message) }
  }
}

extension AdvancedWebView: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    let url = webView.url?.absoluteString ?? ""
    send { api, id in try await api.onPageStarted(webViewId: id, url: url) }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let url = webView.url?.absoluteString ?? ""
    send { api, id in try await api.onPageFinished(webViewId: id, url: url) }
  }

  func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {
    reportError(error, url: webView.url)
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    reportError(error, url: webView.url)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    // Same rules as Android: only main-frame navigations started by the page
    // reach Dart. App-initiated loads, reloads and back/forward never do.
    let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
    guard hasNavigationDelegate, isMainFrame, let url = navigationAction.request.url else {
      decisionHandler(.allow)
      return
    }
    if let pending = pendingAppInitiatedURL, pending == url.absoluteString {
      pendingAppInitiatedURL = nil
      decisionHandler(.allow)
      return
    }
    if navigationAction.navigationType == .reload
      || navigationAction.navigationType == .backForward
    {
      decisionHandler(.allow)
      return
    }
    let request = NavigationRequestMessage(url: url.absoluteString, isMainFrame: true)
    let api = flutterApi
    let id = self.id
    Task { @MainActor in
      let decision: NavigationDecisionMessage
      do {
        decision = try await api.shouldOverrideUrlLoading(webViewId: id, request: request)
      } catch {
        NSLog("AdvancedWebView: navigation delegate failed, allowing navigation: \(error)")
        decision = .navigate
      }
      decisionHandler(decision == .navigate ? .allow : .cancel)
    }
  }
}

extension AdvancedWebView: WKUIDelegate {
  /// `window.open` and `target="_blank"`. WebKit never opens a window on its
  /// own here: the URL is either reported to Dart or loaded in this WebView,
  /// like Android without a delegate.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
      return nil
    }
    if hasNewWindowDelegate {
      let target = url.absoluteString
      send { api, id in try await api.onNewWindowRequest(webViewId: id, url: target) }
    } else {
      webView.load(navigationAction.request)
    }
    return nil
  }
}

extension AdvancedWebView: WKScriptMessageHandler {
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    let channelName = message.name
    let body = (message.body as? String) ?? String(describing: message.body)
    send { api, id in
      try await api.onJavaScriptMessage(webViewId: id, channelName: channelName, message: body)
    }
  }
}

/// WKUserContentController retains its handlers strongly; this breaks the cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var target: WKScriptMessageHandler?

  init(_ target: WKScriptMessageHandler) {
    self.target = target
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
