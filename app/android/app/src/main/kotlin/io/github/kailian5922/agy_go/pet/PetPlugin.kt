package io.github.kailian5922.agy_go.pet

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel bridge (`agy/pet`) controlling the system floating AGY Starling overlay.
 */
class PetPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, METHOD_CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canDrawOverlays" -> result.success(Settings.canDrawOverlays(context))
            "requestOverlayPermission" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}"),
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                context.startActivity(intent)
                result.success(null)
            }
            "setOverlayVisible" -> {
                val visible = call.argument<Boolean>("visible") ?: false
                val mood = call.argument<String>("mood") ?: "idle"
                if (visible) {
                    if (!Settings.canDrawOverlays(context)) {
                        result.error("NO_OVERLAY_PERMISSION", "请先授予「显示在其他应用上层」权限。", null)
                        return
                    }
                    PetOverlayService.show(context, mood)
                } else {
                    PetOverlayService.hide(context)
                }
                result.success(PetOverlayService.isShowing)
            }
            "setPetMood" -> {
                val mood = call.argument<String>("mood") ?: "idle"
                PetOverlayService.updateMood(context, mood)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val METHOD_CHANNEL = "agy/pet"
    }
}
