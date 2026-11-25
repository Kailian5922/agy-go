package io.github.kailian5922.agy_go.runtime

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the Android on-device Antigravity CLI runtime to Flutter via:
 *  - MethodChannel `agy/runtime`
 *  - EventChannel  `agy/runtime/events`
 */
class RuntimePlugin(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, RuntimeController.EventListener {

    private val controller = RuntimeController.get(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    @Volatile private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        controller.addListener(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(controller.statusSnapshot())
            "getLogs" -> result.success(controller.recentLogs())
            "install" -> {
                controller.installOrUpdate()
                result.success(null)
            }
            "checkUpdate" -> {
                controller.checkLatestVersion { outcome ->
                    mainHandler.post {
                        outcome.onSuccess { result.success(it) }
                            .onFailure { result.error("CHECK_UPDATE_FAILED", it.message, null) }
                    }
                }
            }
            "start" -> {
                controller.start()
                result.success(null)
            }
            "stop" -> {
                controller.stop()
                result.success(null)
            }
            "reset" -> {
                val keepHome = call.argument<Boolean>("keepHome") ?: true
                controller.reset(keepHome)
                result.success(null)
            }
            "setAuthConfig" -> {
                val mode = call.argument<String>("mode") ?: AgyAuthHelper.MODE_OAUTH
                val apiKey = call.argument<String>("apiKey") ?: ""
                val baseUrl = call.argument<String>("baseUrl") ?: ""
                controller.setAuthConfig(mode, apiKey, baseUrl)
                result.success(null)
            }
            "setPreferProot" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                controller.setPreferProot(enabled)
                result.success(null)
            }
            "startOAuthLogin" -> {
                controller.startOAuthLogin()
                result.success(null)
            }
            "submitOAuthCode" -> {
                val code = call.argument<String>("code") ?: ""
                controller.submitOAuthCode(code)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(mapOf("type" to "status", "status" to controller.statusSnapshot()))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onEvent(event: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(event)
            } catch (_: Throwable) {}
        }
    }

    fun dispose() {
        controller.removeListener(this)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    companion object {
        const val METHOD_CHANNEL = "agy/runtime"
        const val EVENT_CHANNEL = "agy/runtime/events"
    }
}
