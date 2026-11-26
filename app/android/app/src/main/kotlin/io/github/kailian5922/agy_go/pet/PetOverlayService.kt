package io.github.kailian5922.agy_go.pet

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import io.github.kailian5922.agy_go.MainActivity
import io.github.kailian5922.agy_go.phone.AgyAccessibilityService
import io.github.kailian5922.agy_go.phone.PhoneController
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * DSH Go-style out-of-app floating Starling orb + floating input bar ("问一句") + inline approval/reply
 * bubbles rendered over other apps via `TYPE_APPLICATION_OVERLAY` (or `TYPE_ACCESSIBILITY_OVERLAY`
 * when Phone Control Accessibility Service is already active, requiring zero extra overlay permission).
 *
 * - Single tap orb: opens [FloatingAskBarView] right above the current app with soft keyboard focus.
 * - Long press orb: opens [FloatingMenuView] (问一句 / 打开 AGY Go / 紧急停止 / 隐藏悬浮球).
 * - Drag orb: moves smoothly and snaps to left/right screen edge, remembering dock position.
 * - Auto-hides while AGY Go is in foreground when `onlyOutsideApp` is enabled (default).
 */
class PetOverlayService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var animPhase = 0f

    private var hostContext: Context? = null
    private var hostWindowType: Int = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    private var windowManager: WindowManager? = null

    private var petView: StarlingOverlayView? = null
    private var petParams: WindowManager.LayoutParams? = null

    private var askView: FloatingAskBarView? = null
    private var askParams: WindowManager.LayoutParams? = null
    private var askRestY: Int = 0
    private var askFresh: Boolean = false
    private var askSessionId: String? = null
    private var askCurrentLine: String? = null
    private var askFreshLine: String = "新对话"
    private var askRequestSeq: Long = 0L

    private var menuView: FloatingMenuView? = null
    private var bubbleView: FloatingBubbleView? = null
    private var activeBubbleKey: String? = null
    private var bubbleAutoDismiss: Runnable? = null

    private var dockedRight: Boolean = true
    private var dockYFraction: Float = 0.34f
    private var askDraft: String = ""

    private val a11yListener: () -> Unit = {
        mainHandler.post {
            syncVisibility()
            notifyStatusChanged()
        }
    }

    private val ticker = object : Runnable {
        override fun run() {
            animPhase = (animPhase + 0.08f) % (Math.PI.toFloat() * 2f)
            petView?.setAnimPhase(animPhase)
            if (petView != null) {
                mainHandler.postDelayed(this, 32L)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        dockedRight = prefs.getBoolean(K_DOCK_RIGHT, true)
        dockYFraction = prefs.getFloat(K_DOCK_Y, 0.34f).coerceIn(0.12f, 0.84f)
        askDraft = prefs.getString(K_ASK_DRAFT, "").orEmpty()
        AgyAccessibilityService.addStateListener(a11yListener)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_HIDE -> {
                enabled = false
                removeAllWindows()
                notifyStatusChanged()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SYNC -> {
                syncVisibility()
                return START_STICKY
            }
            ACTION_OPEN_ASK -> {
                syncVisibility()
                mainHandler.post { openAskBar(fresh = intent.getBooleanExtra(EXTRA_FRESH, false)) }
                return START_STICKY
            }
        }
        val mood = intent?.getStringExtra(EXTRA_MOOD)
        if (mood != null) {
            currentMood = mood
            petView?.setMood(mood)
        }
        enabled = true
        syncVisibility()
        return START_STICKY
    }

    override fun onDestroy() {
        AgyAccessibilityService.removeStateListener(a11yListener)
        removeAllWindows()
        if (activeInstance === this) activeInstance = null
        isShowing = false
        notifyStatusChanged()
        super.onDestroy()
    }

    private fun shouldDisplayNow(): Boolean {
        if (!enabled) return false
        if (onlyOutsideApp && appInForeground) return false
        return resolveOverlayHost() != null
    }

    private fun resolveOverlayHost(): Pair<Context, Int>? {
        if (Settings.canDrawOverlays(this)) {
            val ctx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    val dm = getSystemService(DisplayManager::class.java)
                    val display = dm?.getDisplay(Display.DEFAULT_DISPLAY)
                    if (display != null) {
                        createDisplayContext(display)
                            .createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
                    } else {
                        this
                    }
                } catch (_: Throwable) {
                    this
                }
            } else {
                this
            }
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            return ctx to type
        }
        val a11y = AgyAccessibilityService.instance
        if (a11y != null) {
            return a11y.overlayWindowContext() to WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        }
        return null
    }

    private fun syncVisibility() {
        val want = shouldDisplayNow()
        if (!want) {
            removeAllWindows()
            isShowing = false
            notifyStatusChanged()
            return
        }
        val resolved = resolveOverlayHost() ?: run {
            removeAllWindows()
            isShowing = false
            notifyStatusChanged()
            return
        }
        if (petView != null && hostWindowType != resolved.second) {
            removeAllWindows()
        }
        if (petView == null) {
            attachOrb(resolved.first, resolved.second)
        } else {
            petView?.setMood(currentMood)
            petView?.setBadgeCount(pendingApprovalCount)
        }
        syncBubbleIfNeeded()
        notifyStatusChanged()
    }

    private fun attachOrb(ctx: Context, winType: Int) {
        val wm = ctx.getSystemService(WINDOW_SERVICE) as? WindowManager ?: return
        hostContext = ctx
        hostWindowType = winType
        windowManager = wm

        val density = ctx.resources.displayMetrics.density
        val sizePx = (62 * density).toInt()
        val screenW = ctx.resources.displayMetrics.widthPixels
        val screenH = ctx.resources.displayMetrics.heightPixels
        val margin = (8 * density).toInt()

        val lp = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            winType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (dockedRight) screenW - sizePx - margin else margin
            y = (screenH * dockYFraction).toInt().coerceIn(margin * 4, (screenH - sizePx - margin * 6).coerceAtLeast(margin * 4))
        }
        petParams = lp

        val view = StarlingOverlayView(ctx).apply {
            setMood(currentMood)
            setBadgeCount(pendingApprovalCount)
        }

        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var moved = false
        var longPressed = false
        val longPressRunnable = Runnable {
            if (!moved) {
                longPressed = true
                openQuickMenu()
            }
        }

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x
                    startY = lp.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    longPressed = false
                    mainHandler.postDelayed(longPressRunnable, 430L)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (abs(dx) > 10 || abs(dy) > 10) {
                        if (!moved) {
                            moved = true
                            mainHandler.removeCallbacks(longPressRunnable)
                            dismissMenu()
                        }
                    }
                    if (moved) {
                        lp.x = startX + dx
                        lp.y = startY + dy
                        safeUpdateView(view, lp)
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    mainHandler.removeCallbacks(longPressRunnable)
                    if (moved) {
                        val curScreenW = ctx.resources.displayMetrics.widthPixels
                        val curScreenH = ctx.resources.displayMetrics.heightPixels
                        val center = lp.x + sizePx / 2
                        dockedRight = center >= curScreenW / 2
                        lp.x = if (dockedRight) curScreenW - sizePx - margin else margin
                        lp.y = lp.y.coerceIn(margin * 4, (curScreenH - sizePx - margin * 6).coerceAtLeast(margin * 4))
                        dockYFraction = (lp.y.toFloat() / curScreenH.coerceAtLeast(1)).coerceIn(0.12f, 0.84f)
                        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .putBoolean(K_DOCK_RIGHT, dockedRight)
                            .putFloat(K_DOCK_Y, dockYFraction)
                            .apply()
                        safeUpdateView(view, lp)
                        repositionSubWindows()
                    } else if (!longPressed && event.actionMasked == MotionEvent.ACTION_UP) {
                        if (askView != null) {
                            dismissAskBar()
                        } else {
                            openAskBar(fresh = false)
                        }
                    }
                    true
                }
                else -> false
            }
        }

        try {
            wm.addView(view, lp)
            petView = view
            isShowing = true
            mainHandler.removeCallbacks(ticker)
            mainHandler.post(ticker)
        } catch (_: Throwable) {
            petView = null
            petParams = null
            isShowing = false
        }
    }

    // ---- Floating Ask Bar ("问一句") ------------------------------------------------------------

    private fun openAskBar(fresh: Boolean) {
        val ctx = hostContext ?: return
        val wm = windowManager ?: return
        val orb = petParams ?: return
        dismissMenu()
        dismissBubble()
        dismissAskBar()

        askFresh = fresh
        askSessionId = null
        askCurrentLine = null
        askFreshLine = "新对话 · AGY Go"

        val screenW = ctx.resources.displayMetrics.widthPixels
        val screenH = ctx.resources.displayMetrics.heightPixels
        val gap = ctx.dpPx(8f)
        val margin = ctx.dpPx(10f)
        val barW = FloatingAskPlace.barWidth(
            screenWidth = screenW,
            orbLeft = orb.x,
            orbRight = orb.x + orb.width,
            dockedRight = dockedRight,
            gap = gap,
            margin = margin,
            minWidth = ctx.dpPx(250f),
            maxWidth = ctx.dpPx(360f),
        )

        val view = FloatingAskBarView(
            ctx,
            object : FloatingAskBarView.Listener {
                override fun onSend(text: String) = sendAskFromBar(text)
                override fun onToggleFresh() {
                    askFresh = !askFresh
                    updateAskTargetHeader()
                }
                override fun onStopTurn() {
                    callDart("askStop", null) { _ ->
                        askView?.setStatus("已发送停止请求")
                        askView?.setInteractionState(problem = false, isSending = false, canStop = false)
                    }
                }
                override fun onOpenApp() {
                    dismissAskBar()
                    bringAppToFront(prefill = null)
                }
                override fun onDraftChanged(text: String) {
                    askDraft = text
                    getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .edit()
                        .putString(K_ASK_DRAFT, text)
                        .apply()
                }
                override fun onClose() = dismissAskBar()
                override fun onImeInsets(overlapBottom: Int, visible: Boolean) {
                    liftAskBar(overlapBottom, visible)
                }
            },
        )
        view.input.setText(askDraft)
        view.input.setSelection(view.input.length())
        view.setTarget(
            line = if (fresh) askFreshLine else "读取对话中…",
            canSwitch = false,
            isFresh = fresh,
        )

        val (_, barH) = view.measureForWidth(barW)
        val pos = FloatingAskPlace.barPosition(
            screenWidth = screenW,
            screenHeight = screenH,
            orbLeft = orb.x,
            orbRight = orb.x + orb.width,
            orbCenterY = orb.y + orb.height / 2,
            dockedRight = dockedRight,
            barWidth = barW,
            barHeight = barH,
            gap = gap,
            margin = margin,
            topInset = ctx.dpPx(34f),
            bottomInset = ctx.dpPx(24f),
        )

        val lp = WindowManager.LayoutParams(
            barW,
            WindowManager.LayoutParams.WRAP_CONTENT,
            hostWindowType,
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
            x = pos.x
            y = pos.y
        }

        try {
            wm.addView(view, lp)
        } catch (_: Throwable) {
            return
        }
        askView = view
        askParams = lp
        askRestY = pos.y

        view.input.requestFocus()
        view.post {
            if (askView === view) {
                val imm = view.context.getSystemService(InputMethodManager::class.java)
                imm?.showSoftInput(view.input, InputMethodManager.SHOW_IMPLICIT)
            }
        }

        val reqId = ++askRequestSeq
        callDart("askTarget", mapOf("fresh" to fresh)) { raw ->
            if (reqId != askRequestSeq || askView !== view) return@callDart
            val map = raw as? Map<*, *>
            if (map == null) {
                view.setTarget("新对话 · 将在 AGY Go 中发送", canSwitch = false, isFresh = true)
                view.setStatus("应用后台未连接，发送时将自动拉起 AGY Go")
                view.setInteractionState(problem = false, isSending = false, canStop = false)
                return@callDart
            }
            val currentMap = map["current"] as? Map<*, *>
            val freshMap = map["fresh"] as? Map<*, *>
            askSessionId = currentMap?.get("sessionId") as? String
            askCurrentLine = currentMap?.get("line") as? String
            askFreshLine = (freshMap?.get("line") as? String) ?: "新对话 · AGY Go"
            val problem = map["problem"] as? String
            val isBusy = map["isBusy"] == true
            val statusText = map["statusText"] as? String
            val recentRaw = map["recent"] as? List<*>
            val recentLines = recentRaw.orEmpty().mapNotNull { item ->
                val row = item as? Map<*, *> ?: return@mapNotNull null
                val role = row["role"] as? String ?: return@mapNotNull null
                val text = (row["text"] as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                (role == "user") to text
            }
            view.setRecentPreview(recentLines)
            updateAskTargetHeader()
            view.setStatus(problem ?: statusText, isError = problem != null)
            view.setInteractionState(problem = problem != null, isSending = false, canStop = isBusy)
        }
    }

    private fun updateAskTargetHeader() {
        val view = askView ?: return
        val canSwitch = !askSessionId.isNullOrBlank() && !askCurrentLine.isNullOrBlank()
        val effectiveFresh = askFresh || !canSwitch
        val label = if (effectiveFresh) askFreshLine else (askCurrentLine ?: askFreshLine)
        view.setTarget(line = label, canSwitch = canSwitch, isFresh = effectiveFresh)
    }

    private fun liftAskBar(overlapBottom: Int, visible: Boolean) {
        val view = askView ?: return
        val lp = askParams ?: return
        val ctx = hostContext ?: return
        val loc = IntArray(2)
        view.getLocationOnScreen(loc)
        val nextY = when {
            overlapBottom > 0 -> FloatingAskPlace.liftForIme(
                restY = askRestY,
                currentScreenY = loc[1],
                imeOverlap = overlapBottom,
                gap = ctx.dpPx(8f),
                minY = ctx.dpPx(34f),
            )
            visible -> lp.y
            else -> askRestY
        }
        if (nextY != lp.y) {
            lp.y = nextY
            safeUpdateView(view, lp)
        }
    }

    private fun sendAskFromBar(text: String) {
        val view = askView ?: return
        val reqId = askRequestSeq
        val useFresh = askFresh || askSessionId.isNullOrBlank()
        view.setInteractionState(problem = false, isSending = true, canStop = false)
        view.setStatus("正在发送…", isError = false)
        val args = mapOf(
            "text" to text,
            "fresh" to useFresh,
            "sessionId" to if (useFresh) null else askSessionId,
        )
        callDart("askSend", args) { raw ->
            val current = reqId == askRequestSeq && askView === view
            val map = raw as? Map<*, *>
            when {
                map?.get("sent") == true -> {
                    askDraft = ""
                    getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(K_ASK_DRAFT).apply()
                    if (current) {
                        view.input.setText("")
                        dismissAskBar()
                    }
                    showStatusBubble(
                        key = "sent_${System.currentTimeMillis()}",
                        title = if (useFresh) "已发往新对话" else "已发送到当前对话",
                        body = text.take(80),
                        autoDismissMs = 3_000L,
                    )
                }
                map != null -> {
                    if (current) {
                        view.setInteractionState(problem = false, isSending = false, canStop = false)
                        view.setStatus((map["problem"] as? String) ?: "发送失败，请重试", isError = true)
                    }
                }
                else -> {
                    // Flutter engine unreachable: hand text straight to MainActivity composer so nothing is lost.
                    if (current) dismissAskBar()
                    bringAppToFront(prefill = text)
                }
            }
        }
    }

    private fun dismissAskBar() {
        askRequestSeq++
        askView?.let { v ->
            askDraft = v.input.text?.toString() ?: askDraft
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(K_ASK_DRAFT, askDraft)
                .apply()
            safeRemoveView(v)
        }
        askView = null
        askParams = null
    }

    // ---- Long-press Quick Menu ------------------------------------------------------------------

    private fun openQuickMenu() {
        val ctx = hostContext ?: return
        val wm = windowManager ?: return
        val orb = petParams ?: return
        dismissAskBar()
        dismissBubble()
        dismissMenu()

        val items = mutableListOf<Pair<String, () -> Unit>>(
            "问一句（悬浮输入）" to { openAskBar(fresh = false) },
            "新对话（悬浮输入）" to { openAskBar(fresh = true) },
            "打开 AGY Go" to { bringAppToFront(prefill = null) },
        )
        if (PhoneController.get(this).enabled) {
            items.add("紧急停止手机操控" to { PhoneController.get(this).emergencyStop() })
        }
        items.add(
            "隐藏悬浮球" to {
                enabled = false
                removeAllWindows()
                callDart("overlayHiddenByUser", null) { _ -> }
                notifyStatusChanged()
                stopSelf()
            },
        )

        val view = FloatingMenuView(ctx, items) { dismissMenu() }
        val menuW = ctx.dpPx(176f)
        val (_, menuH) = view.measureForWidth(menuW)
        val screenW = ctx.resources.displayMetrics.widthPixels
        val screenH = ctx.resources.displayMetrics.heightPixels
        val pos = FloatingAskPlace.barPosition(
            screenWidth = screenW,
            screenHeight = screenH,
            orbLeft = orb.x,
            orbRight = orb.x + orb.width,
            orbCenterY = orb.y + orb.height / 2,
            dockedRight = dockedRight,
            barWidth = menuW,
            barHeight = menuH,
            gap = ctx.dpPx(8f),
            margin = ctx.dpPx(10f),
            topInset = ctx.dpPx(34f),
            bottomInset = ctx.dpPx(24f),
        )
        val lp = WindowManager.LayoutParams(
            menuW,
            WindowManager.LayoutParams.WRAP_CONTENT,
            hostWindowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = pos.x
            y = pos.y
        }
        try {
            wm.addView(view, lp)
            menuView = view
        } catch (_: Throwable) {}
    }

    private fun dismissMenu() {
        menuView?.let(::safeRemoveView)
        menuView = null
    }

    // ---- Approval & Reply Bubbles ---------------------------------------------------------------

    private fun syncBubbleIfNeeded() {
        if (askView != null || menuView != null || petView == null) return
        val approval = pendingPhoneApproval
        if (approval != null) {
            val key = "approval:${approval.id}"
            if (activeBubbleKey == key && bubbleView != null) return
            showApprovalBubble(approval)
            return
        }
        val notice = pendingReplyBubble
        if (notice != null && notice.id != lastShownReplyBubbleId) {
            lastShownReplyBubbleId = notice.id
            showStatusBubble(
                key = "reply:${notice.id}",
                title = notice.title,
                body = notice.body,
                autoDismissMs = 7_500L,
            )
        }
    }

    private fun showApprovalBubble(approval: PendingApprovalBanner) {
        val ctx = hostContext ?: return
        val wm = windowManager ?: return
        val orb = petParams ?: return
        dismissBubble()

        val view = FloatingBubbleView(
            context = ctx,
            title = if (approval.highRisk) "高风险操作确认 · ${approval.tool}" else "手机操控确认 · ${approval.tool}",
            body = approval.summary,
            isApproval = true,
            isHighRisk = approval.highRisk,
            onTapBody = { bringAppToFront(prefill = null) },
            onDismiss = { dismissBubble() },
            onApprove = {
                dismissBubble()
                PhoneController.get(this).resolveApproval(approval.id, approved = true)
                callDart("resolvePhoneApproval", mapOf("id" to approval.id, "approved" to true)) { _ -> }
            },
            onDeny = {
                dismissBubble()
                PhoneController.get(this).resolveApproval(approval.id, approved = false)
                callDart("resolvePhoneApproval", mapOf("id" to approval.id, "approved" to false)) { _ -> }
            },
        )
        attachBubbleView(ctx, wm, orb, view, key = "approval:${approval.id}", autoDismissMs = null)
    }

    private fun showStatusBubble(
        key: String,
        title: String,
        body: String,
        autoDismissMs: Long,
    ) {
        val ctx = hostContext ?: return
        val wm = windowManager ?: return
        val orb = petParams ?: return
        dismissBubble()

        val view = FloatingBubbleView(
            context = ctx,
            title = title,
            body = body,
            isApproval = false,
            isHighRisk = false,
            onTapBody = {
                dismissBubble()
                openAskBar(fresh = false)
            },
            onDismiss = { dismissBubble() },
        )
        attachBubbleView(ctx, wm, orb, view, key = key, autoDismissMs = autoDismissMs)
    }

    private fun attachBubbleView(
        ctx: Context,
        wm: WindowManager,
        orb: WindowManager.LayoutParams,
        view: FloatingBubbleView,
        key: String,
        autoDismissMs: Long?,
    ) {
        val screenW = ctx.resources.displayMetrics.widthPixels
        val screenH = ctx.resources.displayMetrics.heightPixels
        val bubbleW = FloatingAskPlace.barWidth(
            screenWidth = screenW,
            orbLeft = orb.x,
            orbRight = orb.x + orb.width,
            dockedRight = dockedRight,
            gap = ctx.dpPx(8f),
            margin = ctx.dpPx(10f),
            minWidth = ctx.dpPx(210f),
            maxWidth = ctx.dpPx(280f),
        )
        val (_, bubbleH) = view.measureForWidth(bubbleW)
        val pos = FloatingAskPlace.barPosition(
            screenWidth = screenW,
            screenHeight = screenH,
            orbLeft = orb.x,
            orbRight = orb.x + orb.width,
            orbCenterY = orb.y + orb.height / 2,
            dockedRight = dockedRight,
            barWidth = bubbleW,
            barHeight = bubbleH,
            gap = ctx.dpPx(8f),
            margin = ctx.dpPx(10f),
            topInset = ctx.dpPx(34f),
            bottomInset = ctx.dpPx(24f),
        )
        val lp = WindowManager.LayoutParams(
            bubbleW,
            WindowManager.LayoutParams.WRAP_CONTENT,
            hostWindowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = pos.x
            y = pos.y
        }
        try {
            wm.addView(view, lp)
            bubbleView = view
            activeBubbleKey = key
            if (autoDismissMs != null) {
                val r = Runnable {
                    if (activeBubbleKey == key) dismissBubble()
                }
                bubbleAutoDismiss = r
                mainHandler.postDelayed(r, autoDismissMs)
            }
        } catch (_: Throwable) {}
    }

    private fun dismissBubble() {
        bubbleAutoDismiss?.let { mainHandler.removeCallbacks(it) }
        bubbleAutoDismiss = null
        bubbleView?.let(::safeRemoveView)
        bubbleView = null
        activeBubbleKey = null
    }

    private fun repositionSubWindows() {
        if (askView != null) {
            openAskBar(fresh = askFresh)
        } else if (bubbleView != null) {
            val prevKey = activeBubbleKey
            dismissBubble()
            if (prevKey?.startsWith("approval:") == true) {
                syncBubbleIfNeeded()
            }
        }
    }

    private fun bringAppToFront(prefill: String?) {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (!prefill.isNullOrBlank()) {
                putExtra(MainActivity.EXTRA_PREFILL_TEXT, prefill)
            }
        }
        startActivity(open)
    }

    private fun removeAllWindows() {
        mainHandler.removeCallbacks(ticker)
        dismissAskBar()
        dismissMenu()
        dismissBubble()
        petView?.let(::safeRemoveView)
        petView = null
        petParams = null
        isShowing = false
    }

    private fun safeUpdateView(view: View, lp: WindowManager.LayoutParams) {
        try {
            windowManager?.updateViewLayout(view, lp)
        } catch (_: Throwable) {}
    }

    private fun safeRemoveView(view: View) {
        try {
            windowManager?.removeView(view)
        } catch (_: Throwable) {}
    }

    private class StarlingOverlayView(context: Context) : View(context) {
        private var mood: String = "idle"
        private var phase: Float = 0f
        private var badgeCount: Int = 0

        private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2.5f
            color = Color.argb(150, 255, 255, 255)
        }
        private val eyePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        private val sparkPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(239, 68, 68)
            style = Paint.Style.FILL
        }

        fun setMood(next: String) {
            if (mood != next) {
                mood = next
                invalidate()
            }
        }

        fun setBadgeCount(count: Int) {
            if (badgeCount != count) {
                badgeCount = count
                invalidate()
            }
        }

        fun setAnimPhase(p: Float) {
            phase = p
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            val cx = w / 2f
            val bob = sin(phase.toDouble()).toFloat() * (if (mood == "happy") 4.5f else 2.2f)
            val cy = h / 2f + bob
            val r = minOf(w, h) * 0.34f

            val accent = when (mood) {
                "thinking" -> Color.rgb(107, 146, 248)
                "working" -> Color.rgb(42, 193, 146)
                "waitingApproval" -> Color.rgb(245, 158, 11)
                "happy" -> Color.rgb(156, 126, 245)
                "sleeping" -> Color.rgb(100, 116, 139)
                else -> Color.rgb(62, 99, 221)
            }

            haloPaint.color = Color.argb(72, Color.red(accent), Color.green(accent), Color.blue(accent))
            canvas.drawCircle(cx, cy, r * 1.28f, haloPaint)

            bodyPaint.color = accent
            canvas.drawCircle(cx, cy, r, bodyPaint)
            canvas.drawCircle(cx, cy, r, borderPaint)

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

            if (mood == "thinking" || mood == "working" || mood == "waitingApproval") {
                val orbitR = r * 1.18f
                val sx = cx + cos(phase * 2.0).toFloat() * orbitR
                val sy = cy + sin(phase * 2.0).toFloat() * orbitR
                sparkPaint.color = if (mood == "waitingApproval") Color.rgb(254, 240, 138) else Color.WHITE
                canvas.drawCircle(sx, sy, r * 0.16f, sparkPaint)
            }

            if (badgeCount > 0) {
                canvas.drawCircle(cx + r * 0.72f, cy - r * 0.72f, r * 0.28f, badgePaint)
            }
        }
    }

    data class PendingApprovalBanner(
        val id: String,
        val tool: String,
        val summary: String,
        val highRisk: Boolean,
    )

    data class ReplyBubbleNotice(
        val id: String,
        val title: String,
        val body: String,
    )

    interface DartBridge {
        fun call(method: String, args: Any?, reply: (Any?) -> Unit)
        fun onStatusChanged(status: Map<String, Any?>)
    }

    companion object {
        private const val PREFS = "agy_pet_overlay"
        private const val K_DOCK_RIGHT = "dock_right"
        private const val K_DOCK_Y = "dock_y"
        private const val K_ASK_DRAFT = "ask_draft"

        const val EXTRA_MOOD = "mood"
        const val EXTRA_FRESH = "fresh"
        private const val ACTION_HIDE = "io.github.kailian5922.agy_go.PET_HIDE"
        private const val ACTION_SYNC = "io.github.kailian5922.agy_go.PET_SYNC"
        private const val ACTION_OPEN_ASK = "io.github.kailian5922.agy_go.PET_OPEN_ASK"

        @Volatile private var activeInstance: PetOverlayService? = null
        @Volatile private var dartBridge: DartBridge? = null
        @Volatile var enabled: Boolean = false
            private set
        @Volatile var onlyOutsideApp: Boolean = true
            private set
        @Volatile var appInForeground: Boolean = true
            private set
        @Volatile var isShowing: Boolean = false
            private set
        @Volatile var currentMood: String = "idle"
            private set
        @Volatile private var pendingApprovalCount: Int = 0
        @Volatile private var pendingPhoneApproval: PendingApprovalBanner? = null
        @Volatile private var pendingReplyBubble: ReplyBubbleNotice? = null
        @Volatile private var lastShownReplyBubbleId: String? = null

        fun attachBridge(bridge: DartBridge?) {
            dartBridge = bridge
        }

        fun canHostOverlay(context: Context): Boolean =
            Settings.canDrawOverlays(context) || AgyAccessibilityService.isRunning()

        fun permissionMode(context: Context): String = when {
            Settings.canDrawOverlays(context) -> "overlay"
            AgyAccessibilityService.isRunning() -> "accessibility"
            else -> "none"
        }

        fun statusSnapshot(context: Context): Map<String, Any?> = mapOf(
            "enabled" to enabled,
            "showing" to isShowing,
            "onlyOutsideApp" to onlyOutsideApp,
            "canDrawOverlays" to Settings.canDrawOverlays(context),
            "canUseAccessibilityOverlay" to AgyAccessibilityService.isRunning(),
            "permissionMode" to permissionMode(context),
        )

        fun setAppForeground(context: Context, foreground: Boolean) {
            appInForeground = foreground
            if (enabled) {
                val svc = activeInstance
                if (svc != null) {
                    svc.mainHandler.post { svc.syncVisibility() }
                } else if (!foreground && canHostOverlay(context)) {
                    show(context, currentMood)
                }
            }
        }

        fun setOnlyOutsideApp(context: Context, outsideOnly: Boolean) {
            onlyOutsideApp = outsideOnly
            if (enabled) {
                val svc = activeInstance
                if (svc != null) {
                    svc.mainHandler.post { svc.syncVisibility() }
                } else {
                    show(context, currentMood)
                }
            }
            notifyStatusChanged(context)
        }

        fun show(context: Context, mood: String) {
            enabled = true
            currentMood = mood
            val intent = Intent(context, PetOverlayService::class.java).apply {
                putExtra(EXTRA_MOOD, mood)
            }
            try {
                context.startService(intent)
            } catch (_: Throwable) {}
            notifyStatusChanged(context)
        }

        fun openAskNow(context: Context, fresh: Boolean = false) {
            if (!canHostOverlay(context)) return
            enabled = true
            val svc = activeInstance
            if (svc != null) {
                svc.mainHandler.post {
                    svc.syncVisibility()
                    svc.openAskBar(fresh = fresh)
                }
            } else {
                val intent = Intent(context, PetOverlayService::class.java).apply {
                    action = ACTION_OPEN_ASK
                    putExtra(EXTRA_FRESH, fresh)
                }
                try {
                    context.startService(intent)
                } catch (_: Throwable) {}
            }
        }

        fun pushState(
            context: Context,
            mood: String,
            approval: PendingApprovalBanner?,
            replyBubble: ReplyBubbleNotice?,
        ) {
            currentMood = mood
            pendingPhoneApproval = approval
            pendingApprovalCount = if (approval != null) 1 else 0
            pendingReplyBubble = replyBubble
            val svc = activeInstance
            if (svc != null) {
                svc.mainHandler.post {
                    svc.petView?.setMood(mood)
                    svc.petView?.setBadgeCount(pendingApprovalCount)
                    if (approval == null && svc.activeBubbleKey?.startsWith("approval:") == true) {
                        svc.dismissBubble()
                    }
                    svc.syncBubbleIfNeeded()
                }
            } else if (enabled && (!onlyOutsideApp || !appInForeground) && canHostOverlay(context)) {
                show(context, mood)
            }
        }

        fun updateMood(context: Context, mood: String) {
            currentMood = mood
            activeInstance?.let { svc ->
                svc.mainHandler.post { svc.petView?.setMood(mood) }
            }
        }

        fun hide(context: Context) {
            enabled = false
            isShowing = false
            context.stopService(Intent(context, PetOverlayService::class.java))
            notifyStatusChanged(context)
        }

        private fun callDart(method: String, args: Any?, reply: (Any?) -> Unit) {
            val bridge = dartBridge
            if (bridge == null) {
                reply(null)
                return
            }
            bridge.call(method, args, reply)
        }

        private fun notifyStatusChanged(context: Context? = activeInstance) {
            val ctx = context ?: return
            dartBridge?.onStatusChanged(statusSnapshot(ctx))
        }
    }
}
