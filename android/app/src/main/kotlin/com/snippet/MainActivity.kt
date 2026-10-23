package com.snippet

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "snippet/ambient_audio").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "enqueue" -> { val pcm = call.argument<ByteArray>("pcm") ?: byteArrayOf(); enqueue(call.argument<Int>("turn") ?: 0, call.argument<Int>("seq") ?: 0, pcm, call.argument<Int>("silenceMs") ?: 80); result.success(null) }
                    "position" -> result.success(position())
                    "volume" -> { currentVolume = call.argument<Double>("volume")?.toFloat() ?: 1f; audioTrack?.setVolume(currentVolume); result.success(null) }
                    "stop" -> result.success(stopTrack())
                    "cancelAfter" -> { cancelAfter(call.argument<Int>("turn") ?: 0, call.argument<Int>("seq") ?: -1, call.argument<Int>("fadeMs") ?: 50); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("audio", e.message, null) }
        }
        deliver(intent, fromNewIntent = false)
    }

    private data class AudioChunk(val turn: Int, val seq: Int, val pcm: ByteArray, val silenceFrames: Int)
    private data class AudioBoundary(val turn: Int, val seq: Int, val start: Long, val audioEnd: Long, val end: Long)
    private val audioQueue = java.util.concurrent.LinkedBlockingQueue<AudioChunk>()
    private val written = mutableListOf<AudioBoundary>()
    @Volatile private var audioTrack: AudioTrack? = null
    @Volatile private var stopping = false
    @Volatile private var framesWritten = 0L
    private var audioThread: Thread? = null
    private fun ensureTrack(): AudioTrack {
        audioTrack?.let { return it }
        val min = AudioTrack.getMinBufferSize(24000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()).setAudioFormat(AudioFormat.Builder().setSampleRate(24000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(maxOf(min, 9600)).setTransferMode(AudioTrack.MODE_STREAM).build()
        audioTrack = track
        stopping = false
        track.play()
        audioThread = Thread { writerLoop() }.also { it.start() }
        return track
    }
    private fun enqueue(turn: Int, seq: Int, pcm: ByteArray, silenceMs: Int) {
        ensureTrack()
        audioQueue.put(AudioChunk(turn, seq, pcm, 24000 * silenceMs / 1000))
    }
    private fun writerLoop() {
        while (!stopping) {
            val item = try { audioQueue.take() } catch (_: InterruptedException) { break }
            val track = audioTrack ?: break
            val start = framesWritten
            val totalFrames = item.pcm.size / 2
            synchronized(written) { written.add(AudioBoundary(item.turn, item.seq, start, start + totalFrames, start + totalFrames + item.silenceFrames)) }
            var off = 0
            while (off < item.pcm.size && !stopping) { val n = track.write(item.pcm, off, item.pcm.size - off, AudioTrack.WRITE_BLOCKING); if (n <= 0) break; off += n }
            framesWritten += totalFrames
            if (item.silenceFrames > 0 && !stopping) { val silence = ByteArray(item.silenceFrames * 2); var p = 0; while (p < silence.size && !stopping) { val n = track.write(silence, p, silence.size - p, AudioTrack.WRITE_BLOCKING); if (n <= 0) break; p += n }; framesWritten += item.silenceFrames }
        }
    }
    private fun position(): Map<String, Int> {
        val head = (audioTrack?.playbackHeadPosition?.toLong() ?: 0L) and 0xffffffffL
        synchronized(written) {
            if (written.isEmpty()) return mapOf("seq" to -1, "played_ms" to 0)
            var lastSeq = -1
            var withinMs = 0
            for (i in written.indices) {
                val entry = written[i]
                if (head >= entry.start) {
                    if (head >= entry.audioEnd) { lastSeq = entry.seq; withinMs = ((entry.audioEnd - entry.start) * 1000 / 24000).toInt() }
                    else { lastSeq = entry.seq - 1; withinMs = ((head - entry.start) * 1000 / 24000).toInt() }
                }
            }
            return mapOf("seq" to lastSeq, "played_ms" to withinMs)
        }
    }
    @Volatile private var currentVolume = 1f
    private fun cancelAfter(turn: Int, seq: Int, fadeMs: Int) {
        val keep = audioQueue.filter { it.turn != turn || it.seq <= seq }
        audioQueue.clear(); audioQueue.addAll(keep)
        val current = synchronized(written) { written.lastOrNull() }
        if (current?.turn == turn && current.seq > seq) {
            val track = audioTrack
            if (track != null) {
                val startVolume = currentVolume
                Thread {
                    val steps = 5
                    for (i in 1..steps) {
                        try { Thread.sleep((fadeMs / steps).coerceAtLeast(1).toLong()) } catch (_: InterruptedException) { break }
                        try { track.setVolume(startVolume * (1f - i.toFloat() / steps)) } catch (_: Exception) { break }
                    }
                    stopTrack()
                }.start()
            }
        }
    }
    private fun stopTrack(): Map<String, Int> {
        val pos = position()
        stopping = true
        audioQueue.clear()
        audioThread?.interrupt()
        audioTrack?.let { try { it.pause(); it.flush(); it.stop(); it.release() } catch (_: Exception) {} }
        audioTrack = null
        framesWritten = 0L
        synchronized(written) { written.clear() }
        return pos
    }
    override fun onDestroy() { stopTrack(); super.onDestroy() }

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
