package com.snippet.ambient_audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AmbientAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "snippet/ambient_audio").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "enqueue" -> { val pcm = call.argument<ByteArray>("pcm") ?: byteArrayOf(); enqueue(call.argument<Int>("turn") ?: 0, call.argument<Int>("seq") ?: 0, pcm, call.argument<Int>("silenceMs") ?: 80); result.success(null) }
                "mediaActive" -> result.success((context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.isMusicActive ?: false)
                "position" -> result.success(position())
                "volume" -> { currentVolume = call.argument<Double>("volume")?.toFloat() ?: 1f; audioTrack?.setVolume(currentVolume); result.success(null) }
                "stop" -> result.success(stopTrack())
                "cancelAfter" -> { cancelAfter(call.argument<Int>("turn") ?: 0, call.argument<Int>("seq") ?: -1, call.argument<Int>("fadeMs") ?: 50); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("audio", e.message, null) }
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
}
