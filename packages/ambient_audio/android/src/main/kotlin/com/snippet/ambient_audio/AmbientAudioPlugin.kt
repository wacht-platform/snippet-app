package com.snippet.ambient_audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class AmbientAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private class Chunk(val turn: Int, val seq: Int, val pcm: ByteArray, val silenceFrames: Int)
    private class Boundary(val turn: Int, val seq: Int, val start: Long, val audioEnd: Long)
    private class Sink(val track: AudioTrack) {
        val queue = LinkedBlockingQueue<Chunk>()
        val written = CopyOnWriteArrayList<Boundary>()
        @Volatile var framesWritten = 0L
        @Volatile var stopping = false
        var thread: Thread? = null
    }

    private val lock = Any()
    private var channel: MethodChannel? = null
    private var context: Context? = null
    @Volatile private var sink: Sink? = null
    @Volatile private var lastPos: Map<String, Int> = idlePos()
    private var useComm = false
    @Volatile private var currentVolume = 1f
    private var commActive = false
    private var savedMode = AudioManager.MODE_NORMAL
    private var savedCallVolume = -1
    private var raisedCallVolume = -1

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "snippet/ambient_audio").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        stopTrack()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "enqueue" -> {
                    val pcm = call.argument<ByteArray>("pcm") ?: byteArrayOf()
                    enqueue(call.argument<Int>("turn") ?: 0, call.argument<Int>("seq") ?: 0, pcm, call.argument<Int>("silenceMs") ?: 80)
                    result.success(null)
                }
                "mediaActive" -> result.success(audioManager()?.isMusicActive ?: false)
                "position" -> result.success(position())
                "volume" -> {
                    currentVolume = call.argument<Double>("volume")?.toFloat() ?: 1f
                    synchronized(lock) { sink?.let { try { it.track.setVolume(currentVolume) } catch (_: Exception) {} } }
                    result.success(null)
                }
                "stop" -> result.success(stopTrack())
                "cancelAfter" -> {
                    cancelAfter(call.argument<Int>("turn") ?: 0, call.argument<Int>("seq") ?: -1, call.argument<Int>("fadeMs") ?: 50)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("audio", e.message, null)
        }
    }

    private fun idlePos(): Map<String, Int> = mapOf("seq" to -1, "played_ms" to 0, "turn" to -1, "active" to 0)

    private fun audioManager(): AudioManager? = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private val commTypes = intArrayOf(
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET,
    )

    private fun hasA2dp(am: AudioManager): Boolean =
        am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }

    private fun hasWired(am: AudioManager): Boolean =
        am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in commTypes }

    private fun enterComm(): Boolean {
        val am = audioManager() ?: return false
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                val devices = am.availableCommunicationDevices
                val pick = devices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == AudioDeviceInfo.TYPE_BLE_HEADSET || it.type in commTypes
                } ?: if (hasA2dp(am)) null else devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                if (pick == null) return false
                savedMode = am.mode
                am.mode = AudioManager.MODE_IN_COMMUNICATION
                am.setCommunicationDevice(pick)
            } else {
                if (hasA2dp(am) && !hasWired(am)) return false
                savedMode = am.mode
                am.mode = AudioManager.MODE_IN_COMMUNICATION
                if (!hasWired(am)) am.isSpeakerphoneOn = true
            }
            val max = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val cur = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            savedCallVolume = cur
            raisedCallVolume = -1
            if (cur < max * 7 / 10) {
                raisedCallVolume = max * 8 / 10
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, raisedCallVolume, 0)
            }
            commActive = true
            return true
        } catch (_: Exception) {
            commActive = true
            leaveComm()
            return false
        }
    }

    private fun leaveComm() {
        if (!commActive) return
        commActive = false
        val am = audioManager() ?: return
        try {
            if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice() else am.isSpeakerphoneOn = false
        } catch (_: Exception) {}
        try {
            am.mode = savedMode
        } catch (_: Exception) {}
        try {
            if (raisedCallVolume >= 0 && savedCallVolume >= 0 && am.getStreamVolume(AudioManager.STREAM_VOICE_CALL) == raisedCallVolume) {
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, savedCallVolume, 0)
            }
        } catch (_: Exception) {}
        raisedCallVolume = -1
        savedCallVolume = -1
    }

    private fun createSink(): Sink {
        useComm = enterComm()
        val min = AudioTrack.getMinBufferSize(24000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(if (useComm) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder().setSampleRate(24000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
            )
            .setBufferSizeInBytes(maxOf(min, 9600))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            leaveComm()
            throw IllegalStateException("audio track did not initialise")
        }
        try {
            track.setVolume(currentVolume)
            track.play()
        } catch (e: Exception) {
            track.release()
            leaveComm()
            throw e
        }
        lastPos = idlePos()
        val s = Sink(track)
        s.thread = Thread { writerLoop(s) }.also { it.isDaemon = true; it.start() }
        sink = s
        return s
    }

    private fun releaseSink(s: Sink) {
        if (sink === s) sink = null
        s.stopping = true
        s.queue.clear()
        try {
            s.thread?.interrupt()
        } catch (_: Exception) {}
        try {
            s.track.pause()
            s.track.flush()
            s.track.stop()
        } catch (_: Exception) {}
        try {
            s.track.release()
        } catch (_: Exception) {}
        leaveComm()
    }

    private fun enqueue(turn: Int, seq: Int, pcm: ByteArray, silenceMs: Int) {
        synchronized(lock) {
            val s = sink ?: createSink()
            s.queue.put(Chunk(turn, seq, pcm, 24000 * silenceMs / 1000))
        }
    }

    private fun writeAll(s: Sink, data: ByteArray): Boolean {
        var off = 0
        while (off < data.size && !s.stopping) {
            val n = try { s.track.write(data, off, data.size - off, AudioTrack.WRITE_BLOCKING) } catch (_: Exception) { -1 }
            if (n <= 0) return false
            off += n
        }
        return !s.stopping
    }

    private fun writerLoop(s: Sink) {
        while (!s.stopping) {
            val item = try { s.queue.poll(2000, TimeUnit.MILLISECONDS) } catch (_: InterruptedException) { return }
            if (item == null) {
                synchronized(lock) {
                    if (sink === s && s.queue.isEmpty() && !s.stopping) {
                        val head = try { s.track.playbackHeadPosition.toLong() and 0xffffffffL } catch (_: Exception) { s.framesWritten }
                        if (head >= s.framesWritten) {
                            lastPos = positionOf(s) + ("active" to 0)
                            releaseSink(s)
                            return
                        }
                    }
                }
                continue
            }
            val frames = (item.pcm.size / 2).toLong()
            synchronized(lock) { s.written.add(Boundary(item.turn, item.seq, s.framesWritten, s.framesWritten + frames)) }
            if (!writeAll(s, item.pcm)) return
            s.framesWritten += frames
            if (item.silenceFrames > 0) {
                if (!writeAll(s, ByteArray(item.silenceFrames * 2))) return
                s.framesWritten += item.silenceFrames
            }
        }
    }

    private fun positionOf(s: Sink): Map<String, Int> {
        val head = try { s.track.playbackHeadPosition.toLong() and 0xffffffffL } catch (_: Exception) { 0L }
        var lastSeq = -1
        var lastTurn = -1
        var ms = 0
        for (b in s.written) {
            if (head < b.start) break
            lastTurn = b.turn
            if (head >= b.audioEnd) {
                lastSeq = b.seq
                ms = ((b.audioEnd - b.start) * 1000 / 24000).toInt()
            } else {
                lastSeq = b.seq - 1
                ms = ((head - b.start) * 1000 / 24000).toInt()
            }
        }
        return mapOf("seq" to lastSeq, "played_ms" to ms, "turn" to lastTurn, "active" to 1)
    }

    private fun position(): Map<String, Int> = sink?.let { positionOf(it) } ?: lastPos

    private fun stopTrack(): Map<String, Int> = synchronized(lock) {
        val s = sink ?: return@synchronized lastPos
        val pos = positionOf(s)
        lastPos = pos + ("active" to 0)
        releaseSink(s)
        pos
    }

    private fun cancelAfter(turn: Int, seq: Int, fadeMs: Int) {
        val s: Sink
        synchronized(lock) {
            s = sink ?: return
            val keep = s.queue.filter { it.turn != turn || it.seq <= seq }
            s.queue.clear()
            s.queue.addAll(keep)
            if (s.written.none { it.turn == turn && it.seq > seq }) return
        }
        Thread {
            val steps = 5
            val start = currentVolume
            for (i in 1..steps) {
                try { Thread.sleep((fadeMs / steps).coerceAtLeast(1).toLong()) } catch (_: InterruptedException) { break }
                try { s.track.setVolume(start * (1f - i.toFloat() / steps)) } catch (_: Exception) { break }
            }
            synchronized(lock) {
                if (sink === s) {
                    lastPos = positionOf(s) + ("active" to 0)
                    releaseSink(s)
                }
            }
        }.start()
    }
}
