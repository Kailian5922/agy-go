package io.github.kailian5922.agy_go.phone

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter MethodChannel / EventChannel adapter (`agy/phone`, `agy/phone/events`) backed by the
 * process-wide [PhoneController] singleton. Disposing this plugin on Activity teardown detaches
 * only the Flutter sink without stopping the active MCP server.
 */
class PhonePlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val controller = PhoneController.get(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    @Volatile private var eventSink: EventChannel.EventSink? = null

    private val listener: (Map<String, Any?>) -> Unit = { event ->
        val sink = eventSink
        if (sink != null) {
            mainHandler.post {
                try {
                    sink.success(event)
                } catch (_: Throwable) {}
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    /** Called by MainActivity.onResume() so returning from Accessibility Settings updates immediately. */
    fun onResume() {
        controller.refreshStatus()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(controller.statusSnapshot())
            "setEnabled" -> {
                val want = call.argument<Boolean>("enabled") ?: false
                result.success(controller.setEnabled(want))
            }
            "setSafetyMode" -> {
                result.success(controller.setSafetyMode(call.argument<String>("mode")))
            }
            "resolveApproval" -> {
                val id = call.argument<String>("id") ?: ""
                val approved = call.argument<Boolean>("approved") ?: false
                result.success(controller.resolveApproval(id, approved))
            }
            "emergencyStop" -> {
                controller.emergencyStop()
                result.success(null)
            }
            "openAccessibilitySettings" -> {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(null)
            }
            "openAppDetails" -> {
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${context.packageName}"),
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(null)
            }
            "runSelfCheck" -> {
                controller.runSelfCheck { report ->
                    result.success(report)
                }
            }
            "getAuditLog" -> {
                result.success(controller.getAuditLog())
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        controller.addListener(listener)
    }

    override fun onCancel(arguments: Any?) {
        controller.removeListener(listener)
        eventSink = null
    }

    fun dispose() {
        controller.removeListener(listener)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    companion object {
        const val METHOD_CHANNEL = "agy/phone"
        const val EVENT_CHANNEL = "agy/phone/events"
    }
}
