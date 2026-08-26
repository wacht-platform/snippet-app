package com.snippet

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "snippet/share"
    private var channel: MethodChannel? = null
    private var pending: HashMap<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "takePending") {
                    val payload = pending
                    pending = null
                    result.success(payload)
                } else {
                    result.notImplemented()
                }
            }
        }
        deliver(intent, fromNewIntent = false)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Intent is also handled after the engine is ready so a cold start
        // still reaches Dart.
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliver(intent, fromNewIntent = true)
    }

    private fun deliver(intent: Intent?, fromNewIntent: Boolean) {
        val payload = parse(intent) ?: return
        pending = payload
        if (fromNewIntent) {
            channel?.invokeMethod("shareReceived", payload)
        }
    }

    private fun parse(intent: Intent?): HashMap<String, Any>? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> parseSend(intent, multiple = false)
            Intent.ACTION_SEND_MULTIPLE -> parseSend(intent, multiple = true)
            Intent.ACTION_PROCESS_TEXT -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
                    ?.toString()
                    ?.trim()
                    .orEmpty()
                if (text.isEmpty()) null
                else hashMapOf("type" to "text", "text" to text)
            }
            else -> null
        }
    }

    private fun parseSend(intent: Intent, multiple: Boolean): HashMap<String, Any>? {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val uris = mutableListOf<Uri>()
        if (multiple) {
            val list = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            if (list != null) uris.addAll(list)
        } else {
            val one = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            if (one != null) uris.add(one)
        }
        if (uris.isEmpty() && text.isEmpty()) return null
        if (uris.isEmpty()) {
            return hashMapOf("type" to "text", "text" to text)
        }
        val paths = ArrayList<String>()
        val names = ArrayList<String>()
        var anyImage = false
        for (uri in uris) {
            val copied = copyUri(uri) ?: continue
            paths.add(copied.first)
            names.add(copied.second)
            if (isImageName(copied.second) || (intent.type?.startsWith("image/") == true)) {
                anyImage = true
            }
        }
        if (paths.isEmpty() && text.isEmpty()) return null
        val type = when {
            paths.isEmpty() -> "text"
            anyImage && paths.size == 1 && text.isEmpty() -> "image"
            else -> "file"
        }
        val out = hashMapOf<String, Any>("type" to type, "paths" to paths, "names" to names)
        if (text.isNotEmpty()) out["text"] = text
        return out
    }

    private fun copyUri(uri: Uri): Pair<String, String>? {
        val name = queryDisplayName(uri) ?: uri.lastPathSegment ?: "shared.bin"
        val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val dest = File(cacheDir, "share_${System.currentTimeMillis()}_$safe")
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            } ?: return null
            Pair(dest.absolutePath, name)
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        val projection = arrayOf(android.provider.OpenableColumns.DISPLAY_NAME)
        return try {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun isImageName(name: String): Boolean {
        val lower = name.lowercase()
        return listOf(".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".heic", ".heif")
            .any { lower.endsWith(it) }
    }
}
