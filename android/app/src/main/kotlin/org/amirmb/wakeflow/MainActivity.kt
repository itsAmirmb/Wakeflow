package org.amirmb.wakeflow

import android.media.AudioAttributes
import android.content.Intent
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
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
    private var pendingFile: MethodChannel.Result? = null
    private var pendingExportText: String? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.amirmb.wakeflow/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveText" -> saveText(
                        call.argument<String>("name") ?: "backup.json",
                        call.argument<String>("text") ?: "",
                        result,
                    )
                    "pickText" -> pickText(result)
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

    /// Save dialog (Storage Access Framework): no storage permission needed.
    private fun saveText(name: String, text: String, result: MethodChannel.Result) {
        if (pendingFile != null) {
            result.error("busy", "A file dialog is already open", null)
            return
        }
        pendingFile = result
        pendingExportText = text
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        startActivityForResult(intent, REQUEST_SAVE_FILE)
    }

    private fun pickText(result: MethodChannel.Result) {
        if (pendingFile != null) {
            result.error("busy", "A file dialog is already open", null)
            return
        }
        pendingFile = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/json", "text/plain", "application/octet-stream"),
            )
        }
        startActivityForResult(intent, REQUEST_PICK_FILE)
    }

    private fun handleFileResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val result = pendingFile ?: return
        val text = pendingExportText
        pendingFile = null
        pendingExportText = null
        val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(if (requestCode == REQUEST_SAVE_FILE) false else null)
            return
        }
        // File I/O off the main thread; the result goes back on it.
        Thread {
            try {
                if (requestCode == REQUEST_SAVE_FILE) {
                    val output = contentResolver.openOutputStream(uri, "wt")
                        ?: throw IOException("Could not open the file for writing")
                    output.use { it.write((text ?: "").toByteArray(Charsets.UTF_8)) }
                    runOnUiThread { result.success(true) }
                } else {
                    val input = contentResolver.openInputStream(uri)
                        ?: throw IOException("Could not open the file")
                    val bytes = input.use { readLimited(it) }
                    runOnUiThread { result.success(String(bytes, Charsets.UTF_8)) }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("file_failed", e.message ?: "File access failed", null)
                }
            }
        }.start()
    }

    private fun readLimited(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        var total = 0
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            total += n
            if (total > MAX_IMPORT_BYTES) {
                throw IOException("The file is too large to be a WakeFlow backup")
            }
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_SAVE_FILE || requestCode == REQUEST_PICK_FILE) {
            handleFileResult(requestCode, resultCode, data)
            return
        }
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
        private const val REQUEST_SAVE_FILE = 4712
        private const val REQUEST_PICK_FILE = 4713
        private const val MAX_IMPORT_BYTES = 20 * 1024 * 1024
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
