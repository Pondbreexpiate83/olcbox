package us.leaf3stones.hy2droid.proxy

import android.app.Activity
import android.os.Bundle
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Simple WebView activity that loads captcha from Go local HTTP server
 * No logic needed - Go sends UDP result directly to Hysteria2VpnService
 */
class CaptchaActivity : Activity() {

    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent.getStringExtra("url") ?: run {
            finish()
            return
        }

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.cacheMode = WebSettings.LOAD_NO_CACHE
            settings.userAgentString =
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) Gecko/20100101 Firefox/144.0"

            webViewClient = WebViewClient()
            webChromeClient = WebChromeClient()
        }

        setContentView(webView)
        webView.loadUrl(url)
    }
}