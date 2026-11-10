package dev.egebulut.egebookreader

import android.graphics.Rect
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumeKeysTurnPages = false
    private var reading = false
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "egebookreader/volume").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        volumeKeysTurnPages = call.arguments as Boolean
                        result.success(null)
                    }
                    "setReading" -> {
                        reading = call.arguments as Boolean
                        applyGestureExclusion()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
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
}
