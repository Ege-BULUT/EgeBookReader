package dev.egebulut.egebookreader

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

/**
 * A shelf of the latest books on the home screen. A cover opens its book; the button reads the first one
 * aloud, and while a book is read aloud it pauses, resumes and stops it. What it shows comes from Dart.
 */
open class ShelfWidget(private val count: Int) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = views(context, count)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == ReadingService.ACTION_PAUSE || action == ReadingService.ACTION_RESUME || action == ReadingService.ACTION_STOP) {
            // With the app gone the voice is gone too: what the shelf said was out of date.
            if (!MainActivity.sendSpeechAction(action)) setSpeech(context, null, false)
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val PREFS = "shelf"
        const val ACTION_OPEN = "dev.egebulut.egebookreader.OPEN_BOOK"
        const val EXTRA_BOOK = "book"
        const val EXTRA_SPEAK = "speak"
        private val coverIds = intArrayOf(R.id.cover0, R.id.cover1, R.id.cover2, R.id.cover3, R.id.cover4)

        fun setBooks(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("books", json).apply()
            refresh(context)
        }

        /** What is being read aloud now: its title, or null when nothing is. */
        fun setSpeech(context: Context, title: String?, paused: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("speaking", title).putBoolean("paused", paused).apply()
            refresh(context)
        }

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for ((provider, n) in listOf(Shelf3::class.java to 3, Shelf5::class.java to 5)) {
                val ids = manager.getAppWidgetIds(ComponentName(context, provider))
                if (ids.isNotEmpty()) {
                    val views = views(context, n)
                    for (id in ids) manager.updateAppWidget(id, views)
                }
            }
        }

        private fun open(context: Context, slot: Int, path: String, speak: Boolean) = PendingIntent.getActivity(
            context, slot,
            Intent(context, MainActivity::class.java).setAction(ACTION_OPEN).putExtra(EXTRA_BOOK, path).putExtra(EXTRA_SPEAK, speak),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun control(context: Context, n: Int, action: String) = PendingIntent.getBroadcast(
            context, action.hashCode() + n,
            Intent(context, if (n == 3) Shelf3::class.java else Shelf5::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun views(context: Context, n: Int): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val books = JSONArray(prefs.getString("books", "[]"))
            val speaking = prefs.getString("speaking", null)
            val paused = prefs.getBoolean("paused", false)
            val v = RemoteViews(context.packageName, R.layout.widget_shelf)
            v.setViewVisibility(R.id.covers, if (books.length() == 0) View.GONE else View.VISIBLE)
            v.setViewVisibility(R.id.empty, if (books.length() == 0) View.VISIBLE else View.GONE)
            for ((slot, id) in coverIds.withIndex()) {
                if (slot >= n || slot >= books.length()) {
                    v.setViewVisibility(id, if (slot < n) View.INVISIBLE else View.GONE)
                    continue
                }
                val book = books.getJSONObject(slot)
                v.setViewVisibility(id, View.VISIBLE)
                val cover = book.optString("cover")
                val bitmap = if (cover.isEmpty()) null else BitmapFactory.decodeFile(cover, BitmapFactory.Options().apply { inSampleSize = sampleFor(cover) })
                v.setImageViewBitmap(id, bitmap ?: titleCover(context, book.optString("title")))
                v.setContentDescription(id, book.optString("title"))
                v.setOnClickPendingIntent(id, open(context, slot, book.getString("path"), false))
            }
            if (speaking != null) {
                v.setTextViewText(R.id.status, speaking)
                v.setImageViewResource(R.id.play, if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause)
                v.setOnClickPendingIntent(R.id.play, control(context, n, if (paused) ReadingService.ACTION_RESUME else ReadingService.ACTION_PAUSE))
                v.setViewVisibility(R.id.stop, View.VISIBLE)
                v.setOnClickPendingIntent(R.id.stop, control(context, n, ReadingService.ACTION_STOP))
            } else {
                v.setTextViewText(R.id.status, if (books.length() > 0) books.getJSONObject(0).optString("title") else "")
                v.setImageViewResource(R.id.play, android.R.drawable.ic_media_play)
                v.setViewVisibility(R.id.stop, View.GONE)
                if (books.length() > 0) v.setOnClickPendingIntent(R.id.play, open(context, 9, books.getJSONObject(0).getString("path"), true))
            }
            return v
        }

        /** A book without a cover gets its title on paper, as on the library shelf. */
        private fun titleCover(context: Context, title: String): android.graphics.Bitmap {
            val w = 200
            val h = 300
            val bitmap = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            canvas.drawColor(0xFFECE7DF.toInt())
            val paint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF2A2622.toInt()
                textSize = 22f
                typeface = android.graphics.Typeface.SERIF
            }
            val layout = android.text.StaticLayout.Builder.obtain(title, 0, title.length, paint, w - 28).setMaxLines(5).setEllipsize(android.text.TextUtils.TruncateAt.END).build()
            canvas.translate(14f, 16f)
            layout.draw(canvas)
            return bitmap
        }

        /** A cover is drawn about 240 px wide at most, which keeps the shelf well inside the widget's memory limit. */
        private fun sampleFor(path: String): Int {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 240) sample *= 2
            return sample
        }
    }
}

class Shelf3 : ShelfWidget(3)
class Shelf5 : ShelfWidget(5)
