package io.github.kailian5922.agy_go.pet

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Pure geometry helpers for placing the out-of-app floating ask bar beside the docked orb
 * and lifting it smoothly above the soft keyboard (mirroring DSH Go's AskPlace).
 */
object FloatingAskPlace {
    data class Pos(val x: Int, val y: Int)

    fun barWidth(
        screenWidth: Int,
        orbLeft: Int,
        orbRight: Int,
        dockedRight: Boolean,
        gap: Int,
        margin: Int,
        minWidth: Int,
        maxWidth: Int,
    ): Int {
        val full = (screenWidth - 2 * margin).coerceAtLeast(120)
        val besideRoom = if (dockedRight) {
            orbLeft - gap - margin
        } else {
            screenWidth - margin - (orbRight + gap)
        }
        // On narrow phones, let the bar span cleanly across the width if beside-room is cramped.
        val preferred = if (besideRoom >= minWidth) besideRoom else full
        return preferred.coerceIn(minWidth.coerceAtMost(full), maxWidth.coerceAtMost(full))
    }

    fun barPosition(
        screenWidth: Int,
        screenHeight: Int,
        orbLeft: Int,
        orbRight: Int,
        orbCenterY: Int,
        dockedRight: Boolean,
        barWidth: Int,
        barHeight: Int,
        gap: Int,
        margin: Int,
        topInset: Int,
        bottomInset: Int,
    ): Pos {
        val besideX = if (dockedRight) orbLeft - gap - barWidth else orbRight + gap
        val minX = margin
        val maxX = (screenWidth - margin - barWidth).coerceAtLeast(minX)
        val x = if (besideX in minX..maxX) {
            besideX
        } else {
            ((screenWidth - barWidth) / 2).coerceIn(minX, maxX)
        }
        val minY = topInset + margin
        val maxY = (screenHeight - bottomInset - margin - barHeight).coerceAtLeast(minY)
        val y = (orbCenterY - barHeight / 2).coerceIn(minY, maxY)
        return Pos(x, y)
    }

    fun liftForIme(
        restY: Int,
        currentScreenY: Int,
        imeOverlap: Int,
        gap: Int,
        minY: Int,
    ): Int {
        if (imeOverlap <= 0) return restY
        return minOf(restY, currentScreenY - imeOverlap - gap).coerceAtLeast(minY)
    }
}

internal data class FloatingPalette(
    val fill: Int,
    val inputBg: Int,
    val stroke: Int,
    val ink: Int,
    val muted: Int,
    val accent: Int,
    val onAccent: Int,
    val tonal: Int,
    val onTonal: Int,
    val danger: Int,
    val success: Int,
) {
    companion object {
        fun of(context: Context): FloatingPalette {
            val night = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
            return if (night) {
                FloatingPalette(
                    fill = Color.argb(244, 24, 27, 36),
                    inputBg = Color.argb(255, 36, 40, 52),
                    stroke = Color.argb(65, 255, 255, 255),
                    ink = Color.rgb(241, 245, 249),
                    muted = Color.rgb(156, 163, 175),
                    accent = Color.rgb(91, 134, 247),
                    onAccent = Color.WHITE,
                    tonal = Color.argb(72, 91, 134, 247),
                    onTonal = Color.rgb(186, 206, 255),
                    danger = Color.rgb(248, 113, 113),
                    success = Color.rgb(52, 211, 153),
                )
            } else {
                FloatingPalette(
                    fill = Color.argb(246, 252, 253, 255),
                    inputBg = Color.rgb(241, 244, 249),
                    stroke = Color.argb(42, 15, 23, 42),
                    ink = Color.rgb(15, 23, 42),
                    muted = Color.rgb(100, 116, 139),
                    accent = Color.rgb(62, 99, 221),
                    onAccent = Color.WHITE,
                    tonal = Color.argb(34, 62, 99, 221),
                    onTonal = Color.rgb(43, 73, 180),
                    danger = Color.rgb(220, 38, 38),
                    success = Color.rgb(5, 150, 105),
                )
            }
        }
    }
}

internal fun Context.dpPx(dp: Float): Int =
    (dp * resources.displayMetrics.density + 0.5f).toInt()

/**
 * DSH Go-style out-of-app floating input bar ("问一句"):
 * - Header row: active conversation/workspace target + 「新对话」 toggle pill + 「打开」 app button.
 * - Optional compact preview of the latest reply or live turn status.
 * - Multi-line EditText that takes window focus while open so Android's IME appears directly over
 *   the current app, lifting above the keyboard on API 30+, and closing cleanly on outside tap or Back.
 */
@SuppressLint("ViewConstructor")
internal class FloatingAskBarView(
    context: Context,
    private val listener: Listener,
) : LinearLayout(context) {

    interface Listener {
        fun onSend(text: String)
        fun onToggleFresh()
        fun onStopTurn()
        fun onOpenApp()
        fun onDraftChanged(text: String)
        fun onClose()
        fun onImeInsets(overlapBottom: Int, visible: Boolean)
    }

    private val palette = FloatingPalette.of(context)

    private val targetLabel = TextView(context).apply {
        textSize = 12f
        setTextColor(palette.muted)
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        text = "正在连接 AGY Go…"
    }

    private val freshChip = TextView(context).apply {
        text = "新对话"
        textSize = 11.5f
        gravity = Gravity.CENTER
        minHeight = context.dpPx(26f)
        setPadding(context.dpPx(9f), 0, context.dpPx(9f), 0)
        isClickable = true
        visibility = GONE
        setOnClickListener { listener.onToggleFresh() }
    }

    private val openAppChip = TextView(context).apply {
        text = "打开"
        textSize = 11.5f
        gravity = Gravity.CENTER
        minHeight = context.dpPx(26f)
        setPadding(context.dpPx(9f), 0, context.dpPx(9f), 0)
        setTextColor(palette.muted)
        background = GradientDrawable().apply {
            cornerRadius = context.dpPx(13f).toFloat()
            setColor(palette.inputBg)
        }
        isClickable = true
        setOnClickListener { listener.onOpenApp() }
    }

    private val recentBox = LinearLayout(context).apply {
        orientation = VERTICAL
        visibility = GONE
        setPadding(context.dpPx(8f), context.dpPx(6f), context.dpPx(8f), context.dpPx(6f))
        background = GradientDrawable().apply {
            cornerRadius = context.dpPx(11f).toFloat()
            setColor(palette.inputBg)
        }
    }

    val input: EditText = object : EditText(context) {
        override fun onKeyPreIme(keyCode: Int, event: KeyEvent?): Boolean {
            if (keyCode == KeyEvent.KEYCODE_BACK && event?.action == KeyEvent.ACTION_UP) {
                listener.onClose()
                return true
            }
            return super.onKeyPreIme(keyCode, event)
        }
    }.apply {
        textSize = 14.5f
        setTextColor(palette.ink)
        setHintTextColor(palette.muted)
        hint = "在应用外问一句，回车发送…"
        background = GradientDrawable().apply {
            cornerRadius = context.dpPx(14f).toFloat()
            setColor(palette.inputBg)
        }
        setPadding(context.dpPx(12f), context.dpPx(9f), context.dpPx(12f), context.dpPx(9f))
        inputType = InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_FLAG_MULTI_LINE or
            InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        imeOptions = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        maxLines = 4
        filters = arrayOf(InputFilter.LengthFilter(MAX_TEXT))
        setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                triggerSend()
                true
            } else {
                false
            }
        }
    }

    private val stopButton = TextView(context).apply {
        text = "停止"
        textSize = 12f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        background = GradientDrawable().apply {
            cornerRadius = context.dpPx(19f).toFloat()
            setColor(palette.danger)
        }
        visibility = GONE
        isClickable = true
        setOnClickListener { listener.onStopTurn() }
    }

    private val sendButton = TextView(context).apply {
        text = "发送"
        textSize = 12.5f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setTextColor(palette.onAccent)
        isClickable = true
        setOnClickListener { triggerSend() }
    }

    private val statusLine = TextView(context).apply {
        textSize = 11.5f
        setTextColor(palette.muted)
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
        visibility = GONE
    }

    private var blocked = false
    private var sending = false

    init {
        orientation = VERTICAL
        val pad = context.dpPx(12f)
        setPadding(pad, context.dpPx(10f), pad, pad)
        elevation = context.dpPx(10f).toFloat()
        background = GradientDrawable().apply {
            cornerRadius = context.dpPx(18f).toFloat()
            setColor(palette.fill)
            setStroke(context.dpPx(1f).coerceAtLeast(1), palette.stroke)
        }

        val header = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(targetLabel, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        header.addView(
            freshChip,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = context.dpPx(6f)
            },
        )
        header.addView(
            openAppChip,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = context.dpPx(6f)
            },
        )
        addView(header, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))

        addView(
            recentBox,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = context.dpPx(6f)
            },
        )

        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        row.addView(input, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        row.addView(
            stopButton,
            LayoutParams(context.dpPx(48f), context.dpPx(38f)).apply {
                marginStart = context.dpPx(6f)
            },
        )
        row.addView(
            sendButton,
            LayoutParams(context.dpPx(54f), context.dpPx(38f)).apply {
                marginStart = context.dpPx(6f)
            },
        )
        addView(
            row,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = context.dpPx(8f)
            },
        )
        addView(
            statusLine,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = context.dpPx(6f)
            },
        )

        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                refreshButtons()
                listener.onDraftChanged(s?.toString().orEmpty())
            }
        })

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            setOnApplyWindowInsetsListener { _, insets ->
                val imeBottom = insets.getInsets(WindowInsets.Type.ime()).bottom
                val imeVisible = insets.isVisible(WindowInsets.Type.ime())
                listener.onImeInsets(imeBottom, imeVisible)
                insets
            }
        }

        setFreshSwitch(shown = false, selected = false)
        refreshButtons()
    }

    fun setTarget(line: String, canSwitch: Boolean, isFresh: Boolean) {
        targetLabel.text = line
        setFreshSwitch(shown = canSwitch, selected = isFresh)
    }

    private fun setFreshSwitch(shown: Boolean, selected: Boolean) {
        freshChip.visibility = if (shown) VISIBLE else GONE
        freshChip.setTextColor(if (selected) palette.onTonal else palette.ink)
        freshChip.background = GradientDrawable().apply {
            cornerRadius = context.dpPx(13f).toFloat()
            setColor(if (selected) palette.tonal else palette.fill)
            if (!selected) {
                setStroke(context.dpPx(1f).coerceAtLeast(1), palette.stroke)
            }
        }
    }

    fun setRecentPreview(lines: List<Pair<Boolean, String>>) {
        recentBox.removeAllViews()
        if (lines.isEmpty()) {
            recentBox.visibility = GONE
            return
        }
        recentBox.visibility = VISIBLE
        lines.takeLast(2).forEachIndexed { idx, (isUser, text) ->
            val tv = TextView(context).apply {
                this.text = if (isUser) "你：$text" else "AGY：$text"
                textSize = 12f
                setTextColor(if (isUser) palette.muted else palette.ink)
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            }
            recentBox.addView(
                tv,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                    if (idx > 0) topMargin = context.dpPx(4f)
                },
            )
        }
    }

    fun setStatus(text: String?, isError: Boolean = false) {
        if (text.isNullOrBlank()) {
            statusLine.visibility = GONE
            return
        }
        statusLine.text = text
        statusLine.setTextColor(if (isError) palette.danger else palette.muted)
        statusLine.visibility = VISIBLE
    }

    fun setInteractionState(
        problem: Boolean = blocked,
        isSending: Boolean = sending,
        canStop: Boolean = false,
    ) {
        blocked = problem
        sending = isSending
        input.isEnabled = !isSending
        stopButton.visibility = if (canStop && !isSending) VISIBLE else GONE
        refreshButtons()
    }

    private fun refreshButtons() {
        val enabled = !input.text.isNullOrBlank() && !blocked && !sending
        sendButton.isEnabled = enabled
        sendButton.alpha = if (enabled) 1f else 0.45f
        sendButton.background = GradientDrawable().apply {
            cornerRadius = context.dpPx(19f).toFloat()
            setColor(if (enabled) palette.accent else palette.inputBg)
        }
        sendButton.setTextColor(if (enabled) palette.onAccent else palette.muted)
    }

    private fun triggerSend() {
        val text = input.text?.toString()?.trim().orEmpty()
        if (text.isEmpty() || blocked || sending) return
        listener.onSend(text)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_UP) listener.onClose()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
            listener.onClose()
            return true
        }
        return super.dispatchTouchEvent(event)
    }

    fun measureForWidth(widthPx: Int): Pair<Int, Int> {
        measure(
            MeasureSpec.makeMeasureSpec(widthPx, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
        )
        return measuredWidth to measuredHeight
    }

    companion object {
        const val MAX_TEXT = 4_000
    }
}

