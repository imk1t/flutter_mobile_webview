import Flutter
import UIKit
import WebKit
import XCTest

@testable import advanced_webview

// Unit tests for the Swift implementation. They run in the example app's test
// host: `xcodebuild test -workspace Runner.xcworkspace -scheme Runner`.
@MainActor
final class RunnerTests: XCTestCase {

  func testCreateRegistersTheWebViewById() throws {
    let (hostApi, registry, _) = makeHostApi()

    try hostApi.create(params: params(webViewId: 7))

    XCTAssertEqual(try registry.get(7).id, 7)
  }

  func testCreateRejectsADuplicateId() throws {
    let (hostApi, _, _) = makeHostApi()
    try hostApi.create(params: params(webViewId: 1))

    XCTAssertThrowsError(try hostApi.create(params: params(webViewId: 1))) { error in
      XCTAssertEqual((error as? PigeonError)?.code, "already-exists")
    }
  }

  func testUnknownIdThrowsNotFound() {
    let (hostApi, _, _) = makeHostApi()

    XCTAssertThrowsError(try hostApi.reload(webViewId: 42)) { error in
      XCTAssertEqual((error as? PigeonError)?.code, "not-found")
    }
  }

  func testDisposeUnregisters() throws {
    let (hostApi, registry, _) = makeHostApi()
    try hostApi.create(params: params(webViewId: 1))

    try hostApi.dispose(webViewId: 1)

    XCTAssertThrowsError(try registry.get(1))
    // Disposing twice is harmless.
    XCTAssertNoThrow(try hostApi.dispose(webViewId: 1))
  }

  func testLoadUrlRejectsAnInvalidUrl() throws {
    let (hostApi, _, _) = makeHostApi()
    try hostApi.create(params: params(webViewId: 1))

    XCTAssertThrowsError(try hostApi.loadUrl(webViewId: 1, url: "", headers: [:])) { error in
      XCTAssertEqual((error as? PigeonError)?.code, "invalid-url")
    }
  }

  func testSettingsAreAppliedAtCreationAndOnUpdate() throws {
    let (hostApi, registry, _) = makeHostApi()
    try hostApi.create(
      params: params(webViewId: 1, settings: settings(javaScriptEnabled: false, userAgent: "ua-1")))
    let webView = try registry.get(1).webView
    XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    XCTAssertEqual(webView.customUserAgent, "ua-1")
    XCTAssertTrue(webView.isOpaque)

    try hostApi.updateSettings(
      webViewId: 1,
      settings: settings(javaScriptEnabled: true, transparentBackground: true, userAgent: "ua-2"))

    XCTAssertTrue(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    XCTAssertEqual(webView.customUserAgent, "ua-2")
    XCTAssertFalse(webView.isOpaque)
  }

  func testCreationOnlySettingsConfigureTheWebView() throws {
    let (hostApi, registry, _) = makeHostApi()
    try hostApi.create(
      params: params(
        webViewId: 1,
        settings: settings(mediaPlaybackRequiresUserGesture: false, allowsInlineMediaPlayback: true)
      ))

    let configuration = try registry.get(1).webView.configuration
    XCTAssertTrue(configuration.allowsInlineMediaPlayback)
    XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, [])
  }

  func testJavaScriptChannelsInjectPostMessageShim() throws {
    let (hostApi, registry, _) = makeHostApi()
    try hostApi.create(params: params(webViewId: 1, channels: ["Echo"]))

    let scripts = try registry.get(1).webView.configuration.userContentController.userScripts
    XCTAssertEqual(scripts.count, 1)
    XCTAssertTrue(scripts[0].source.contains("window['Echo']"))
    XCTAssertEqual(scripts[0].injectionTime, .atDocumentStart)
  }

