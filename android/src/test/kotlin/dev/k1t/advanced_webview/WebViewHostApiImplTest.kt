package dev.k1t.advanced_webview

import android.graphics.Color
import android.net.Uri
import android.os.Looper
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WebViewHostApiImplTest {
    private lateinit var messenger: BinaryMessenger
    private lateinit var scope: CoroutineScope
    private lateinit var registry: WebViewRegistry
    private lateinit var hostApi: WebViewHostApiImpl

    @Before
    fun setUp() {
        messenger = mock(BinaryMessenger::class.java)
        scope = MainScope()
        registry = WebViewRegistry()
        hostApi = WebViewHostApiImpl(
            RuntimeEnvironment.getApplication(),
            registry,
            AdvancedWebViewFlutterApi(messenger),
            scope,
        )
    }

    @After
    fun tearDown() {
        hostApi.disposeAll()
        scope.cancel()
    }

    @Test
    fun createRegistersTheWebViewById() {
        hostApi.create(params(webViewId = 7))

        assertEquals(7L, registry.get(7).id)
    }

    @Test
    fun createRejectsADuplicateId() {
        hostApi.create(params(webViewId = 1))

        assertFailsWith<IllegalStateException> { hostApi.create(params(webViewId = 1)) }
    }

    @Test
    fun unknownIdThrowsNotFound() {
        val error = assertFailsWith<FlutterError> { hostApi.reload(42) }

        assertEquals("not-found", error.code)
    }

    @Test
    fun disposeDestroysAndUnregisters() {
        hostApi.create(params(webViewId = 1))
        val webView = registry.get(1).webView

        hostApi.dispose(1)

        assertTrue(shadowOf(webView).wasDestroyCalled())
        assertFailsWith<FlutterError> { registry.get(1) }
        // Disposing twice is harmless.
        hostApi.dispose(1)
    }

    @Test
    fun loadUrlForwardsUrlAndHeaders() {
        hostApi.create(params(webViewId = 1))

        hostApi.loadUrl(1, "https://example.com/", mapOf("X-Test" to "1"))

        val shadow = shadowOf(registry.get(1).webView)
        assertEquals("https://example.com/", shadow.lastLoadedUrl)
        assertEquals(mapOf("X-Test" to "1"), shadow.lastAdditionalHttpHeaders)
    }

    @Test
    fun loadHtmlStringUsesTheBaseUrl() {
        hostApi.create(params(webViewId = 1))

        hostApi.loadHtmlString(1, "<p>hi</p>", "https://example.com/")

        val load = shadowOf(registry.get(1).webView).lastLoadDataWithBaseURL
        assertEquals("https://example.com/", load.baseUrl)
        assertEquals("<p>hi</p>", load.data)
        assertEquals("text/html", load.mimeType)
    }

    @Test
    fun settingsAreAppliedAtCreationAndOnUpdate() {
        hostApi.create(
            params(webViewId = 1, settings = settings(javaScriptEnabled = false, userAgent = "ua-1")),
        )
        val webView = registry.get(1).webView
        assertFalse(webView.settings.javaScriptEnabled)
        assertEquals("ua-1", webView.settings.userAgentString)

        hostApi.updateSettings(
            1,
            settings(javaScriptEnabled = true, supportZoom = false, transparentBackground = true, userAgent = "ua-2"),
        )

        assertTrue(webView.settings.javaScriptEnabled)
        assertFalse(webView.settings.supportZoom())
        assertEquals("ua-2", webView.settings.userAgentString)
        assertEquals(Color.TRANSPARENT, shadowOf(webView).backgroundColor)
    }

    @Test
    fun passkeysCanBeEnabledAndDisabledOnTheSameWebView() {
        mockStatic(WebViewFeature::class.java).use { features ->
            features.`when`<Boolean> { WebViewFeature.isFeatureSupported(WebViewFeature.WEB_AUTHENTICATION) }
                .thenReturn(true)
            mockStatic(WebSettingsCompat::class.java).use { compat ->
                hostApi.create(params(webViewId = 1, settings = settings(passkeysEnabled = true)))
                val nativeSettings = registry.get(1).webView.settings
                compat.verify {
                    WebSettingsCompat.setWebAuthenticationSupport(
                        nativeSettings,
                        WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_FOR_APP,
                    )
                }
                compat.clearInvocations()
                hostApi.updateSettings(1, settings(passkeysEnabled = false))
                compat.verify {
                    WebSettingsCompat.setWebAuthenticationSupport(
                        nativeSettings,
                        WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_NONE,
                    )
                }
            }
        }
    }

    @Test
    fun unsupportedWebAuthenticationRemainsANoOp() {
        mockStatic(WebViewFeature::class.java).use { features ->
            features.`when`<Boolean> { WebViewFeature.isFeatureSupported(WebViewFeature.WEB_AUTHENTICATION) }
                .thenReturn(false)
            mockStatic(WebSettingsCompat::class.java).use { compat ->
                hostApi.create(params(webViewId = 1, settings = settings(passkeysEnabled = true)))
                hostApi.updateSettings(1, settings(passkeysEnabled = false))
                compat.verifyNoInteractions()
            }
        }
    }

    @Test
    fun javaScriptChannelsForwardMessagesToDart() {
        hostApi.create(params(webViewId = 3, channels = listOf("Echo")))
        val channel = shadowOf(registry.get(3).webView).getJavascriptInterface("Echo")
        assertNotNull(channel)

        channel.javaClass.getMethod("postMessage", String::class.java).invoke(channel, "hi")
        shadowOf(Looper.getMainLooper()).idle()

        verify(messenger).send(
            eq("dev.flutter.pigeon.advanced_webview.AdvancedWebViewFlutterApi.onJavaScriptMessage"),
            any(),
            any(),
        )
    }

    @Test
    fun navigationIsNotInterceptedWithoutADelegate() {
        hostApi.create(params(webViewId = 1, hasNavigationDelegate = false))
        val webView = registry.get(1).webView

        assertFalse(shouldOverride(webView, "https://example.com/", isMainFrame = true))
    }

    @Test
    fun onlyMainFrameNavigationsAreSentToTheDelegate() {
        hostApi.create(params(webViewId = 1, hasNavigationDelegate = true))
        val webView = registry.get(1).webView

        // Main frame: cancelled now, re-loaded once Dart allows it.
        assertTrue(shouldOverride(webView, "https://example.com/", isMainFrame = true))
        assertFalse(shouldOverride(webView, "https://example.com/frame", isMainFrame = false))
    }

    @Test
    fun factoryReturnsTheExistingInstanceAndDetachesIt() {
        hostApi.create(params(webViewId = 5))
        val instance = registry.get(5)
        val oldParent = FrameLayout(RuntimeEnvironment.getApplication())
        oldParent.addView(instance.webView)

        val view = AdvancedWebViewFactory(registry)
            .create(RuntimeEnvironment.getApplication(), 0, mapOf("webViewId" to 5))

        assertSame(instance, view)
        assertNull(instance.webView.parent)
    }

    private fun shouldOverride(webView: WebView, url: String, isMainFrame: Boolean): Boolean {
        val request = mock(WebResourceRequest::class.java)
        `when`(request.url).thenReturn(Uri.parse(url))
        `when`(request.isForMainFrame).thenReturn(isMainFrame)
        return shadowOf(webView).webViewClient.shouldOverrideUrlLoading(webView, request)
    }

    private fun params(
        webViewId: Long,
        settings: WebViewSettingsMessage = settings(),
        channels: List<String> = emptyList(),
        hasNavigationDelegate: Boolean = false,
        hasNewWindowDelegate: Boolean = false,
        userScripts: List<UserScriptMessage> = emptyList(),
    ) = CreationParamsMessage(
        webViewId,
        settings,
        channels,
        hasNavigationDelegate,
        hasNewWindowDelegate,
        userScripts,
    )

    private fun settings(
        javaScriptEnabled: Boolean = true,
        supportZoom: Boolean = true,
        transparentBackground: Boolean = false,
        userAgent: String? = null,
        passkeysEnabled: Boolean = false,
    ) = WebViewSettingsMessage(
        javaScriptEnabled = javaScriptEnabled,
        mediaPlaybackRequiresUserGesture = true,
        allowsInlineMediaPlayback = false,
        supportZoom = supportZoom,
        transparentBackground = transparentBackground,
        passkeysEnabled = passkeysEnabled,
        userAgent = userAgent,
    )
}
