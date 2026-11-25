package io.github.kailian5922.agy_go.phone

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Android AccessibilityService backing AGY Go's MCP phone-control tools.
 * Only performs actions when invoked by PhoneMcpServer after SafetyGate approval.
 */
class AgyAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString()
        if (!pkg.isNullOrBlank()) {
            lastForegroundPackage = pkg
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    fun foregroundPackage(): String? =
        rootInActiveWindow?.packageName?.toString() ?: lastForegroundPackage

    /** Captures a compact structured snapshot of interactive & visible UI elements. */
    fun readScreenTree(maxNodes: Int = 140): JSONObject {
        val root = rootInActiveWindow
        val result = JSONObject()
        val pkg = root?.packageName?.toString() ?: lastForegroundPackage ?: "unknown"
        result.put("package", pkg)
        val nodes = JSONArray()
        if (root != null) {
            collectNodes(root, nodes, maxNodes)
        }
        result.put("nodeCount", nodes.length())
        result.put("nodes", nodes)
        return result
    }

    private fun collectNodes(node: AccessibilityNodeInfo, out: JSONArray, maxNodes: Int) {
        if (out.length() >= maxNodes) return
        val text = node.text?.toString()?.trim().orEmpty()
        val desc = node.contentDescription?.toString()?.trim().orEmpty()
        val resId = node.viewIdResourceName?.substringAfterLast('/').orEmpty()
        val interactive = node.isClickable || node.isEditable || node.isCheckable || node.isScrollable

        if (node.isVisibleToUser && (text.isNotEmpty() || desc.isNotEmpty() || interactive)) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            if (rect.width() > 0 && rect.height() > 0) {
                val obj = JSONObject()
                obj.put("i", out.length())
                if (text.isNotEmpty()) obj.put("text", text.take(120))
                if (desc.isNotEmpty()) obj.put("desc", desc.take(120))
                if (resId.isNotEmpty()) obj.put("id", resId)
                obj.put("cls", node.className?.toString()?.substringAfterLast('.') ?: "View")
                obj.put("cx", rect.centerX())
                obj.put("cy", rect.centerY())
                obj.put("bounds", JSONArray(listOf(rect.left, rect.top, rect.right, rect.bottom)))
                if (node.isClickable) obj.put("clickable", true)
                if (node.isEditable) obj.put("editable", true)
                if (node.isScrollable) obj.put("scrollable", true)
                if (node.isFocused) obj.put("focused", true)
                out.put(obj)
            }
        }

        for (i in 0 until node.childCount) {
            if (out.length() >= maxNodes) break
            val child = node.getChild(i) ?: continue
            collectNodes(child, out, maxNodes)
        }
    }

    fun tap(x: Float, y: Float, durationMs: Long = 60L): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs.coerceIn(20L, 2000L))
        return dispatchAndWait(GestureDescription.Builder().addStroke(stroke).build())
    }

    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 320L): Boolean {
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs.coerceIn(80L, 3000L))
        return dispatchAndWait(GestureDescription.Builder().addStroke(stroke).build())
    }

    fun inputText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val target = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: findFirstEditable(root)
            ?: return false
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun pressGlobal(actionName: String): Boolean {
        val code = when (actionName.lowercase()) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings" -> GLOBAL_ACTION_QUICK_SETTINGS
            else -> return false
        }
        return performGlobalAction(code)
    }

    fun captureScreenshotJpegBase64(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val latch = CountDownLatch(1)
        val out = AtomicReference<String?>(null)
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    try {
                        val hw = Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                        val soft = hw?.copy(Bitmap.Config.ARGB_8888, false)
                        screenshot.hardwareBuffer.close()
                        hw?.recycle()
                        if (soft != null) {
                            val maxDim = 1080
                            val scale = minOf(1f, maxDim.toFloat() / maxOf(soft.width, soft.height))
                            val resized = if (scale < 1f) {
                                Bitmap.createScaledBitmap(
                                    soft,
                                    (soft.width * scale).toInt().coerceAtLeast(1),
                                    (soft.height * scale).toInt().coerceAtLeast(1),
                                    true,
                                ).also { soft.recycle() }
                            } else {
                                soft
                            }
                            val baos = ByteArrayOutputStream()
                            resized.compress(Bitmap.CompressFormat.JPEG, 72, baos)
                            resized.recycle()
                            out.set(Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP))
                        }
                    } catch (_: Throwable) {
                        out.set(null)
                    } finally {
                        latch.countDown()
                    }
                }

                override fun onFailure(errorCode: Int) {
                    latch.countDown()
                }
            },
        )
        latch.await(6, TimeUnit.SECONDS)
        return out.get()
    }

    private fun findFirstEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable && node.isVisibleToUser) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val hit = findFirstEditable(child)
            if (hit != null) return hit
        }
        return null
    }

    private fun dispatchAndWait(gesture: GestureDescription): Boolean {
        val latch = CountDownLatch(1)
        var ok = false
        val started = dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    ok = true
                    latch.countDown()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    ok = false
                    latch.countDown()
                }
            },
            null,
        )
        if (!started) return false
        latch.await(5, TimeUnit.SECONDS)
        return ok
    }

    companion object {
        @Volatile var instance: AgyAccessibilityService? = null
            private set

        @Volatile var lastForegroundPackage: String? = null
            private set

        fun isRunning(): Boolean = instance != null
    }
}
