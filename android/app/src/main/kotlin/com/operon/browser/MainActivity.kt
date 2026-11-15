package com.operon.browser

import android.content.Context
import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Bridges Android-native capabilities to Dart:
 * - [CHANNEL]: shared text & `VIEW` intents
 * - [SECURE_CHANNEL]: Android Keystore AES-GCM secret storage for API keys
 * - [FILES_CHANNEL]: opening downloaded files via FileProvider
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShare = sharedFrom(intent)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val created = MethodChannel(messenger, CHANNEL)
        created.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialShared" -> {
                    result.success(pendingShare)
                    pendingShare = null
                    // The launch intent stays attached to the activity; without
                    // this an activity re-create would replay the same share.
                    setIntent(Intent(Intent.ACTION_MAIN))
                }
                "shareText" -> {
                    val text = call.argument<String>("text").orEmpty()
                    result.success(shareText(text))
                }
                else -> result.notImplemented()
            }
        }
        channel = created

        MethodChannel(messenger, SECURE_CHANNEL).setMethodCallHandler { call, result ->
            val key = call.argument<String>("key").orEmpty()
            try {
                when (call.method) {
                    "write" -> {
                        if (key.isEmpty()) {
                            result.success(false)
                        } else {
                            val value = call.argument<String>("value").orEmpty()
                            writeSecret(key, value)
                            result.success(true)
                        }
                    }
                    "read" -> {
                        result.success(if (key.isEmpty()) null else readSecret(key))
                    }
                    "delete" -> {
                        if (key.isNotEmpty()) deleteSecret(key)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("secure_storage_error", e.message, null)
            }
        }

        MethodChannel(messenger, FILES_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFile" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val mime = call.argument<String>("mimeType")
                    result.success(openFile(path, mime))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Opens the system share sheet. Returns false when there is nothing to send. */
    private fun shareText(text: String): Boolean {
        if (text.isBlank()) return false
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        val chooser = Intent.createChooser(send, null)
        startActivity(chooser)
        return true
    }

    private fun openFile(path: String, mimeType: String?): Boolean {
        if (path.isBlank()) return false
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file,
            )
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType?.takeIf { it.isNotBlank() } ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(viewIntent, null))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun secretPrefs() =
        applicationContext.getSharedPreferences(SECRET_PREFS, Context.MODE_PRIVATE)

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER,
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun writeSecret(key: String, value: String) {
        if (value.isEmpty()) {
            deleteSecret(key)
            return
        }
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val payload = ByteArray(iv.size + ciphertext.size)
        System.arraycopy(iv, 0, payload, 0, iv.size)
        System.arraycopy(ciphertext, 0, payload, iv.size, ciphertext.size)
        val encoded = Base64.encodeToString(payload, Base64.NO_WRAP)
        secretPrefs().edit().putString(key, encoded).apply()
    }

    private fun readSecret(key: String): String? {
        val encoded = secretPrefs().getString(key, null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            if (payload.size <= GCM_IV_BYTES) return null
            val iv = payload.copyOfRange(0, GCM_IV_BYTES)
            val ciphertext = payload.copyOfRange(GCM_IV_BYTES, payload.size)
            val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(),
                GCMParameterSpec(GCM_TAG_BITS, iv),
            )
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun deleteSecret(key: String) {
        secretPrefs().edit().remove(key).apply()
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
        private const val SECURE_CHANNEL = "operon/secure_storage"
        private const val FILES_CHANNEL = "operon/files"
        private const val SECRET_PREFS = "operon_secure_secrets"
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val KEY_ALIAS = "operon_api_key_master_v1"
        private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
    }
}
