package org.amirmb.wakeflow

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopAlarm() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.amirmb.wakeflow/alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val sound = call.argument<String>("sound") ?: "wf_alarm"
                        val loop = call.argument<Boolean>("loop") ?: false
                        play(sound, loop)
                        result.success(null)
                    }
                    "stop" -> { stopAlarm(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun play(sound: String, loop: Boolean) {
        stopAlarm()
        val id = resources.getIdentifier(sound, "raw", packageName)
        if (id == 0) {
            android.util.Log.e("WakeFlow", "missing raw sound: $sound")
            return
        }
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                resources.openRawResourceFd(id).use {
                    setDataSource(it.fileDescriptor, it.startOffset, it.length)
                }
                isLooping = loop
                if (!loop) setOnCompletionListener { stopAlarm() }
                prepare()
                start()
            }
            if (loop) handler.postDelayed(autoStop, 180_000) // never ring forever
        } catch (e: Exception) {
            android.util.Log.e("WakeFlow", "sound failed: $sound", e)
            stopAlarm()
        }
    }

    private fun stopAlarm() {
        handler.removeCallbacks(autoStop)
        player?.let {
            try { if (it.isPlaying) it.stop() } catch (_: Exception) {}
            it.release()
        }
        player = null
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }
}
