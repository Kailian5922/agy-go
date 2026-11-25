package io.github.kailian5922.agy_go.runtime

import android.Manifest
import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the Android on-device Antigravity CLI runtime and shared phone storage mounter
 * to Flutter via:
 *  - MethodChannel `agy/runtime`
 *  - EventChannel  `agy/runtime/events`
 */
class RuntimePlugin(
    private val context: Context,
    private val activityProvider: () -> Activity?,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, RuntimeController.EventListener {

    private val controller = RuntimeController.get(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    @Volatile private var eventSink: EventChannel.EventSink? = null
    private var pendingStorageResult: MethodChannel.Result? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        controller.addListener(this)
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != STORAGE_REQUEST_CODE) return false
        controller.notifyStorageChanged()
        pendingStorageResult?.success(PhoneStorage.status(context))
        pendingStorageResult = null
        return true
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
                val phoneStorage = call.argument<Boolean>("phoneStorage")
                val binds = call.argument<List<String>>("extraBinds")
                controller.start(phoneStorage = phoneStorage, extraBinds = binds)
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
            "setPhoneStorage" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                controller.setPhoneStorage(enabled)
                result.success(PhoneStorage.status(context))
            }
            "setWorkspaceBinds" -> {
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                controller.setWorkspaceBinds(paths)
                result.success(null)
            }
            "storageStatus" -> result.success(PhoneStorage.status(context))
            "requestStorage" -> requestStorage(result)
            "openAllFilesAccess" -> {
                val intent = PhoneStorage.allFilesAccessIntent(context)
                result.success(intent != null && runCatching { context.startActivity(intent) }.isSuccess)
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

    private fun requestStorage(result: MethodChannel.Result) {
        if (PhoneStorage.isGranted(context)) {
            controller.notifyStorageChanged()
            result.success(PhoneStorage.status(context))
            return
        }
        val activity = activityProvider()
        if (activity == null) {
            result.error("NO_ACTIVITY", "No foreground activity available", null)
            return
        }
        pendingStorageResult?.success(PhoneStorage.status(context))
        pendingStorageResult = result
        activity.requestPermissions(
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ),
            STORAGE_REQUEST_CODE,
        )
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
        pendingStorageResult = null
    }

    companion object {
        const val METHOD_CHANNEL = "agy/runtime"
        const val EVENT_CHANNEL = "agy/runtime/events"
        private const val STORAGE_REQUEST_CODE = 0x5d5
    }
}
