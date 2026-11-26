package io.github.kailian5922.agy_go.pet

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bidirectional platform channel bridge (`agy/pet`) powering the out-of-app floating Starling orb,
 * DSH Go-style floating ask bar ("问一句"), and floating approval/reply bubbles.
 */
class PetPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, METHOD_CHANNEL)
    @Volatile private var disposed = false
    @Volatile private var pendingPrefillText: String? = null

    private val bridge = object : PetOverlayService.DartBridge {
        override fun call(method: String, args: Any?, reply: (Any?) -> Unit) {
            if (disposed) {
                reply(null)
                return
            }
            mainHandler.post {
                if (disposed) {
                    reply(null)
                    return@post
                }
                try {
                    channel.invokeMethod(
                        method,
                        args,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) = reply(result)
                            override fun error(code: String, msg: String?, details: Any?) = reply(null)
                            override fun notImplemented() = reply(null)
                        },
                    )
                } catch (_: Throwable) {
                    reply(null)
                }
            }
        }

        override fun onStatusChanged(status: Map<String, Any?>) {
            if (disposed) return
            mainHandler.post {
                if (disposed) return@post
                try {
                    channel.invokeMethod("statusChanged", status)
                } catch (_: Throwable) {}
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
        PetOverlayService.attachBridge(bridge)
    }

    fun onResume() {
        PetOverlayService.setAppForeground(context, true)
        bridge.onStatusChanged(PetOverlayService.statusSnapshot(context))
    }

    fun onPause() {
        PetOverlayService.setAppForeground(context, false)
    }

    fun deliverPrefillText(text: String?) {
        val clean = text?.trim().orEmpty()
        if (clean.isEmpty()) return
        pendingPrefillText = clean
        if (!disposed) {
            mainHandler.post {
                if (disposed) return@post
                try {
                    channel.invokeMethod("prefillComposer", mapOf("text" to clean))
                    pendingPrefillText = null
                } catch (_: Throwable) {}
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canDrawOverlays" -> result.success(PetOverlayService.canHostOverlay(context))
            "getStatus" -> result.success(PetOverlayService.statusSnapshot(context))
            "requestOverlayPermission" -> {
                val opened = startSettingsIntent(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${context.packageName}"),
                    ),
                ) || openAppDetails()
                result.success(opened)
            }
            "openAppDetails" -> result.success(openAppDetails())
            "setOnlyOutsideApp" -> {
                val outsideOnly = call.argument<Boolean>("onlyOutsideApp") ?: true
                PetOverlayService.setOnlyOutsideApp(context, outsideOnly)
                result.success(PetOverlayService.statusSnapshot(context))
            }
            "setOverlayVisible" -> {
                val visible = call.argument<Boolean>("visible") ?: false
                val mood = call.argument<String>("mood") ?: "idle"
                val outsideOnly = call.argument<Boolean>("onlyOutsideApp")
                if (outsideOnly != null) {
                    PetOverlayService.setOnlyOutsideApp(context, outsideOnly)
                }
                if (visible) {
                    if (!PetOverlayService.canHostOverlay(context)) {
                        result.error(
                            "NO_OVERLAY_PERMISSION",
                            "请先授予「显示在其他应用上层」权限或开启手机操控无障碍服务。",
                            null,
                        )
                        return
                    }
                    PetOverlayService.show(context, mood)
                } else {
                    PetOverlayService.hide(context)
                }
                result.success(visible)
            }
            "openAskBar" -> {
                val fresh = call.argument<Boolean>("fresh") ?: false
                if (!PetOverlayService.canHostOverlay(context)) {
                    result.success(false)
                } else {
                    PetOverlayService.openAskNow(context, fresh = fresh)
                    result.success(true)
                }
            }
            "setPetMood" -> {
                val mood = call.argument<String>("mood") ?: "idle"
                PetOverlayService.updateMood(context, mood)
                result.success(null)
            }
            "pushOverlayState" -> {
                val mood = call.argument<String>("mood") ?: "idle"
                val approvalMap = call.argument<Map<String, Any?>>("approval")
                val approval = approvalMap?.let { m ->
                    val id = m["id"] as? String ?: return@let null
                    PetOverlayService.PendingApprovalBanner(
                        id = id,
                        tool = (m["tool"] as? String) ?: "phone",
                        summary = (m["summary"] as? String) ?: "需要确认手机操控操作",
                        highRisk = m["highRisk"] == true,
                    )
                }
                val bubbleMap = call.argument<Map<String, Any?>>("replyBubble")
                val bubble = bubbleMap?.let { m ->
                    val id = m["id"] as? String ?: return@let null
                    val body = (m["body"] as? String)?.trim().orEmpty()
                    if (body.isEmpty()) return@let null
                    PetOverlayService.ReplyBubbleNotice(
                        id = id,
                        title = (m["title"] as? String) ?: "AGY Go 回复",
                        body = body,
                    )
                }
                PetOverlayService.pushState(context, mood = mood, approval = approval, replyBubble = bubble)
                result.success(null)
            }
            "takePendingPrefill" -> {
                val text = pendingPrefillText
                pendingPrefillText = null
                result.success(text)
            }
            else -> result.notImplemented()
        }
    }

    private fun openAppDetails(): Boolean = startSettingsIntent(
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${context.packageName}"),
        ),
    )

    private fun startSettingsIntent(intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (_: Throwable) {
        false
    }

    fun dispose() {
        disposed = true
        PetOverlayService.attachBridge(null)
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val METHOD_CHANNEL = "agy/pet"
    }
}
