package dev.egebulut.egebookreader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app alive while a book is read aloud with the screen off or another app in front.
 * The speaking itself stays in Dart; this holds the process, a wake lock and the notification.
 */
class ReadingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE, ACTION_RESUME, ACTION_STOP -> MainActivity.sendSpeechAction(intent.action!!)
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: ""
                val paused = intent?.getBooleanExtra(EXTRA_PAUSED, false) ?: false
                val labels = intent?.getStringArrayExtra(EXTRA_LABELS) ?: arrayOf("Pause", "Resume", "Stop")
                show(title, paused, labels)
                holdWakeLock()
            }
        }
        return START_NOT_STICKY
    }

    private fun show(title: String, paused: Boolean, labels: Array<String>) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, labels[3], NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        fun action(icon: Int, label: String, name: String): Notification.Action {
            val pending = PendingIntent.getService(
                this, name.hashCode(), Intent(this, ReadingService::class.java).setAction(name),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(this, icon), label, pending).build()
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(labels[3])
            .setContentIntent(open)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(
                if (paused) action(android.R.drawable.ic_media_play, labels[1], ACTION_RESUME)
                else action(android.R.drawable.ic_media_pause, labels[0], ACTION_PAUSE),
            )
            .addAction(action(android.R.drawable.ic_menu_close_clear_cancel, labels[2], ACTION_STOP))
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(ID, notification)
        }
    }

    private fun holdWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        // ponytail: bounded to 6 hours so a lost stop signal cannot drain the battery forever.
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "egebookreader:reading").apply { acquire(6 * 60 * 60 * 1000L) }
    }

    override fun onDestroy() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "reading"
        const val ID = 41
        const val ACTION_PAUSE = "pause"
        const val ACTION_RESUME = "resume"
        const val ACTION_STOP = "stop"
        const val EXTRA_TITLE = "title"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_LABELS = "labels"
    }
}
