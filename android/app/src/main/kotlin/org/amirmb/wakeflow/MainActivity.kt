package org.amirmb.wakeflow

import android.media.AudioAttributes
import android.content.Intent
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopAlarm() }
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.amirmb.wakeflow/alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val sound = call.argument<String>("sound") ?: "wf_alarm"
                        val loop = call.argument<Boolean>("loop") ?: false
                        val uri = call.argument<String>("uri")
                        play(sound, loop, uri)
                        result.success(null)
                    }
                    "pickAlarm" -> pickAlarm(call.argument<String>("current"), result)
                    "stop" -> { stopAlarm(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    /// Plays the phone alarm at [uri] if given (and playable), otherwise the
    /// bundled res/raw [sound].
    private fun play(sound: String, loop: Boolean, uri: String?) {
        stopAlarm()
        if (uri != null &&
            startPlayer(loop) { setDataSource(this@MainActivity, Uri.parse(uri)) }
        ) return
        val id = resources.getIdentifier(sound, "raw", packageName)
        if (id == 0) {
            android.util.Log.e("WakeFlow", "missing raw sound: $sound")
            return
        }
        startPlayer(loop) {
            resources.openRawResourceFd(id).use {
                setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
        }
    }

    private fun startPlayer(loop: Boolean, source: MediaPlayer.() -> Unit): Boolean {
        return try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                source()
                isLooping = loop
                if (!loop) setOnCompletionListener { stopAlarm() }
                prepare()
                start()
            }
            if (loop) handler.postDelayed(autoStop, 180_000) // never ring forever
            true
        } catch (e: Exception) {
            android.util.Log.e("WakeFlow", "sound failed", e)
            stopAlarm()
            false
        }
    }

    /// Opens the system alarm-sound picker (the phone's own alarm tones).
    private fun pickAlarm(current: String?, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "Picker already open", null)
            return
        }
        pendingPick = result
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Break-end alarm")
            if (current != null) {
                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(current))
            }
        }
        startActivityForResult(intent, REQUEST_PICK_ALARM)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK_ALARM) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick
        pendingPick = null
        val uri: Uri? = if (resultCode == RESULT_OK) {
            data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        } else null
        if (uri == null) {
            result?.success(null)
            return
        }
        val title = try {
            RingtoneManager.getRingtone(this, uri).getTitle(this)
        } catch (e: Exception) {
            "Alarm"
        }
        result?.success(mapOf("uri" to uri.toString(), "title" to title))
    }

    companion object {
        private const val REQUEST_PICK_ALARM = 4711
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