/**
 * Compact frosted bubble beside the docked orb showing either:
 * 1. A Phone Control / Tool approval prompt with inline 「拒绝」 / 「允许」 buttons right on top of other apps.
 * 2. A concise status or reply snippet (tap to open the floating ask bar).
 */
@SuppressLint("ViewConstructor")
internal class FloatingBubbleView(
    context: Context,
    title: String,
    body: String,
    isApproval: Boolean,
    isHighRisk: Boolean,
    private val onTapBody: () -> Unit,
    private val onDismiss: () -> Unit,
    private val onApprove: (() -> Unit)? = null,
    private val onDeny: (() -> Unit)? = null,
) : LinearLayout(context) {

    private val palette = FloatingPalette.of(context)

    init {
        orientation = VERTICAL
        val pad = context.dpPx(11f)
        setPadding(pad, context.dpPx(9f), pad, context.dpPx(9f))
        elevation = context.dpPx(8f).toFloat()
        val strokeColor = when {
            isApproval && isHighRisk -> palette.danger
            isApproval -> Color.rgb(245, 158, 11)
            else -> palette.stroke
        }
        background = GradientDrawable().apply {
            cornerRadius = context.dpPx(16f).toFloat()
            setColor(palette.fill)
            setStroke(context.dpPx(if (isApproval) 1.5f else 1f).coerceAtLeast(1), strokeColor)
        }

        val topRow = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val titleView = TextView(context).apply {
            text = title
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(if (isApproval) strokeColor else palette.accent)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        val closeView = TextView(context).apply {
            text = "✕"
            textSize = 12f
            setTextColor(palette.muted)
            setPadding(context.dpPx(8f), 0, context.dpPx(2f), 0)
            isClickable = true
            setOnClickListener { onDismiss() }
        }
        topRow.addView(titleView, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        topRow.addView(closeView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        addView(topRow, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))

        val bodyView = TextView(context).apply {
            text = body
            textSize = 13f
            setTextColor(palette.ink)
            maxLines = 3
            ellipsize = TextUtils.TruncateAt.END
            setOnClickListener { onTapBody() }
        }
        addView(
            bodyView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = context.dpPx(4f)
            },
        )

        if (isApproval && onApprove != null && onDeny != null) {
            val actions = LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.END
            }
            val denyBtn = TextView(context).apply {
                text = "拒绝"
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setTextColor(palette.danger)
                setPadding(context.dpPx(14f), context.dpPx(6f), context.dpPx(14f), context.dpPx(6f))
                background = GradientDrawable().apply {
                    cornerRadius = context.dpPx(14f).toFloat()
                    setColor(palette.inputBg)
                }
                isClickable = true
                setOnClickListener { onDeny.invoke() }
            }
            val allowBtn = TextView(context).apply {
                text = "允许"
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setPadding(context.dpPx(14f), context.dpPx(6f), context.dpPx(14f), context.dpPx(6f))
                background = GradientDrawable().apply {
                    cornerRadius = context.dpPx(14f).toFloat()
                    setColor(palette.accent)
                }
                isClickable = true
                setOnClickListener { onApprove.invoke() }
            }
            actions.addView(denyBtn, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
            actions.addView(
                allowBtn,
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                    marginStart = context.dpPx(8f)
                },
            )
            addView(
                actions,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                    topMargin = context.dpPx(8f)
                },
            )
        }
    }

    fun measureForWidth(widthPx: Int): Pair<Int, Int> {
        measure(
            MeasureSpec.makeMeasureSpec(widthPx, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
        )
        return measuredWidth to measuredHeight
    }
}

