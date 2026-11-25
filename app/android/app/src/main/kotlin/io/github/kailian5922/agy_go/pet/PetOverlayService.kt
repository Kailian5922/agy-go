package io.github.kailian5922.agy_go.pet

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import io.github.kailian5922.agy_go.MainActivity
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * Original AGY Starling (星灵) floating desktop pet rendered over other apps via SYSTEM_ALERT_WINDOW.
 * Supports smooth dragging, automatic edge snapping, live mood animations, and tap-to-open AGY Go.
 */
class PetOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var petView: StarlingOverlayView? = null
    private var params: WindowManager.LayoutParams? = null
    private val animatorHandler = Handler(Looper.getMainLooper())
    private var animPhase = 0f

    private val ticker = object : Runnable {
        override fun run() {
            animPhase = (animPhase + 0.08f) % (Math.PI.toFloat() * 2f)
            petView?.setAnimPhase(animPhase)
            animatorHandler.postDelayed(this, 32L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mood = intent?.getStringExtra(EXTRA_MOOD)
        if (mood != null) {
            currentMood = mood
            petView?.setMood(mood)
        }
        if (petView == null && Settings.canDrawOverlays(this)) {
            attachOverlay()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        animatorHandler.removeCallbacks(ticker)
        try {
            petView?.let { windowManager?.removeView(it) }
        } catch (_: Throwable) {}
        petView = null
        isShowing = false
        super.onDestroy()
    }

    private fun attachOverlay() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm
        val density = resources.displayMetrics.density
        val sizePx = (66 * density).toInt()
        val screenW = resources.displayMetrics.widthPixels

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val lp = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = screenW - sizePx - (12 * density).toInt()
            y = (220 * density).toInt()
        }
        params = lp

        val view = StarlingOverlayView(this).apply {
            setMood(currentMood)
        }

        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var moved = false

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x
                    startY = lp.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (abs(dx) > 8 || abs(dy) > 8) moved = true
                    lp.x = startX + dx
                    lp.y = startY + dy
                    wm.updateViewLayout(view, lp)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        val open = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(open)
                    } else {
                        // Snap cleanly to nearest screen edge.
                        val margin = (8 * density).toInt()
                        val center = lp.x + sizePx / 2
                        lp.x = if (center < screenW / 2) margin else screenW - sizePx - margin
                        wm.updateViewLayout(view, lp)
                    }
                    true
                }
                else -> false
            }
        }

        wm.addView(view, lp)
        petView = view
        isShowing = true
        animatorHandler.post(ticker)
    }

    private class StarlingOverlayView(context: Context) : View(context) {
        private var mood: String = "idle"
        private var phase: Float = 0f

        private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2.5f
            color = Color.argb(140, 255, 255, 255)
        }
        private val eyePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        private val sparkPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        fun setMood(next: String) {
            mood = next
            invalidate()
        }

        fun setAnimPhase(p: Float) {
            phase = p
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            val cx = w / 2f
            val bob = sin(phase.toDouble()).toFloat() * (if (mood == "happy") 5f else 2.5f)
            val cy = h / 2f + bob
            val r = minOf(w, h) * 0.34f

            val accent = when (mood) {
                "thinking" -> Color.rgb(122, 162, 255)
                "working" -> Color.rgb(52, 211, 153)
                "waitingApproval" -> Color.rgb(251, 191, 36)
                "happy" -> Color.rgb(167, 139, 250)
                "sleeping" -> Color.rgb(100, 116, 139)
                else -> Color.rgb(62, 99, 221)
            }

            // Soft glow halo
            haloPaint.color = Color.argb(72, Color.red(accent), Color.green(accent), Color.blue(accent))
            canvas.drawCircle(cx, cy, r * 1.28f, haloPaint)

            // Main frosted orb body
            bodyPaint.color = accent
            canvas.drawCircle(cx, cy, r, bodyPaint)
            canvas.drawCircle(cx, cy, r, borderPaint)

            // Expressive eyes
            val eyeOffsetX = r * 0.32f
            val eyeY = cy - r * 0.06f
            if (mood == "sleeping") {
                eyePaint.strokeWidth = 3f
                canvas.drawLine(cx - eyeOffsetX - 5f, eyeY, cx - eyeOffsetX + 5f, eyeY, eyePaint)
                canvas.drawLine(cx + eyeOffsetX - 5f, eyeY, cx + eyeOffsetX + 5f, eyeY, eyePaint)
            } else {
                val eyeR = r * 0.14f
                canvas.drawCircle(cx - eyeOffsetX, eyeY, eyeR, eyePaint)
                canvas.drawCircle(cx + eyeOffsetX, eyeY, eyeR, eyePaint)
            }

            // Orbiting star satellite when thinking/working/waiting
            if (mood == "thinking" || mood == "working" || mood == "waitingApproval") {
                val orbitR = r * 1.18f
                val sx = cx + cos(phase * 2.0).toFloat() * orbitR
                val sy = cy + sin(phase * 2.0).toFloat() * orbitR
                sparkPaint.color = if (mood == "waitingApproval") Color.rgb(254, 240, 138) else Color.WHITE
                canvas.drawCircle(sx, sy, r * 0.16f, sparkPaint)
            }
        }
    }

    companion object {
        const val EXTRA_MOOD = "mood"
        @Volatile var isShowing: Boolean = false
            private set
        @Volatile var currentMood: String = "idle"
            private set

        fun show(context: Context, mood: String) {
            val intent = Intent(context, PetOverlayService::class.java).apply {
                putExtra(EXTRA_MOOD, mood)
            }
            context.startService(intent)
        }

        fun updateMood(context: Context, mood: String) {
            currentMood = mood
            if (isShowing) {
                show(context, mood)
            }
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, PetOverlayService::class.java))
        }
    }
}
