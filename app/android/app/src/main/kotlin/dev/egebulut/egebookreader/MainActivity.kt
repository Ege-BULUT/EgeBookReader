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
    private var pendingFolder: MethodChannel.Result? = null

    /** Off the main thread, then the answer back on it. */
    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) = Thread {
        try {
            val value = work()
            runOnUiThread { result.success(value) }
        } catch (e: Exception) {
            runOnUiThread { result.error("io", e.message, null) }
        }
    }.start()

    /** Every file under a folder the reader picked: its uri, its path inside the folder and when it changed. */
    private fun listFolder(tree: android.net.Uri): List<Map<String, Any>> {
        val found = mutableListOf<Map<String, Any>>()
        val dirs = ArrayDeque(listOf(android.provider.DocumentsContract.getTreeDocumentId(tree) to ""))
        val columns = arrayOf(
            android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE,
            android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        while (dirs.isNotEmpty()) {
            val (id, prefix) = dirs.removeFirst()
            val children = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
            contentResolver.query(children, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val rel = prefix + c.getString(1)
                    if (c.getString(2) == android.provider.DocumentsContract.Document.MIME_TYPE_DIR) {
                        dirs.add(c.getString(0) to "$rel/")
                    } else {
                        val uri = android.provider.DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0))
                        found.add(mapOf("uri" to uri.toString(), "path" to rel, "modified" to c.getLong(3)))
                    }
                }
            }
        }
        return found
    }

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
                    "shareFile" -> {
                        val args = call.arguments as Map<*, *>
                        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.files", java.io.File(args["path"] as String))
                        val send = Intent(Intent.ACTION_SEND)
                            .setType(args["type"] as String)
                            .putExtra(Intent.EXTRA_STREAM, uri)
                            .putExtra(Intent.EXTRA_TEXT, args["text"] as String?)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        startActivity(Intent.createChooser(send, null))
                        result.success(null)
                    }
                    "setBrightness" -> {
                        val v = (call.arguments as Number).toFloat()
                        window.attributes = window.attributes.apply { screenBrightness = if (v < 0) -1f else v }
                        result.success(null)
                    }
                    "shelf" -> {
                        ShelfWidget.setBooks(this, call.arguments as String)
                        result.success(null)
                    }
                    "takeOpen" -> {
                        result.success(openRequest(intent))
                        intent.action = null
                    }
                    "pickFolder" -> {
                        pendingFolder = result
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), PICK_FOLDER)
                    }
                    "listFolder" -> inBackground(result) { listFolder(android.net.Uri.parse(call.arguments as String)) }
                    "copyIn" -> {
                        val args = call.arguments as Map<*, *>
                        inBackground(result) {
                            val to = java.io.File(args["to"] as String).apply { parentFile?.mkdirs() }
                            contentResolver.openInputStream(android.net.Uri.parse(args["uri"] as String))!!.use { input ->
                                to.outputStream().use { input.copyTo(it) }
                            }
                            to.path
                        }
                    }
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
                    "encodeAac" -> {
                        val args = call.arguments as Map<*, *>
                        inBackground(result) { encodeAac(args["from"] as String, args["to"] as String); null }
                    }
                    "thermal" -> result.success(
                        if (Build.VERSION.SDK_INT >= 29) (getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus else 0,
                    )
                    "speechService" -> {
                        updateSpeechService(call.arguments as Map<*, *>)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** A 16-bit mono WAV from the voice, packed as AAC in an .m4a: about a tenth of the space. */
    private fun encodeAac(from: String, to: String) {
        val wav = java.io.File(from).readBytes()
        val rate = java.nio.ByteBuffer.wrap(wav).order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt(24)
        val pcm = wav.copyOfRange(44, wav.size)
        val mime = android.media.MediaFormat.MIMETYPE_AUDIO_AAC
        val format = android.media.MediaFormat.createAudioFormat(mime, rate, 1).apply {
            setInteger(android.media.MediaFormat.KEY_AAC_PROFILE, android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(android.media.MediaFormat.KEY_BIT_RATE, 48000)
            setInteger(android.media.MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        val codec = android.media.MediaCodec.createEncoderByType(mime)
        val muxer = android.media.MediaMuxer(to, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            codec.configure(format, null, null, android.media.MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val info = android.media.MediaCodec.BufferInfo()
            var offset = 0
            var inputDone = false
            var track = -1
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val input = codec.getInputBuffer(i)!!
                        input.clear()
                        val n = minOf(input.remaining() and 1.inv(), pcm.size - offset)
                        input.put(pcm, offset, n)
                        val time = offset / 2L * 1_000_000 / rate
                        offset += n
                        inputDone = offset >= pcm.size
                        codec.queueInputBuffer(i, 0, n, time, if (inputDone) android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10_000)
                if (o == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                } else if (o >= 0) {
                    if (info.flags and android.media.MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && track >= 0) muxer.writeSampleData(track, codec.getOutputBuffer(o)!!, info)
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            muxer.stop()
        } finally {
            codec.release()
            muxer.release()
        }
    }

    /** A book the home-screen shelf asked to open, and whether to read it aloud. */
    private fun openRequest(intent: Intent?): Map<String, Any>? {
        if (intent?.action != ShelfWidget.ACTION_OPEN) return null
        val book = intent.getStringExtra(ShelfWidget.EXTRA_BOOK) ?: return null
        return mapOf("book" to book, "speak" to intent.getBooleanExtra(ShelfWidget.EXTRA_SPEAK, false))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openRequest(intent)?.let { channel?.invokeMethod("open", it) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (speechChannel == channel) speechChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Copies the file Dart prepared to where the reader chose, off the main thread: a library backup can be large.
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FOLDER) {
            val result = pendingFolder ?: return
            pendingFolder = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) return result.success(null)
            // Kept across restarts, so new books in the folder can be picked up later.
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            return result.success(uri.toString())
        }
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
        private const val PICK_FOLDER = 43
        private var speechChannel: MethodChannel? = null

        /** A button on the reading notification or the shelf was pressed; false when the app is not running. */
        fun sendSpeechAction(action: String): Boolean {
            val channel = speechChannel ?: return false
            channel.invokeMethod("speechAction", action)
            return true
        }
    }
}
