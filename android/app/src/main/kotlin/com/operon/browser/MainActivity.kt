package com.operon.browser

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards shared text and `VIEW` links to Dart over [CHANNEL].
 *
 * The raw text is passed through untouched; parsing lives in Dart so the same
 * rules can be unit tested without an Android device.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShare = sharedFrom(intent)

        val created = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        created.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialShared" -> {
                    result.success(pendingShare)
                    pendingShare = null
                    // The launch intent stays attached to the activity; without
                    // this an activity re-create would replay the same share.
                    setIntent(Intent(Intent.ACTION_MAIN))
                }
                else -> result.notImplemented()
            }
        }
        channel = created
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val shared = sharedFrom(intent) ?: return
        val active = channel
        if (active == null) {
            // Dart is not listening yet; keep it for the initial handshake.
            pendingShare = shared
        } else {
            active.invokeMethod("shared", shared)
            setIntent(Intent(Intent.ACTION_MAIN))
        }
    }

    private fun sharedFrom(intent: Intent?): String? {
        return when (intent?.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }
    }

    companion object {
        private const val CHANNEL = "operon/share"
    }
}
