// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

package io.github.kailian5922.agy_go.notify

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.provider.Settings
import io.github.kailian5922.agy_go.MainActivity
import io.github.kailian5922.agy_go.R

/**
 * Native Android Live Activity / capsule notification controller (channel [CHANNEL], id [ID]).
 *
 * Mirrors DSH Go's LiveActivity:
 * - Requests Android 16+ Live Update promotion ([EXTRA_REQUEST_PROMOTED_ONGOING],
 *   `Notification.ProgressStyle`, `setShortCriticalText`, `setUsesChronometer`).
 * - HyperOS 3.1+ (超级岛), ColorOS 16 / OPPO / OnePlus / realme (流体云), MagicOS 10 (灵动胶囊),
 *   and Pixel Android 16 QPR1+ draw promoted ongoing notifications as status-bar capsules / islands.
 * - Attaches Xiaomi HyperOS Focus template ([XiaomiFocus]) where SystemUI permits it.
 * - Runs all updates off the main thread on a dedicated [HandlerThread], rate-limited to
 *   [MIN_GAP_MS] so `NotificationManager` never drops rapid streaming bursts, refreshed every
 *   [REFRESH_MS], and guarded by [TIMEOUT_MS] / [ENDING_TIMEOUT_MS] so a killed process never
 *   leaves stale status behind.
 */
object LiveActivity {
    const val CHANNEL = "agy-live"
    const val ID = 3083

    /** `Notification.EXTRA_REQUEST_PROMOTED_ONGOING` (Android 16 / SDK 36.1). */
    const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    private const val PREFS = "agy_live"
    private const val K_ENABLED = "enabled"
    private const val DEFAULT_ACCENT = 0xFF3E63DD.toInt()
    private const val MIN_GAP_MS = 600L
    private const val REFRESH_MS = 4 * 60_000L
    private const val TIMEOUT_MS = 10 * 60_000L
    private const val ENDING_TIMEOUT_MS = 15_000L

    private val handler: Handler by lazy {
        Handler(HandlerThread("agy-live").apply { start() }.looper)
    }

    @Volatile private var app: Context? = null
    @Volatile private var current: LiveContent? = null

    // Accessed on live handler thread only.
    private var shown: LiveContent? = null
    /** True at startup so any stale capsule left by an earlier process is cancelled cleanly. */
    private var posted = true
    private var postedAt = 0L

    private val applyNow = Runnable { apply() }
    private val repost = Runnable {
        shown = null
        apply()
    }

