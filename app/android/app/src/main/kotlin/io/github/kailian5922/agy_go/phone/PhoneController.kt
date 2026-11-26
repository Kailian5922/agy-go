package io.github.kailian5922.agy_go.phone

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.github.kailian5922.agy_go.runtime.AgyAuthHelper
import io.github.kailian5922.agy_go.runtime.AgyInstaller
import io.github.kailian5922.agy_go.runtime.RuntimeController
import org.json.JSONObject
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors

/**
 * Process-wide singleton owning Android Phone Control state, SafetyGate, and the local
 * Streamable HTTP MCP server (`PhoneMcpServer`).
 *
 * Keeping this singleton outside [io.github.kailian5922.agy_go.MainActivity] guarantees:
 * 1. Activity recreation or switching to another app NEVER stops `PhoneMcpServer`.
 * 2. Persisted `enabled` / `safetyMode` survive app restarts and stay synced with
 *    Antigravity CLI's official `~/.gemini/config/mcp_config.json` (`serverUrl`) BEFORE `agy acp` launches.
 * 3. Live AccessibilityService bind/unbind events and MCP client handshakes update Flutter immediately.
 */
class PhoneController private constructor(private val appContext: Context) {

    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val installer = AgyInstaller(appContext)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "agy-phone-ctrl").apply { isDaemon = true }
    }
    private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()
    private val auditLog = ArrayDeque<Map<String, Any?>>(120)

    @Volatile var enabled: Boolean = prefs.getBoolean(KEY_ENABLED, false)
        private set

    val safetyGate = SafetyGate { prompt ->
        emit(mapOf("type" to "approvalRequest", "request" to prompt.toMap()))
        emitStatus()
    }.apply {
        mode = SafetyGate.Mode.parse(prefs.getString(KEY_SAFETY_MODE, null))
    }

    val mcpServer = PhoneMcpServer(
        context = appContext,
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
        onClientActivity = {
            emitStatus()
        },
    )

    init {
        AgyAccessibilityService.addStateListener {
            emitStatus()
        }
        // Restore live server + config immediately if user left Phone Control enabled previously.
        if (enabled) {
            ensureStartedAndSynced()
        } else {
            writePhoneMcpConfig(installer.homeDir, url = null, token = null, register = false)
        }
    }

    fun addListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.add(listener)
        listener(mapOf("type" to "status", "status" to statusSnapshot()))
    }

    fun removeListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.remove(listener)
    }

    /**
     * Called by [RuntimeController] right BEFORE launching `agy acp` so `~/.gemini/config/mcp_config.json`
     * always matches the live `PhoneMcpServer` port & Bearer token (or removes any stale dead entry).
     */
    @Synchronized
    fun prepareForEngineLaunch(): Boolean {
        if (enabled) {
            ensureStartedAndSynced()
            return true
        }
        writePhoneMcpConfig(installer.homeDir, url = null, token = null, register = false)
        return false
    }

    @Synchronized
    private fun ensureStartedAndSynced() {
        val port = mcpServer.start()
        if (port > 0) {
            writePhoneMcpConfig(
                homeDir = installer.homeDir,
                url = mcpServer.url(),
                token = mcpServer.authToken,
                register = true,
            )
        }
    }

    @Synchronized
    fun setEnabled(want: Boolean): Map<String, Any?> {
        enabled = want
        prefs.edit().putBoolean(KEY_ENABLED, want).apply()
        if (want) {
            ensureStartedAndSynced()
        } else {
            safetyGate.emergencyStop()
            mcpServer.stop()
            writePhoneMcpConfig(installer.homeDir, url = null, token = null, register = false)
        }
        RuntimeController.get(appContext).setPhoneControlEnabled(want)
        emitStatus()
        return statusSnapshot()
    }

    @Synchronized
    fun setSafetyMode(rawMode: String?): Map<String, Any?> {
        val parsed = SafetyGate.Mode.parse(rawMode)
        safetyGate.mode = parsed
        prefs.edit().putString(KEY_SAFETY_MODE, parsed.wire).apply()
        emitStatus()
        return statusSnapshot()
    }

    fun resolveApproval(id: String, approved: Boolean): Boolean {
        val ok = safetyGate.resolve(id, approved)
        emitStatus()
        return ok
    }

    @Synchronized
    fun emergencyStop() {
        safetyGate.emergencyStop()
        enabled = false
        prefs.edit().putBoolean(KEY_ENABLED, false).apply()
        mcpServer.stop()
        writePhoneMcpConfig(installer.homeDir, url = null, token = null, register = false)
        RuntimeController.get(appContext).setPhoneControlEnabled(false)
        emitStatus()
    }

    fun getAuditLog(): List<Map<String, Any?>> = synchronized(auditLog) { auditLog.toList() }

    fun refreshStatus(): Map<String, Any?> {
        val snap = statusSnapshot()
        emit(mapOf("type" to "status", "status" to snap))
        return snap
    }

    fun runSelfCheck(callback: (Map<String, Any?>) -> Unit) {
        worker.execute {
            val a11yRunning = AgyAccessibilityService.isRunning()
            val a11yEnabledInSettings = AgyAccessibilityService.isEnabledInSettings(appContext)
            val restricted = AgyAccessibilityService.readRestrictedSettings(appContext)
            val mcpUrl = if (mcpServer.port > 0) mcpServer.url() else null
            val (probeOk, probeDetail) = if (enabled) {
                if (mcpServer.port <= 0) {
                    ensureStartedAndSynced()
                }
                mcpServer.selfProbe()
            } else {
                false to "请先开启「启用 MCP 手机操控」总开关"
            }
            val cfgFile = mcpConfigFile(installer.homeDir)
            val configOk = if (enabled && mcpUrl != null && cfgFile.isFile) {
                try {
                    val root = JSONObject(cfgFile.readText())
                    val phone = root.optJSONObject("mcpServers")?.optJSONObject("phone")
                    phone?.optString("serverUrl") == mcpUrl
                } catch (_: Throwable) {
                    false
                }
            } else {
                false
            }
            val screenCheckOk = if (a11yRunning) {
                try {
                    val tree = AgyAccessibilityService.instance?.readScreenTree(maxNodes = 16)
                    tree != null
                } catch (_: Throwable) {
                    false
                }
            } else {
                false
            }

            val summary = when {
                !enabled -> "手机操控总开关尚未开启"
                !probeOk -> probeDetail
                !configOk -> "MCP 配置文件未同步，请重试开关或重启引擎"
                !a11yRunning && a11yEnabledInSettings -> "无障碍已在系统开启但服务未绑定，请到系统无障碍中关闭再重新打开一次"
                !a11yRunning && (restricted == AgyAccessibilityService.RESTRICTED_GUARDED || restricted == AgyAccessibilityService.RESTRICTED_ACKNOWLEDGED) ->
                    "无障碍未开启：Android 侧载应用需先在「应用信息 › ⋮」允许受限设置"
                !a11yRunning -> "本地 MCP 已就绪，但无障碍服务未开启"
                !mcpServer.clientInitialized -> "无障碍与本地 MCP 均正常；如当前对话仍看不到工具，请点击「重启本机引擎立即接入」或新开对话"
                else -> "全部正常：无障碍已绑定、本地 MCP 通信正常、agy 已接入"
            }

            val report = mapOf(
                "ok" to (enabled && probeOk && configOk && a11yRunning),
                "mcpProbeOk" to probeOk,
                "mcpProbeDetail" to probeDetail,
                "mcpConfigOk" to configOk,
                "mcpConfigPath" to cfgFile.absolutePath,
                "mcpClientConnected" to mcpServer.clientInitialized,
                "accessibilityConnected" to a11yRunning,
                "accessibilityEnabledInSettings" to a11yEnabledInSettings,
                "restrictedSettings" to restricted,
                "screenReadOk" to screenCheckOk,
                "summary" to summary,
            )
            mainHandler.post { callback(report) }
        }
    }

    fun statusSnapshot(): Map<String, Any?> {
        val port = mcpServer.port
        return mapOf(
            "enabled" to enabled,
            "accessibilityConnected" to AgyAccessibilityService.isRunning(),
            "accessibilityEnabledInSettings" to AgyAccessibilityService.isEnabledInSettings(appContext),
            "restrictedSettings" to AgyAccessibilityService.readRestrictedSettings(appContext),
            "safetyMode" to safetyGate.mode.wire,
            "mcpPort" to port,
            "mcpUrl" to if (port > 0) mcpServer.url() else null,
            "mcpToken" to if (port > 0) mcpServer.authToken else null,
            "mcpClientConnected" to mcpServer.clientInitialized,
            "mcpClientName" to mcpServer.lastClientName,
            "mcpConfigPath" to mcpConfigFile(installer.homeDir).absolutePath,
            "pendingApprovals" to safetyGate.pendingPrompts(),
        )
    }

    private fun emitStatus() {
        emit(mapOf("type" to "status", "status" to statusSnapshot()))
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            for (l in listeners) {
                try {
                    l(event)
                } catch (_: Throwable) {}
            }
        }
    }

    companion object {
        private const val PREFS = "agy_phone_control"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_SAFETY_MODE = "safety_mode"

        @Volatile private var instance: PhoneController? = null

        fun get(context: Context): PhoneController =
            instance ?: synchronized(this) {
                instance ?: PhoneController(context.applicationContext).also { instance = it }
            }

        /** Official Antigravity CLI global MCP configuration file (`~/.gemini/config/mcp_config.json`). */
        fun mcpConfigFile(homeDir: File): File = File(homeDir, ".gemini/config/mcp_config.json")

        /**
         * Writes (or removes) the `phone` Streamable HTTP MCP server entry in Antigravity CLI's
         * official `~/.gemini/config/mcp_config.json` using `serverUrl` (official schema; `httpUrl`
         * is unsupported by Antigravity CLI) and removes any legacy stale `phone` entry from
         * `~/.gemini/antigravity-cli/settings.json`.
         */
        fun writePhoneMcpConfig(
            homeDir: File,
            url: String?,
            token: String?,
            register: Boolean,
        ) {
            try {
                val cfgFile = mcpConfigFile(homeDir)
                cfgFile.parentFile?.mkdirs()
                val root = if (cfgFile.isFile) {
                    try {
                        JSONObject(cfgFile.readText())
                    } catch (_: Exception) {
                        JSONObject()
                    }
                } else {
                    JSONObject()
                }
                val servers = root.optJSONObject("mcpServers") ?: JSONObject()
                if (register && !url.isNullOrBlank() && !token.isNullOrBlank()) {
                    val tools = JSONObject()
                    for (name in PhoneMcpServer.TOOL_NAMES) {
                        tools.put(name, JSONObject().put("eager", true))
                    }
                    servers.put(
                        "phone",
                        JSONObject()
                            .put("serverUrl", url)
                            .put("headers", JSONObject().put("Authorization", "Bearer $token"))
                            .put("timeoutSeconds", 600)
                            .put("tools", tools),
                    )
                } else {
                    servers.remove("phone")
                }
                root.put("mcpServers", servers)
                atomicWriteJson(cfgFile, root)
            } catch (_: Throwable) {}

            // Clean any legacy dead `phone` entry written to settings.json by older builds.
            try {
                val legacyFile = AgyAuthHelper.settingsFile(homeDir)
                if (legacyFile.isFile) {
                    val root = JSONObject(legacyFile.readText())
                    val servers = root.optJSONObject("mcpServers")
                    if (servers != null && servers.has("phone")) {
                        servers.remove("phone")
                        root.put("mcpServers", servers)
                        atomicWriteJson(legacyFile, root)
                    }
                }
            } catch (_: Throwable) {}
        }

        private fun atomicWriteJson(target: File, json: JSONObject) {
            target.parentFile?.mkdirs()
            val tmp = File(target.parentFile, ".${target.name}.tmp")
            tmp.writeText(json.toString(2))
            if (!tmp.renameTo(target)) {
                tmp.copyTo(target, overwrite = true)
                tmp.delete()
            }
        }
    }
}