  func testEvaluateJavaScriptReturnsJson() async throws {
    let (hostApi, _, _) = makeHostApi()
    try hostApi.create(params: params(webViewId: 1))
    defer { hostApi.disposeAll() }

    let number = try await hostApi.evaluateJavaScript(webViewId: 1, source: "1 + 2")
    let object = try await hostApi.evaluateJavaScript(webViewId: 1, source: "({a: [1, 'b']})")
    let string = try await hostApi.evaluateJavaScript(webViewId: 1, source: "'text'")
    let undefined = try await hostApi.evaluateJavaScript(webViewId: 1, source: "undefined")
    let null = try await hostApi.evaluateJavaScript(webViewId: 1, source: "null")

    XCTAssertEqual(number, "3")
    XCTAssertEqual(object, #"{"a":[1,"b"]}"#)
    XCTAssertEqual(string, #""text""#)
    XCTAssertNil(undefined)
    XCTAssertNil(null)
  }

  func testCookiePathsMatchOnlyAtPathBoundaries() async throws {
    let (hostApi, registry, _) = makeHostApi()
    try hostApi.create(params: params(webViewId: 1))
    let instance = try registry.get(1)
    let store = instance.webView.configuration.websiteDataStore.httpCookieStore
    let cookies = [("root", "/"), ("exact", "/account"), ("slash", "/account/")].map { name, path in
      HTTPCookie(properties: [.name: name, .value: "1", .domain: "path-match.test", .path: path])!
    }
    for cookie in cookies { await store.setCookie(cookie) }
    let cases: [(String, Set<String>)] = [
      ("", ["root"]), ("/", ["root"]), ("/account", ["root", "exact"]),
      ("/account/", ["root", "exact", "slash"]),
      ("/account/child", ["root", "exact", "slash"]),
      ("/account%2Fchild", ["root"]),
      ("/accounting", ["root"]), ("/accounting/child", ["root"]),
    ]
    for (path, expected) in cases {
      let result = try await hostApi.getCookies(webViewId: 1, url: "https://path-match.test" + path)
      XCTAssertEqual(Set(result.map(\.name)), expected, "Path: \(path)")
    }
    for cookie in cookies { await store.deleteCookie(cookie) }
  }

  func testFactoryReturnsTheExistingInstance() throws {
    let (hostApi, registry, _) = makeHostApi()
    try hostApi.create(params: params(webViewId: 5))
    let instance = try registry.get(5)

    let view = AdvancedWebViewFactory(registry: registry).create(
      withFrame: .zero, viewIdentifier: 0, arguments: ["webViewId": 5])

    XCTAssertTrue(view === instance)
  }

  // MARK: - Helpers

  private func makeHostApi() -> (WebViewHostApiImpl, WebViewRegistry, FakeBinaryMessenger) {
    let messenger = FakeBinaryMessenger()
    let registry = WebViewRegistry()
    let hostApi = WebViewHostApiImpl(
      registry: registry, flutterApi: AdvancedWebViewFlutterApi(binaryMessenger: messenger))
    addTeardownBlock { @MainActor in hostApi.disposeAll() }
    return (hostApi, registry, messenger)
  }

  private func params(
    webViewId: Int64,
    settings: WebViewSettingsMessage? = nil,
    channels: [String] = [],
    hasNavigationDelegate: Bool = false,
    hasNewWindowDelegate: Bool = false,
    userScripts: [UserScriptMessage] = []
  ) -> CreationParamsMessage {
    return CreationParamsMessage(
      webViewId: webViewId,
      settings: settings ?? self.settings(),
      javaScriptChannelNames: channels,
      hasNavigationDelegate: hasNavigationDelegate,
      hasNewWindowDelegate: hasNewWindowDelegate,
      userScripts: userScripts)
  }

  private func settings(
    javaScriptEnabled: Bool = true,
    mediaPlaybackRequiresUserGesture: Bool = true,
    allowsInlineMediaPlayback: Bool = false,
    transparentBackground: Bool = false,
    userAgent: String? = nil
  ) -> WebViewSettingsMessage {
    return WebViewSettingsMessage(
      javaScriptEnabled: javaScriptEnabled,
      mediaPlaybackRequiresUserGesture: mediaPlaybackRequiresUserGesture,
      allowsInlineMediaPlayback: allowsInlineMediaPlayback,
      supportZoom: true,
      transparentBackground: transparentBackground,
      passkeysEnabled: false,
      userAgent: userAgent)
  }
}

/// Records outgoing FlutterApi messages; never replies.
private final class FakeBinaryMessenger: NSObject, FlutterBinaryMessenger {
  private(set) var sentChannels: [String] = []

  func send(onChannel channel: String, message: Data?) {
    sentChannels.append(channel)
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    sentChannels.append(channel)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    return 0
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
