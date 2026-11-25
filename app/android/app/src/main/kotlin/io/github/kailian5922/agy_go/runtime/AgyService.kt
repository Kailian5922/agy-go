package io.github.kailian5922.agy_go.runtime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import io.github.kailian5922.agy_go.MainActivity

/**
 * ForegroundService keeping the on-device `agy acp` engine alive when the user switches apps
 * or turns off the screen during a long agent turn.
 */
class AgyService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                RuntimeController.get(applicationContext).stop()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                ensureChannel()
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "On-device Antigravity CLI is active"
                startForeground(NOTIFICATION_ID, buildNotification(text))
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "AGY Local Runtime",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the on-device Antigravity CLI engine running in the background."
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(contentText: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPi = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopIntent = Intent(this, AgyService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("AGY Go")
            .setContentText(contentText)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(openPi)
            .addAction(
                Notification.Action.Builder(null, "Stop", stopPi).build(),
            )
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "agy_local_runtime"
        private const val NOTIFICATION_ID = 4107
        private const val ACTION_START = "io.github.kailian5922.agy_go.ACTION_START_RUNTIME"
        private const val ACTION_STOP = "io.github.kailian5922.agy_go.ACTION_STOP_RUNTIME"
        private const val EXTRA_TEXT = "text"

        fun startForegroundService(context: Context, text: String) {
            val intent = Intent(context, AgyService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            context.stopService(Intent(context, AgyService::class.java))
        }
    }
}
