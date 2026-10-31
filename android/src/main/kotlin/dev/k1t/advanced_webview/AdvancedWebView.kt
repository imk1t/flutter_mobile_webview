package dev.k1t.advanced_webview

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Message
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.ScriptHandler
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.Log
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.coroutines.resume

/** One native WebView plus the clients that forward its callbacks to Dart. */
class AdvancedWebView(
    context: Context,
    params: CreationParamsMessage,
    private val flutterApi: AdvancedWebViewFlutterApi,
    private val scope: CoroutineScope,
    private val fileChooser: FileChooser,
) : PlatformView {
    val id: Long = params.webViewId

    // Created before a platform view exists; the real (Activity) context is
    // swapped in by [attachToContext] so dialogs and IME work correctly.
    private val contextWrapper = MutableContextWrapper(context)
    val webView: WebView = WebView(contextWrapper)

    private val hasNavigationDelegate = params.hasNavigationDelegate
    private val hasNewWindowDelegate = params.hasNewWindowDelegate
    private val scriptHandlers = mutableListOf<ScriptHandler>()
    private var isDestroyed = false

    init {
        webView.settings.domStorageEnabled = true
        // Without a delegate, window.open and target=_blank load in this WebView.
        webView.settings.setSupportMultipleWindows(hasNewWindowDelegate)
        webView.settings.javaScriptCanOpenWindowsAutomatically = true
        applySettings(params.settings)
        webView.webViewClient = Client()
        webView.webChromeClient = ChromeClient()
        params.javaScriptChannelNames.forEach(::addJavaScriptChannel)
        params.userScripts.forEach(::addUserScript)
    }

    fun attachToContext(context: Context) {
        contextWrapper.baseContext = context
        // A re-created platform view reuses this WebView; detach it from the
        // previous container so it can be added to the new one.
        (webView.parent as? ViewGroup)?.removeView(webView)
    }

    @SuppressLint("SetJavaScriptEnabled")
    fun applySettings(settings: WebViewSettingsMessage) {
        with(webView.settings) {
            javaScriptEnabled = settings.javaScriptEnabled
            mediaPlaybackRequiresUserGesture = settings.mediaPlaybackRequiresUserGesture
            setSupportZoom(settings.supportZoom)
            builtInZoomControls = settings.supportZoom
            displayZoomControls = false
            userAgentString = settings.userAgent ?: WebSettings.getDefaultUserAgent(webView.context)
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_AUTHENTICATION)) {
            WebSettingsCompat.setWebAuthenticationSupport(
                webView.settings,
                if (settings.passkeysEnabled) {
                    WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_FOR_APP
                } else {
                    WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_NONE
                },
            )
        }
        webView.setBackgroundColor(if (settings.transparentBackground) Color.TRANSPARENT else Color.WHITE)
    }

    suspend fun evaluateJavaScript(source: String): String? = suspendCancellableCoroutine { cont ->
        webView.evaluateJavascript(source) { result ->
            // Android already returns JSON; "null" covers both null and undefined.
            cont.resume(if (result == null || result == "null") null else result)
        }
    }

    fun addUserScript(script: UserScriptMessage) {
        check(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            "User scripts need a WebView that supports DOCUMENT_START_SCRIPT"
        }
        scriptHandlers += WebViewCompat.addDocumentStartJavaScript(webView, script.wrapped(), setOf("*"))
    }

    fun removeAllUserScripts() {
        scriptHandlers.forEach { it.remove() }
        scriptHandlers.clear()
    }

    /**
     * Document-start scripts run in every frame, so a main-frame-only script
     * checks `window.top`, and an at-document-end script waits for the DOM.
     */
    private fun UserScriptMessage.wrapped(): String {
        val frameGuard = if (mainFrameOnly) "if (window.top !== window) return;" else ""
        val schedule = if (injectionTime == UserScriptInjectionTimeMessage.AT_DOCUMENT_END) {
            "if (document.readyState === 'loading') " +
                "document.addEventListener('DOMContentLoaded', run); else run();"
        } else {
            "run();"
        }
        return "(function() { $frameGuard function run() {\n$source\n} $schedule })();"
    }

    suspend fun setCookie(cookie: CookieMessage) {
        val scheme = if (cookie.isSecure) "https" else "http"
        val url = "$scheme://${cookie.domain.trimStart('.')}${cookie.path}"
        val stored = suspendCancellableCoroutine { cont ->
            CookieManager.getInstance().setCookie(url, cookie.toSetCookieHeader()) { cont.resume(it) }
        }
        check(stored) { "The cookie '${cookie.name}' was rejected for $url" }
        CookieManager.getInstance().flush()
    }

    /** Android only exposes `name=value` pairs, so the other attributes are defaults. */
    fun getCookies(url: String): List<CookieMessage> {
        val host = Uri.parse(url).host.orEmpty()
        val header = CookieManager.getInstance().getCookie(url) ?: return emptyList()
        return header.split(";").mapNotNull { pair ->
            val separator = pair.indexOf('=')
            if (separator <= 0) return@mapNotNull null
            CookieMessage(
                name = pair.substring(0, separator).trim(),
                value = pair.substring(separator + 1).trim(),
                domain = host,
                path = "/",
                isSecure = false,
                isHttpOnly = false,
            )
        }
    }

    suspend fun clearCookies() {
        suspendCancellableCoroutine<Boolean> { cont ->
            CookieManager.getInstance().removeAllCookies { cont.resume(it) }
        }
        CookieManager.getInstance().flush()
    }

    @SuppressLint("JavascriptInterface", "AddJavascriptInterface")
    private fun addJavaScriptChannel(name: String) {
        webView.addJavascriptInterface(
            object {
                @JavascriptInterface
                fun postMessage(message: String) {
                    // Called on a JavaBridge thread; scope dispatches to main.
                    send { flutterApi.onJavaScriptMessage(id, name, message) }
                }
            },
            name,
        )
    }

    override fun getView(): View = webView

    override fun dispose() {
        // Lifetime is owned by Dart (AdvancedWebViewHostApi.dispose), not by the
        // platform view, so the WebView survives re-attachment.
    }

    fun destroy() {
        if (isDestroyed) return
        isDestroyed = true
        webView.stopLoading()
        webView.destroy()
    }

    /** Fire-and-forget call into Dart. Failures are logged, never thrown. */
    private fun send(block: suspend () -> Unit) {
        scope.launch {
            if (isDestroyed) return@launch
            try {
                block()
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to deliver event to Dart: ${e.message}")
            }
        }
    }

    private inner class Client : WebViewClient() {
        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            send { flutterApi.onPageStarted(id, url) }
        }

        override fun onPageFinished(view: WebView, url: String) {
            send { flutterApi.onPageFinished(id, url) }
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            val message = WebResourceErrorMessage(
                errorCode = error.errorCode.toLong(),
                message = error.description.toString(),
                isMainFrame = request.isForMainFrame,
                url = request.url.toString(),
            )
            send { flutterApi.onReceivedError(id, message) }
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            // Android needs a synchronous answer. For main-frame navigations we
            // cancel, ask Dart, and re-issue the load if allowed. Sub-frame
            // navigations cannot be re-issued, so they are always allowed.
            if (!hasNavigationDelegate || !request.isForMainFrame) return false
            val url = request.url.toString()
            scope.launch {
                val decision = try {
                    flutterApi.shouldOverrideUrlLoading(id, NavigationRequestMessage(url, true))
                } catch (e: Throwable) {
                    Log.w(TAG, "Navigation delegate failed, allowing navigation: ${e.message}")
                    NavigationDecisionMessage.NAVIGATE
                }
                if (decision == NavigationDecisionMessage.NAVIGATE && !isDestroyed) {
                    webView.loadUrl(url)
                }
            }
            return true
        }
    }

    private inner class ChromeClient : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) {
            send { flutterApi.onProgressChanged(id, newProgress.toLong()) }
        }

        override fun onReceivedTitle(view: WebView, title: String?) {
            send { flutterApi.onTitleChanged(id, title) }
        }

        override fun onShowFileChooser(
            webView: WebView,
            filePathCallback: ValueCallback<Array<Uri>>,
            fileChooserParams: FileChooserParams,
        ): Boolean = fileChooser.show(filePathCallback, fileChooserParams)

        override fun onCreateWindow(
            view: WebView,
            isDialog: Boolean,
            isUserGesture: Boolean,
            resultMsg: Message,
        ): Boolean {
            if (!hasNewWindowDelegate) return false
            // The URL is only known once the new window starts loading, so hand
            // the page a throwaway WebView, report the first URL it navigates
            // to, and destroy it.
            val popup = WebView(view.context)
            popup.webViewClient = object : WebViewClient() {
                private var reported = false

                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    report(view, request.url.toString())
                    return true
                }

                override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                    report(view, url)
                }

                private fun report(view: WebView, url: String) {
                    if (reported || url == "about:blank") return
                    reported = true
                    send { flutterApi.onNewWindowRequest(id, url) }
                    view.stopLoading()
                    view.post { view.destroy() }
                }
            }
            (resultMsg.obj as WebView.WebViewTransport).webView = popup
            resultMsg.sendToTarget()
            return true
        }
    }

    private fun CookieMessage.toSetCookieHeader(): String = buildString {
        append("$name=$value; Domain=$domain; Path=$path")
        expiresMillis?.let {
            val format = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US)
            format.timeZone = TimeZone.getTimeZone("GMT")
            append("; Expires=${format.format(Date(it))}")
        }
        if (isSecure) append("; Secure")
        if (isHttpOnly) append("; HttpOnly")
    }

    private companion object {
        const val TAG = "AdvancedWebView"
    }
}
