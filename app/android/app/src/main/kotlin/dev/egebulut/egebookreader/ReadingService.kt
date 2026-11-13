package dev.egebulut.egebookreader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app alive while a book is read aloud with the screen off or another app in front.
 * The speaking itself stays in Dart; this holds the process, a wake lock and the notification.
 *
 * It is also the book's media session: the lock screen and headset buttons control the voice, music
 * is turned down (not off) while the voice speaks, and unplugging headphones pauses it.
 */
class ReadingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var session: MediaSession? = null
    private var focus: AudioFocusRequest? = null
    private var listening = false
    private var silence: AudioTrack? = null

    // The system voice speaks from the TTS engine's process, so Android would not count this app as playing and would
    // send headset buttons to the last music app (which then starts). A silent loop from here makes the buttons ours.
    private fun holdSilence(on: Boolean) {
        if (!on) return silence?.pause() ?: Unit
        val track = silence ?: run {
            val bytes = 1600 // 0.1 s of 16-bit mono at 8 kHz
            AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(8000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(bytes)
                .build()
                .apply {
                    write(ByteArray(bytes), 0, bytes)
                    setLoopPoints(0, bytes / 2, -1)
                }
                .also { silence = it }
        }
        track.play()
    }
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { MainActivity.sendSpeechAction(ACTION_PAUSE) }
    }

    private fun mediaSession(): MediaSession = session ?: MediaSession(this, "reading").apply {
        setCallback(object : MediaSession.Callback() {
            override fun onPlay() { MainActivity.sendSpeechAction(ACTION_RESUME) }
            override fun onPause() { MainActivity.sendSpeechAction(ACTION_PAUSE) }
            override fun onStop() { MainActivity.sendSpeechAction(ACTION_STOP) }
        })
        session = this
    }

    private fun audio() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // Transient and may-duck: music carries on, quieter, under the voice; a call or another player pauses the voice.
    private fun holdFocus(on: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val request = focus ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setOnAudioFocusChangeListener { change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                    MainActivity.sendSpeechAction(ACTION_PAUSE)
                }
            }
            .build()
            .also { focus = it }
        if (on) audio().requestAudioFocus(request) else audio().abandonAudioFocusRequest(request)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE, ACTION_RESUME, ACTION_STOP -> MainActivity.sendSpeechAction(intent.action!!)
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: ""
                val paused = intent?.getBooleanExtra(EXTRA_PAUSED, false) ?: false
                val labels = intent?.getStringArrayExtra(EXTRA_LABELS) ?: arrayOf("Pause", "Resume", "Stop")
                show(title, paused, labels)
                ShelfWidget.setSpeech(this, title, paused)
                holdWakeLock()
                holdFocus(!paused)
                holdSilence(!paused)
                if (!listening) {
                    val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
                    if (Build.VERSION.SDK_INT >= 33) registerReceiver(noisy, filter, RECEIVER_NOT_EXPORTED) else registerReceiver(noisy, filter)
                    listening = true
                }
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
        val media = mediaSession().apply {
            setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, labels[3])
                    .build(),
            )
            setPlaybackState(
                PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP)
                    .setState(if (paused) PlaybackState.STATE_PAUSED else PlaybackState.STATE_PLAYING, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f)
                    .build(),
            )
            isActive = true
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(labels.getOrElse(4) { labels[3] })
            .setContentIntent(open)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setStyle(Notification.MediaStyle().setMediaSession(media.sessionToken).setShowActionsInCompactView(0, 1))
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
        ShelfWidget.setSpeech(this, null, false)
        if (wakeLock?.isHeld == true) wakeLock?.release()
        holdFocus(false)
        silence?.release()
        silence = null
        session?.release()
        session = null
        if (listening) unregisterReceiver(noisy)
        listening = false
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
