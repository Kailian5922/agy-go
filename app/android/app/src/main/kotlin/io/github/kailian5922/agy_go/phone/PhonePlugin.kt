package io.github.kailian5922.agy_go.phone

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.kailian5922.agy_go.runtime.AgyAuthHelper
import io.github.kailian5922.agy_go.runtime.AgyInstaller
import org.json.JSONObject
import java.io.File
import java.util.ArrayDeque

/**
 * Exposes Android MCP Phone Control & SafetyGate to Flutter (`agy/phone`, `agy/phone/events`).
 */
class PhonePlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val installer = AgyInstaller(context)
    private val auditLog = ArrayDeque<Map<String, Any?>>(120)

    @Volatile private var enabled = false
    @Volatile private var eventSink: EventChannel.EventSink? = null

    private val safetyGate = SafetyGate { prompt ->
        emit(mapOf("type" to "approvalRequest", "request" to prompt.toMap()))
    }

    private val mcpServer = PhoneMcpServer(
        context = context,
        safetyGate = safetyGate,
        isEnabled = { enabled },
        onAudit = { tool, summary, outcome ->
            val entry = mapOf(
                "atMs" to System.currentTimeMillis(),
                "tool" to tool,
                "summary" to summary,
                "outcome" to outcome,
            )
            synchronized(auditLog) {
                if (auditLog.size >= 120) auditLog.removeFirst()
                auditLog.addLast(entry)
            }
            emit(mapOf("type" to "audit", "entry" to entry))
        },
    )

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(statusSnapshot())
            "setEnabled" -> {
                val want = call.argument<Boolean>("enabled") ?: false
                enabled = want
                if (want) {
                    mcpServer.start()
                    syncAgyMcpSettings(register = true)
                } else {
                    safetyGate.emergencyStop()
                    mcpServer.stop()
                    syncAgyMcpSettings(register = false)
                }
                emitStatus()
                result.success(statusSnapshot())
            }
            "setSafetyMode" -> {
                safetyGate.mode = SafetyGate.Mode.parse(call.argument<String>("mode"))
                emitStatus()
                result.success(statusSnapshot())
            }
            "resolveApproval" -> {
                val id = call.argument<String>("id") ?: ""
                val approved = call.argument<Boolean>("approved") ?: false
                val ok = safetyGate.resolve(id, approved)
                result.success(ok)
            }
            "emergencyStop" -> {
                safetyGate.emergencyStop()
                enabled = false
                mcpServer.stop()
                syncAgyMcpSettings(register = false)
                emitStatus()
                result.success(null)
            }
            "openAccessibilitySettings" -> {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(null)
            }
            "getAuditLog" -> {
                val copy = synchronized(auditLog) { auditLog.toList() }
                result.success(copy)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(mapOf("type" to "status", "status" to statusSnapshot()))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun statusSnapshot(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "accessibilityConnected" to AgyAccessibilityService.isRunning(),
        "safetyMode" to safetyGate.mode.wire,
        "mcpPort" to mcpServer.port,
        "mcpUrl" to if (mcpServer.port > 0) mcpServer.url() else null,
        "mcpToken" to if (mcpServer.port > 0) mcpServer.authToken else null,
        "pendingApprovals" to safetyGate.pendingPrompts(),
    )

    private fun syncAgyMcpSettings(register: Boolean) {
        try {
            val file = AgyAuthHelper.settingsFile(installer.homeDir)
            file.parentFile?.mkdirs()
            val root = if (file.exists()) {
                try {
                    JSONObject(file.readText())
                } catch (_: Exception) {
                    JSONObject()
                }
            } else {
                JSONObject()
            }
            val servers = root.optJSONObject("mcpServers") ?: JSONObject()
            if (register && mcpServer.port > 0) {
                servers.put(
                    "phone",
                    JSONObject()
                        .put("httpUrl", mcpServer.url())
                        .put("headers", JSONObject().put("Authorization", "Bearer ${mcpServer.authToken}")),
                )
            } else {
                servers.remove("phone")
            }
            root.put("mcpServers", servers)
            val tmp = File(file.parentFile, "settings.json.tmp")
            tmp.writeText(root.toString(2))
            if (!tmp.renameTo(file)) {
                tmp.copyTo(file, overwrite = true)
                tmp.delete()
            }
        } catch (_: Throwable) {}
    }

    private fun emitStatus() {
        emit(mapOf("type" to "status", "status" to statusSnapshot()))
    }

    private fun emit(event: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(event)
            } catch (_: Throwable) {}
        }
    }

    fun dispose() {
        safetyGate.emergencyStop()
        mcpServer.stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    companion object {
        const val METHOD_CHANNEL = "agy/phone"
        const val EVENT_CHANNEL = "agy/phone/events"
    }
}