/**
 * Compact long-press quick menu beside the floating orb (mirroring DSH Go's PetMenuView).
 */
@SuppressLint("ViewConstructor")
internal class FloatingMenuView(
    context: Context,
    items: List<Pair<String, () -> Unit>>,
    private val onDismiss: () -> Unit,
) : LinearLayout(context) {

    private val palette = FloatingPalette.of(context)

    init {
        orientation = VERTICAL
        setPadding(context.dpPx(6f), context.dpPx(6f), context.dpPx(6f), context.dpPx(6f))
        elevation = context.dpPx(8f).toFloat()
        background = GradientDrawable().apply {
            cornerRadius = context.dpPx(16f).toFloat()
            setColor(palette.fill)
            setStroke(context.dpPx(1f).coerceAtLeast(1), palette.stroke)
        }
        items.forEachIndexed { idx, (label, action) ->
            val row = TextView(context).apply {
                text = label
                textSize = 13.5f
                setTextColor(if (label.contains("停止") || label.contains("隐藏")) palette.danger else palette.ink)
                setPadding(context.dpPx(12f), context.dpPx(9f), context.dpPx(12f), context.dpPx(9f))
                isClickable = true
                setOnClickListener {
                    onDismiss()
                    action()
                }
            }
            addView(
                row,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                    if (idx > 0) topMargin = context.dpPx(2f)
                },
            )
        }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
            onDismiss()
            return true
        }
        return super.dispatchTouchEvent(event)
    }

    fun measureForWidth(widthPx: Int): Pair<Int, Int> {
        measure(
            MeasureSpec.makeMeasureSpec(widthPx, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
        )
        return measuredWidth to measuredHeight
    }
}
