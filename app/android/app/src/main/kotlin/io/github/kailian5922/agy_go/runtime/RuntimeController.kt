package io.github.kailian5922.agy_go.runtime

import android.content.Context
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.ArrayDeque
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors

/**
 * Single source of truth for the on-device Antigravity CLI lifecycle on Android.
 *
 * Flutter mirrors events emitted here; all process/installer transitions run on a dedicated worker.
 */
class RuntimeController private constructor(private val context: Context) {

    interface EventListener {
        fun onEvent(event: Map<String, Any?>)
    }

    private val installer = AgyInstaller(context)
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "agy-runtime-ctrl") }
    private val listeners = CopyOnWriteArraySet<EventListener>()
    private val logRing = ArrayDeque<String>(MAX_LOG_LINES)
    private val lock = Any()

    @Volatile private var phase: String = "notInstalled"
    @Volatile private var installedVersion: String? = null
    @Volatile private var executionMode: String = "native_bionic"
    @Volatile private var port: Int? = null
    @Volatile private var token: String? = null
    @Volatile private var lastError: String? = null
    @Volatile private var authConfig: AgyAuthHelper.AuthConfig = AgyAuthHelper.AuthConfig()
    @Volatile private var preferProot: Boolean = prefs.getBoolean(K_PREFER_PROOT, false)
    @Volatile private var phoneStorageEnabled: Boolean = prefs.getBoolean(K_PHONE_STORAGE, false)
    @Volatile private var phoneControlEnabled: Boolean = false
    @Volatile private var extraWorkspaceBinds: List<String> = emptyList()
    @Volatile private var process: AgyProcess? = null

    // Interactive OAuth login helper process (`agy acp --login`), if active.
    @Volatile private var loginProcess: Process? = null
    @Volatile private var loginStdin: BufferedWriter? = null

    init {
        installer.ensureDirectories()
        refreshInstalledStateLocked()
        val granted = PhoneStorage.isGranted(context)
        PhoneStorage.syncShortcuts(installer.homeDir, installer.prootRootfsDir, phoneStorageEnabled && granted)
    }

    fun addListener(listener: EventListener) {
        listeners.add(listener)
    }

    fun removeListener(listener: EventListener) {
        listeners.remove(listener)
    }

    fun statusSnapshot(): Map<String, Any?> = synchronized(lock) {
        val storageGranted = PhoneStorage.isGranted(context)
        mapOf(
            "phase" to phase,
            "abi" to installer.primaryAbi(),
            "nativeSupported" to (installer.nativePlatformForDevice() != null),
            "prootAvailable" to installer.isProotAvailable(),
            "preferProot" to preferProot,
            "executionMode" to executionMode,
            "installedVersion" to installedVersion,
            "workspacePath" to installer.workspaceDir.absolutePath,
            "homePath" to installer.homeDir.absolutePath,
            "phoneStorageEnabled" to phoneStorageEnabled,
            "phoneStorageGranted" to storageGranted,
            "phoneStorageMounted" to (phoneStorageEnabled && storageGranted),
            "phoneStoragePath" to PhoneStorage.hostRoot(),
            "port" to port,
            "token" to token,
            "error" to lastError,
            "authMode" to authConfig.mode,
        )
    }

    fun recentLogs(): List<String> = synchronized(logRing) { logRing.toList() }

    fun setAuthConfig(mode: String, apiKey: String, baseUrl: String) {
        synchronized(lock) {
            authConfig = AgyAuthHelper.AuthConfig(mode = mode, apiKey = apiKey, baseUrl = baseUrl)
            AgyAuthHelper.applySettings(installer.homeDir, authConfig)
        }
        emitStatus()
    }

    fun setPreferProot(enabled: Boolean) {
        synchronized(lock) {
            preferProot = enabled
            prefs.edit().putBoolean(K_PREFER_PROOT, enabled).apply()
        }
        emitStatus()
    }

    fun setPhoneStorage(enabled: Boolean) {
        synchronized(lock) {
            phoneStorageEnabled = enabled
            prefs.edit().putBoolean(K_PHONE_STORAGE, enabled).apply()
            val mounted = enabled && PhoneStorage.isGranted(context)
            PhoneStorage.syncShortcuts(installer.homeDir, installer.prootRootfsDir, mounted)
            GuestWorkspaceSetup.writeInstructions(
                homeDir = installer.homeDir,
                workspaceDir = installer.workspaceDir,
                useProot = preferProot && installer.isProotAvailable(),
                phoneStorageMounted = mounted,
                phoneControlEnabled = phoneControlEnabled,
            )
        }
        emitStatus()
    }

    fun setWorkspaceBinds(paths: List<String>) {
        synchronized(lock) {
            extraWorkspaceBinds = paths.filter { it.startsWith("/") }.distinct()
        }
    }

    fun setPhoneControlEnabled(enabled: Boolean) {
        synchronized(lock) {
            phoneControlEnabled = enabled
        }
    }

    fun installOrUpdate() {
        worker.execute {
            synchronized(lock) {
                if (phase == "installing") return@execute
                if (phase == "running" || phase == "starting") {
                    stopLocked()
                }
                phase = "installing"
                lastError = null
            }
            emitStatus()

            try {
                val info = installer.installOrUpdate(
                    object : AgyInstaller.ProgressListener {
                        override fun onProgress(stage: String, fraction: Double, detail: String) {
                            emit(
                                mapOf(
                                    "type" to "progress",
                                    "stage" to stage,
                                    "fraction" to fraction,
                                    "detail" to detail,
                                ),
                            )
                        }

                        override fun onLog(line: String) {
                            appendLog(line, "installer")
                        }
                    },
                )
                synchronized(lock) {
                    installedVersion = info.version
                    phase = "installed"
                    lastError = null
                }
            } catch (e: Throwable) {
                val msg = e.message ?: e.javaClass.simpleName
                appendLog("[installer] failed: $msg", "error")
                synchronized(lock) {
                    refreshInstalledStateLocked()
                    lastError = msg
                    if (installedVersion == null) phase = "error"
                }
            }
            emitStatus()
        }
    }

    fun checkLatestVersion(callback: (Result<Map<String, Any?>>) -> Unit) {
        worker.execute {
            try {
                val platform = installer.nativePlatformForDevice() ?: "linux_arm64"
                val manifest = installer.fetchManifest(platform)
                callback(
                    Result.success(
                        mapOf(
                            "latestVersion" to manifest.version,
                            "installedVersion" to installedVersion,
                            "platform" to manifest.platform,
                            "updateAvailable" to (installedVersion != null && installedVersion != manifest.version),
                        ),
                    ),
                )
            } catch (e: Throwable) {
                callback(Result.failure(e))
            }
        }
    }

    fun start(phoneStorage: Boolean? = null, extraBinds: List<String>? = null) {
        worker.execute {
            val useProot: Boolean
            val currentAuth: AgyAuthHelper.AuthConfig
            val mountStorage: Boolean
            val binds: List<String>
            val phoneCtrl: Boolean
            synchronized(lock) {
                if (phoneStorage != null) {
                    phoneStorageEnabled = phoneStorage
                    prefs.edit().putBoolean(K_PHONE_STORAGE, phoneStorage).apply()
                }
                if (extraBinds != null) {
                    extraWorkspaceBinds = extraBinds.filter { it.startsWith("/") }.distinct()
                }
                if (phase == "running" && process?.isAlive() == true) {
                    emitStatus()
                    return@execute
                }
                if (phase == "installing" || phase == "starting") return@execute
                refreshInstalledStateLocked()
                if (installedVersion == null && !(preferProot && installer.isProotAvailable())) {
                    lastError = "Antigravity CLI is not installed yet."
                    phase = "notInstalled"
                    emitStatus()
                    return@execute
                }
                phase = "starting"
                lastError = null
                port = null
                token = null
                useProot = preferProot && installer.isProotAvailable()
                currentAuth = authConfig
                mountStorage = phoneStorageEnabled && PhoneStorage.isGranted(context)
                binds = extraWorkspaceBinds
                phoneCtrl = phoneControlEnabled
            }
            if (phoneStorageEnabled && !mountStorage) {
                appendLog("[runtime] phone storage requested but permission not granted", "system")
            }
            emitStatus()

            try {
                val proc = AgyProcess(
                    context = context,
                    installer = installer,
                    authConfig = currentAuth,
                    useProot = useProot,
                    phoneStorageMounted = mountStorage,
                    extraWorkspaceBinds = binds,
                    phoneControlEnabled = phoneCtrl,
                    listener = object : AgyProcess.Listener {
                        override fun onLog(line: String, stream: String) {
                            appendLog(line, stream)
                        }

                        override fun onReady(port: Int, token: String, executionMode: String) {
                            synchronized(lock) {
                                this@RuntimeController.port = port
                                this@RuntimeController.token = token
                                this@RuntimeController.executionMode = executionMode
                                phase = "running"
                                lastError = null
                            }
                            AgyService.startForegroundService(
                                context,
                                "Antigravity CLI running ($executionMode · :$port)",
                            )
                            emitStatus()
                        }

                        override fun onOAuthUrl(url: String) {
                            emit(mapOf("type" to "oauthUrl", "url" to url))
                        }

                        override fun onExit(code: Int, expected: Boolean) {
                            appendLog("[runtime] agy exited (code=$code, expected=$expected)", "system")
                            AgyService.stopService(context)
                            synchronized(lock) {
                                process = null
                                port = null
                                token = null
                                if (expected) {
                                    refreshInstalledStateLocked()
                                } else {
                                    phase = "error"
                                    lastError = "agy exited unexpectedly with code $code"
                                }
                            }
                            emitStatus()
                        }
                    },
                )
                synchronized(lock) {
                    process = proc
                }
                proc.start()
            } catch (e: Throwable) {
                val msg = e.message ?: e.javaClass.simpleName
                appendLog("[runtime] start failed: $msg", "error")
                AgyService.stopService(context)
                synchronized(lock) {
                    process = null
                    port = null
                    token = null
                    phase = "error"
                    lastError = msg
                }
                emitStatus()
            }
        }
    }

    fun stop() {
        worker.execute {
            synchronized(lock) {
                stopLocked()
                refreshInstalledStateLocked()
            }
            AgyService.stopService(context)
            emitStatus()
        }
    }

    fun reset(keepHome: Boolean) {
        worker.execute {
            synchronized(lock) {
                stopLocked()
                installer.resetRuntime(keepHome = keepHome)
                refreshInstalledStateLocked()
                lastError = null
            }
            AgyService.stopService(context)
            appendLog("[runtime] reset completed (keepHome=$keepHome)", "system")
            emitStatus()
        }
    }

    /**
     * Runs `agy acp --login` in headless SSH-style URL loop mode so the user can sign in with
     * their Google account via the system browser and paste back the authorization code.
     */
    fun startOAuthLogin() {
        worker.execute {
            val binary = installer.agyBinary
            if (!binary.exists() || !binary.canExecute()) {
                appendLog("[auth] cannot login: agy binary not installed", "error")
                return@execute
            }
            stopLoginProcess()
            try {
                val pb = ProcessBuilder(binary.absolutePath, "acp", "--login").apply {
                    directory(installer.workspaceDir)
                    redirectErrorStream(true)
                    val env = environment()
                    env["HOME"] = installer.homeDir.absolutePath
                    env["SSH_CONNECTION"] = "127.0.0.1 0 127.0.0.1 22"
                    env["NO_BROWSER"] = "1"
                }
                val proc = pb.start()
                loginProcess = proc
                loginStdin = BufferedWriter(OutputStreamWriter(proc.outputStream, Charsets.UTF_8))
                appendLog("[auth] started agy acp --login", "system")

                Thread({
                    try {
                        BufferedReader(InputStreamReader(proc.inputStream, Charsets.UTF_8)).use { reader ->
                            while (true) {
                                val line = reader.readLine() ?: break
                                appendLog(AgyAuthHelper.redactLine(line, authConfig.apiKey), "auth")
                                val match = Regex("https://accounts\\.google\\.com/[^\\s\"'<>]+").find(line)
                                if (match != null) {
                                    emit(mapOf("type" to "oauthUrl", "url" to match.value))
                                }
                            }
                        }
                    } finally {
                        val code = try {
                            proc.waitFor()
                        } catch (_: Exception) {
                            -1
                        }
                        appendLog("[auth] login process finished (code=$code)", "system")
                        emit(mapOf("type" to "oauthDone", "exitCode" to code))
                        stopLoginProcess()
                    }
                }, "agy-oauth-reader").start()
            } catch (e: Throwable) {
                appendLog("[auth] login failed: ${e.message}", "error")
            }
        }
    }

    fun submitOAuthCode(code: String) {
        worker.execute {
            val stdin = loginStdin ?: return@execute
            try {
                stdin.write(code.trim())
                stdin.newLine()
                stdin.flush()
                appendLog("[auth] submitted authorization code", "system")
            } catch (e: Throwable) {
                appendLog("[auth] failed to submit code: ${e.message}", "error")
            }
        }
    }

    fun notifyStorageChanged() {
        synchronized(lock) {
            val mounted = phoneStorageEnabled && PhoneStorage.isGranted(context)
            PhoneStorage.syncShortcuts(installer.homeDir, installer.prootRootfsDir, mounted)
            GuestWorkspaceSetup.writeInstructions(
                homeDir = installer.homeDir,
                workspaceDir = installer.workspaceDir,
                useProot = preferProot && installer.isProotAvailable(),
                phoneStorageMounted = mounted,
                phoneControlEnabled = phoneControlEnabled,
            )
        }
        emitStatus()
    }

    private fun stopLoginProcess() {
        try {
            loginProcess?.destroy()
        } catch (_: Exception) {}
        loginProcess = null
        loginStdin = null
    }

    private fun stopLocked() {
        val current = process
        if (current != null) {
            phase = "stopping"
            current.stop()
            process = null
        }
        port = null
        token = null
    }

    private fun refreshInstalledStateLocked() {
        val info = installer.installedInfo()
        installedVersion = info?.version
        phase = if (info != null) "installed" else "notInstalled"
    }

    private fun appendLog(line: String, stream: String) {
        val formatted = "[$stream] $line"
        synchronized(logRing) {
            if (logRing.size >= MAX_LOG_LINES) logRing.removeFirst()
            logRing.addLast(formatted)
        }
        emit(mapOf("type" to "log", "line" to formatted, "stream" to stream))
    }

    private fun emitStatus() {
        emit(mapOf("type" to "status", "status" to statusSnapshot()))
    }

    private fun emit(event: Map<String, Any?>) {
        for (l in listeners) {
            l.onEvent(event)
        }
    }

    companion object {
        private const val MAX_LOG_LINES = 400
        private const val PREFS_NAME = "agy_runtime_prefs"
        private const val K_PREFER_PROOT = "prefer_proot"
        private const val K_PHONE_STORAGE = "phone_storage"

        @Volatile private var instance: RuntimeController? = null

        fun get(context: Context): RuntimeController =
            instance ?: synchronized(this) {
                instance ?: RuntimeController(context.applicationContext).also { instance = it }
            }
    }
}