    /** Updates the active capsule state from Flutter (null clears the capsule). */
    fun update(context: Context, enabled: Boolean, content: LiveContent?) {
        val ctx = attach(context)
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(K_ENABLED, true) != enabled) {
            prefs.edit().putBoolean(K_ENABLED, enabled).apply()
        }
        current = content
        refresh(ctx)
    }

    /** Re-evaluates and posts/cancels on the background thread within [MIN_GAP_MS]. */
    fun refresh(context: Context) {
        attach(context)
        handler.removeCallbacks(applyNow)
        val wait = (postedAt + MIN_GAP_MS - SystemClock.elapsedRealtime()).coerceAtLeast(0L)
        handler.postDelayed(applyNow, wait)
    }

    /**
     * Posts a 10-second live capsule preview immediately so the user can verify status-bar
     * capsule / island rendering from Settings. Call off the main thread.
     */
    fun postPreview(context: Context, accentColor: Int?): Boolean {
        val ctx = attach(context)
        if (!canPromote(ctx) && !XiaomiFocus.allowed(ctx)) {
            return false
        }
        val preview = LiveContent(
            kind = LiveContent.Kind.RUNNING,
            title = "AGY Go 实时活动测试",
            text = "正在验证状态栏胶囊 / 灵动岛显示效果",
            chip = "测试中",
            publicText = "AGY Go 实时活动测试",
            sinceMs = System.currentTimeMillis(),
            accentColor = accentColor,
            timeoutMs = 10_000L,
        )
        return runCatching {
            post(ctx, preview)
            posted = true
            postedAt = SystemClock.elapsedRealtime()
            true
        }.getOrDefault(false)
    }

    /**
     * Queries device Live Update & HyperOS Focus capability.
     * Call off the main thread (performs a binder call into SystemUI on HyperOS).
     */
    fun status(context: Context): Map<String, Any?> {
        val ctx = attach(context)
        val nm = nm(ctx)
        val canPost = canPromote(ctx)
        val page = Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
            settingsIntent(ctx).resolveActivity(ctx.packageManager) != null
        val xiaomi = XiaomiFocus.allowed(ctx)
        val notificationsEnabled = runCatching { nm.areNotificationsEnabled() }.getOrDefault(true)
        val channelImportance = runCatching {
            nm.getNotificationChannel(CHANNEL)?.importance ?: NotificationManager.IMPORTANCE_DEFAULT
        }.getOrDefault(NotificationManager.IMPORTANCE_DEFAULT)
        return mapOf(
            "supported" to (canPost || page || xiaomi),
            "allowed" to (canPost || xiaomi),
            "settings" to page,
            "xiaomiFocus" to xiaomi,
            "notificationsEnabled" to notificationsEnabled,
            "channelOpen" to (channelImportance > NotificationManager.IMPORTANCE_MIN),
            "islandVendor" to isIslandVendor(),
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    /** System page hosting this app's 「实时活动 / 在流体云中显示」 switch (Android 16+). */
    @SuppressLint("InlinedApi")
    fun settingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)

    fun appNotificationSettingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)

    private fun isIslandVendor(): Boolean {
        val v = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase()
        return v.contains("xiaomi") || v.contains("redmi") || v.contains("poco") ||
            v.contains("oppo") || v.contains("oneplus") || v.contains("realme") ||
            v.contains("honor")
    }

    private fun attach(context: Context): Context = context.applicationContext.also { app = it }

    private fun enabled(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(K_ENABLED, true)

    private fun canPromote(ctx: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
            runCatching { nm(ctx).canPostPromotedNotifications() }.getOrDefault(false)

    private fun nm(ctx: Context): NotificationManager =
        ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun apply() {
        val ctx = app ?: return
        val content = if (enabled(ctx) && (canPromote(ctx) || XiaomiFocus.allowed(ctx))) {
            current
        } else {
            null
        }
        if (content == null) {
            handler.removeCallbacks(repost)
            if (posted) {
                runCatching { nm(ctx).cancel(ID) }
            }
            posted = false
            shown = null
            return
        }
        if (content == shown) return
        runCatching { post(ctx, content) }.onFailure { return }
        posted = true
        shown = content
        postedAt = SystemClock.elapsedRealtime()
        handler.removeCallbacks(repost)
        if (!content.ending && content.timeoutMs == null) {
            handler.postDelayed(repost, REFRESH_MS)
        }
    }

    private fun post(ctx: Context, c: LiveContent) {
        val nm = nm(ctx)
        ensureChannel(nm)
        val color = c.accentColor ?: DEFAULT_ACCENT
        val timeout = c.timeoutMs ?: if (c.ending) ENDING_TIMEOUT_MS else TIMEOUT_MS

        val builder = Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_agy)
            .setColor(color)
            .setContentTitle(c.title)
            .setContentText(c.text.ifEmpty { null })
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(if (c.busy) Notification.CATEGORY_PROGRESS else Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion(ctx, c, color))
            .setContentIntent(openIntent(ctx))
            .setTimeoutAfter(timeout)
            .addExtras(Bundle().apply { putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true) })

        val since = c.sinceMs
        if (since != null && !c.ending) {
            builder.setWhen(since).setShowWhen(true).setUsesChronometer(true)
        } else {
            builder.setShowWhen(false)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            builder.setStyle(
                if (c.busy) {
                    Notification.ProgressStyle()
                        .setProgressSegments(
                            listOf(Notification.ProgressStyle.Segment(1).setColor(color)),
                        )
                        .setProgressIndeterminate(true)
                } else {
                    Notification.BigTextStyle().bigText(c.text)
                },
            )
            c.chipWords?.let(builder::setShortCriticalText)
        } else if (c.busy) {
            builder.setProgress(0, 0, true)
        } else {
            builder.setStyle(Notification.BigTextStyle().bigText(c.text))
        }

        val icon = Icon.createWithResource(ctx, R.mipmap.ic_launcher)
        XiaomiFocus.apply(ctx, builder, c, icon)
        nm.notify(ID, builder.build())
    }

    /** Lock-screen public fallback when sensitive content is hidden. */
    private fun publicVersion(ctx: Context, c: LiveContent, color: Int): Notification {
        val builder = Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_agy)
            .setColor(color)
            .setContentTitle("AGY Go")
            .setContentText(c.publicText)
            .setOngoing(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            c.chipWords?.let(builder::setShortCriticalText)
        }
        return builder.build()
    }

    private fun openIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            ctx,
            ID,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (nm.getNotificationChannel(CHANNEL) != null) return
        // IMPORTANCE_DEFAULT is required for Live Update / island promotion; silent so updates
        // never chime or vibrate.
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                "实时活动（胶囊通知）",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "任务运行、等待审批与手机操控时，在状态栏胶囊 / 灵动岛 / 流体云中实时展示进度"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
    }
}
