package dev.egebulut.egebookreader

import android.graphics.Rect
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumeKeysTurnPages = false
    private var reading = false
    private var channel: MethodChannel? = null
    private var pendingSave: Pair<String, MethodChannel.Result>? = null

    private fun updateSpeechService(args: Map<*, *>) {
        val service = Intent(this, ReadingService::class.java)
        if (args["active"] != true) {
            stopService(service)
            return
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
        }
        service.putExtra(ReadingService.EXTRA_TITLE, args["title"] as String)
        service.putExtra(ReadingService.EXTRA_PAUSED, args["paused"] as Boolean)
        service.putExtra(ReadingService.EXTRA_LABELS, (args["labels"] as List<*>).map { it as String }.toTypedArray())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service) else startService(service)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "egebookreader/volume").also {
            speechChannel = it
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        volumeKeysTurnPages = call.arguments as Boolean
                        result.success(null)
                    }
                    "setReading" -> {
                        reading = call.arguments as Boolean
                        applyGestureExclusion()
                        // A page being read should not go dark in the middle of a paragraph.
                        if (reading) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "shouldRest" -> result.success(shouldRest())
                    "saveDocument" -> {
                        val args = call.arguments as Map<*, *>
                        pendingSave = (args["path"] as String) to result
                        startActivityForResult(
                            Intent(Intent.ACTION_CREATE_DOCUMENT)
                                .addCategory(Intent.CATEGORY_OPENABLE)
                                .setType("application/octet-stream")
                                .putExtra(Intent.EXTRA_TITLE, args["name"] as String),
                            SAVE_DOCUMENT,
                        )
                    }
                    "speechService" -> {
                        updateSpeechService(call.arguments as Map<*, *>)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // Copies the file Dart prepared to where the reader chose, off the main thread: a library backup can be large.
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_DOCUMENT) return
        val (path, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) return result.success(false)
        Thread {
            try {
                contentResolver.openOutputStream(uri)!!.use { out -> java.io.File(path).inputStream().use { it.copyTo(out) } }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("write", e.message, null) }
            }
        }.start()
    }

    // Background colouring waits while the phone is warm or saving battery.
    private fun shouldRest(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val hot = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            power.currentThermalStatus >= PowerManager.THERMAL_STATUS_MODERATE
        return hot || power.isPowerSaveMode
    }

    override fun onPostCreate(savedInstanceState: android.os.Bundle?) {
        super.onPostCreate(savedInstanceState)
        window.decorView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyGestureExclusion() }
    }

    // While reading, a swipe from the middle of a screen edge turns the page instead of going back.
    // Android allows at most 200dp per edge, so the rest of the edge keeps the system gesture.
    private fun applyGestureExclusion() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val root = window.decorView
        val density = resources.displayMetrics.density
        val band = (200 * density).toInt()
        val edge = (32 * density).toInt()
        val top = (root.height - band) / 2
        root.systemGestureExclusionRects = if (reading) {
            listOf(Rect(0, top, edge, top + band), Rect(root.width - edge, top, root.width, top + band))
        } else {
            emptyList()
        }
    }

    // Consuming both DOWN and UP keeps the system from changing the volume or showing its HUD.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val direction = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> 1
            KeyEvent.KEYCODE_VOLUME_UP -> -1
            else -> 0
        }
        if (direction == 0 || !volumeKeysTurnPages) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            channel?.invokeMethod("key", direction)
        }
        return true
    }

    companion object {
        private const val SAVE_DOCUMENT = 42
        private var speechChannel: MethodChannel? = null

        /** A button on the reading notification was pressed. */
        fun sendSpeechAction(action: String) {
            speechChannel?.invokeMethod("speechAction", action)
        }
    }
}
