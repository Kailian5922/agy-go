package io.github.kailian5922.agy_go.runtime

import android.content.Context
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.ArrayDeque
import kotlin.concurrent.thread

/**
 * Spawns the on-device `agy acp` process (Native Android Bionic by default, or optional PRoot Linux)
 * and bridges its stdin/stdout NDJSON stream to a token-authenticated loopback TCP socket.
 *
 * Workspace & phone storage mounting mirrors DSH Go:
 * - Native Bionic mode: `HOME` is `filesDir/runtime/home`, default workspace is `HOME/workspace`,
 *   and when phone storage is enabled & granted, `HOME/手机存储 -> /storage/emulated/0` is synced
 *   and `agy` can directly operate on any workspace path passed via ACP `cwd`.
 * - PRoot Linux mode: passes `-b /storage/emulated/0:/sdcard -b /storage` plus extra registered
 *   workspace binds before `/usr/bin/env`, and syncs `/root/手机存储 -> /sdcard`.
 */
class AgyProcess(
    private val context: Context,
    private val installer: AgyInstaller,
    private val authConfig: AgyAuthHelper.AuthConfig,
    private val executionPolicy: AgyAuthHelper.ExecutionPolicy,
    private val useProot: Boolean,
    private val phoneStorageMounted: Boolean,
    private val extraWorkspaceBinds: List<String>,
    private val phoneControlEnabled: Boolean,
    private val initialWorkingDir: String? = null,
    private val listener: Listener,
) {
    interface Listener {
        fun onLog(line: String, stream: String)
        fun onReady(port: Int, token: String, executionMode: String)
        fun onOAuthUrl(url: String)
        fun onExit(code: Int, expected: Boolean)
    }

    @Volatile private var process: Process? = null
    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var activeClient: Socket? = null
    @Volatile private var activeClientWriter: BufferedWriter? = null
    @Volatile private var processStdin: BufferedWriter? = null
    @Volatile private var stopping = false

    val sessionToken: String = generateToken()
    var listenPort: Int = -1
        private set
    var executionMode: String = if (useProot) "proot" else "native_bionic"
        private set

    private val clientLock = Any()
    private val pendingFrames = ArrayDeque<String>()

    fun start() {
        installer.ensureDirectories()
        AgyAuthHelper.applySettings(installer.homeDir, authConfig, executionPolicy)
        PhoneStorage.syncShortcuts(installer.homeDir, installer.prootRootfsDir, phoneStorageMounted)
        GuestWorkspaceSetup.writeInstructions(
            homeDir = installer.homeDir,
            workspaceDir = installer.workspaceDir,
            useProot = useProot && installer.isProotAvailable(),
            phoneStorageMounted = phoneStorageMounted,
            phoneControlEnabled = phoneControlEnabled,
        )

        val acpLogFile = File(installer.homeDir, ACP_LOG_REL_PATH).apply {
            parentFile?.mkdirs()
            runCatching { writeText("") }
        }

        val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
        serverSocket = server
        listenPort = server.localPort

        val requestedDir = initialWorkingDir?.trim()?.takeIf { it.startsWith("/") }?.let(::File)
        val startDir = if (requestedDir != null && requestedDir.isDirectory) {
            requestedDir
        } else {
            installer.workspaceDir
        }

        val cmd = buildCommand(acpLogFile)
        val pb = ProcessBuilder(cmd).apply {
            directory(startDir)
            val env = environment()
            env["HOME"] = installer.homeDir.absolutePath
            env["USER"] = "agy"
            env["SHELL"] = if (executionMode == "proot") "/bin/sh" else "/system/bin/sh"
            env["TMPDIR"] = File(context.cacheDir, "tmp").apply { mkdirs() }.absolutePath
            env["XDG_CONFIG_HOME"] = File(installer.homeDir, ".config").absolutePath
            env["XDG_CACHE_HOME"] = File(installer.homeDir, ".cache").absolutePath
            env["XDG_DATA_HOME"] = File(installer.homeDir, ".local/share").absolutePath
            env["TERM"] = "xterm-256color"
            env["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
            val loopbackBypass = mergeNoProxy(env["NO_PROXY"] ?: env["no_proxy"])
            env["NO_PROXY"] = loopbackBypass
            env["no_proxy"] = loopbackBypass
            if (phoneStorageMounted) {
                env["AGY_PHONE_STORAGE"] = if (executionMode == "proot") PhoneStorage.GUEST_PATH else PhoneStorage.hostRoot()
            }
            val currentPath = env["PATH"] ?: "/system/bin:/system/xbin"
            env["PATH"] = "${installer.binDir.absolutePath}:$currentPath"
            if (executionMode == "proot") {
                env["PROOT_TMP_DIR"] = File(context.cacheDir, "proot-tmp").apply { mkdirs() }.absolutePath
                env["LD_LIBRARY_PATH"] = context.applicationInfo.nativeLibraryDir
            }
            for ((k, v) in AgyAuthHelper.environmentOverrides(authConfig)) {
                env[k] = v
            }
        }

        listener.onLog(
            "[runtime] launching ($executionMode, cwd=${startDir.absolutePath}, storage=${if (phoneStorageMounted) "mounted" else "isolated"}, policy=${executionPolicy.toolPermission}): ${cmd.joinToString(" ")}",
            "system",
        )
        val proc = pb.start()
        process = proc
        processStdin = BufferedWriter(OutputStreamWriter(proc.outputStream, Charsets.UTF_8))

        // Pump agy acp stdout (JSON-RPC frames) -> currently attached Flutter loopback client.
        thread(name = "agy-stdout", isDaemon = true) {
            try {
                BufferedReader(InputStreamReader(proc.inputStream, Charsets.UTF_8)).use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        val trimmed = line.trim()
                        if (trimmed.isEmpty()) continue
                        detectOAuthUrl(trimmed)
                        if (trimmed.startsWith("{")) {
                            forwardToClient(trimmed)
                        } else {
                            listener.onLog(AgyAuthHelper.redactLine(line, authConfig.apiKey), "stdout")
                        }
                    }
                }
            } catch (e: Exception) {
                if (!stopping) {
                    listener.onLog("[runtime] stdout pump ended: ${e.message}", "system")
                }
            }
        }

        // Pump agy acp stderr -> redacted logs + OAuth URL detection.
        thread(name = "agy-stderr", isDaemon = true) {
            try {
                BufferedReader(InputStreamReader(proc.errorStream, Charsets.UTF_8)).use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        detectOAuthUrl(line)
                        listener.onLog(AgyAuthHelper.redactLine(line, authConfig.apiKey), "stderr")
                    }
                }
            } catch (e: Exception) {
                if (!stopping) {
                    listener.onLog("[runtime] stderr pump ended: ${e.message}", "system")
                }
            }
        }

        // Tail `agy acp --log-file`: `agy acp` redirects its internal diagnostic logs
        // away from stderr so retries (429/503/network reset), compaction, and trajectory
        // state transitions are only visible via the log file.
        thread(name = "agy-log-tailer", isDaemon = true) {
            tailAcpLogFile(acpLogFile, proc)
        }

        // Accept loopback TCP connections from Flutter with token verification.
        thread(name = "agy-bridge-accept", isDaemon = true) {
            while (!stopping && !server.isClosed) {
                val client = try {
                    server.accept()
                } catch (_: Exception) {
                    break
                }
                handleClientConnection(client)
            }
        }

        // Wait for child process exit.
        thread(name = "agy-waiter", isDaemon = true) {
            val code = try {
                proc.waitFor()
            } catch (_: InterruptedException) {
                -1
            }
            val expected = stopping
            cleanupResources()
            listener.onExit(code, expected)
        }

        listener.onReady(listenPort, sessionToken, executionMode)
    }

    fun isAlive(): Boolean = process?.isAlive == true

    fun stop() {
        stopping = true
        cleanupResources()
    }

    private fun buildAcpArgs(logFilePath: String): List<String> {
        // Never pass global `--add-dir` here: each ACP conversation specifies its own `cwd`
        // (and optional per-session additionalDirectories via `/add-dir`), keeping workspaces isolated.
        val args = ArrayList<String>()
        args.add("acp")
        args.add("--log-file")
        args.add(logFilePath)
        if (executionPolicy.skipPermissions) {
            args.add("--dangerously-skip-permissions")
        }
        return args
    }

    private fun buildCommand(acpLogFile: File): List<String> {
        if (useProot && installer.isProotAvailable()) {
            executionMode = "proot"
            val proot = File(context.applicationInfo.nativeLibraryDir, "libproot.so").absolutePath
            val cmd = ArrayList<String>().apply {
                add(proot)
                add("-r"); add(installer.prootRootfsDir.absolutePath)
                add("-0")
                add("-w"); add("/root/workspace")
                add("-b"); add("/dev")
                add("-b"); add("/proc")
                add("-b"); add("/sys")
                add("-b"); add("${installer.homeDir.absolutePath}:/root")
                for (bind in PhoneStorage.prootBinds(phoneStorageMounted, extraWorkspaceBinds)) {
                    add("-b"); add(bind)
                }
                add("/usr/bin/env")
                add("HOME=/root")
                add("SHELL=/bin/sh")
                add("AGY_CLI_DISABLE_AUTO_UPDATE=true")
                add("NO_PROXY=127.0.0.1,localhost,::1")
                add("no_proxy=127.0.0.1,localhost,::1")
                add("PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin")
                if (phoneStorageMounted) {
                    add("AGY_PHONE_STORAGE=${PhoneStorage.GUEST_PATH}")
                }
                add("/root/.local/bin/agy")
                addAll(buildAcpArgs("/root/$ACP_LOG_REL_PATH"))
            }
            return cmd
        }
        executionMode = "native_bionic"
        return buildList {
            add(installer.agyBinary.absolutePath)
            addAll(buildAcpArgs(acpLogFile.absolutePath))
        }
    }

    private fun handleClientConnection(socket: Socket) {
        thread(name = "agy-client-reader", isDaemon = true) {
            try {
                socket.tcpNoDelay = true
                val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
                val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))

                val firstLine = reader.readLine()
                val authed = try {
                    firstLine != null && JSONObject(firstLine).optString("auth") == sessionToken
                } catch (_: Exception) {
                    false
                }

                if (!authed) {
                    writer.write("{\"ok\":false,\"error\":\"unauthorized\"}\n")
                    writer.flush()
                    socket.close()
                    return@thread
                }

                writer.write("{\"ok\":true}\n")
                writer.flush()

                synchronized(clientLock) {
                    try {
                        activeClient?.close()
                    } catch (_: Exception) {}
                    activeClient = socket
                    activeClientWriter = writer
                    // Flush any stdout frames buffered during a brief loopback reconnect.
                    while (pendingFrames.isNotEmpty()) {
                        val queued = pendingFrames.peekFirst() ?: break
                        writer.write(queued)
                        writer.newLine()
                        writer.flush()
                        pendingFrames.removeFirst()
                    }
                }
                listener.onLog("[bridge] Flutter client attached on 127.0.0.1:$listenPort", "system")

                while (!stopping) {
                    val frame = reader.readLine() ?: break
                    val stdin = processStdin ?: break
                    synchronized(stdin) {
                        stdin.write(frame)
                        stdin.newLine()
                        stdin.flush()
                    }
                }
            } catch (_: Exception) {
                // Client detached; keep agy process alive so Flutter can reattach.
            } finally {
                synchronized(clientLock) {
                    if (activeClient === socket) {
                        activeClient = null
                        activeClientWriter = null
                    }
                }
                try {
                    socket.close()
                } catch (_: Exception) {}
            }
        }
    }

    private fun enqueuePendingFrameLocked(line: String) {
        if (pendingFrames.size >= MAX_PENDING_FRAMES) {
            pendingFrames.removeFirst()
        }
        pendingFrames.addLast(line)
    }

    private fun forwardToClient(line: String) {
        synchronized(clientLock) {
            val writer = activeClientWriter
            if (writer == null) {
                enqueuePendingFrameLocked(line)
                return
            }
            try {
                writer.write(line)
                writer.newLine()
                writer.flush()
            } catch (_: Exception) {
                try {
                    activeClient?.close()
                } catch (_: Exception) {}
                activeClient = null
                activeClientWriter = null
                enqueuePendingFrameLocked(line)
            }
        }
    }

    private fun tailAcpLogFile(logFile: File, proc: Process) {
        var offset = 0L
        val lineBuf = ByteArrayOutputStream(512)
        var lineTruncated = false
        while (!stopping && proc.isAlive) {
            try {
                if (logFile.exists()) {
                    val fileLen = logFile.length()
                    if (fileLen < offset) {
                        offset = 0L
                        lineBuf.reset()
                        lineTruncated = false
                    }
                    if (fileLen > offset) {
                        RandomAccessFile(logFile, "r").use { raf ->
                            raf.seek(offset)
                            var remaining = fileLen - offset
                            while (remaining > 0L && !stopping) {
                                val chunkSize = remaining.coerceAtMost(32768L).toInt()
                                val buf = ByteArray(chunkSize)
                                val read = raf.read(buf)
                                if (read <= 0) break
                                offset += read
                                remaining -= read
                                for (i in 0 until read) {
                                    val b = buf[i]
                                    if (b == '\n'.code.toByte()) {
                                        val raw = String(lineBuf.toByteArray(), Charsets.UTF_8)
                                            .trimEnd('\r')
                                        lineBuf.reset()
                                        lineTruncated = false
                                        handleAcpLogLine(raw)
                                    } else if (!lineTruncated) {
                                        if (lineBuf.size() < MAX_LOG_LINE_BYTES) {
                                            lineBuf.write(b.toInt())
                                        } else {
                                            lineTruncated = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                // File may be mid-rotation or temporarily unreadable; retry next tick.
            }
            try {
                Thread.sleep(LOG_TAIL_POLL_MS)
            } catch (_: InterruptedException) {
                break
            }
        }
    }

    private fun handleAcpLogLine(rawLine: String) {
        val trimmed = rawLine.trim()
        if (trimmed.isEmpty()) return
        detectOAuthUrl(trimmed)
        if (!shouldForwardAcpLog(trimmed)) return
        listener.onLog(AgyAuthHelper.redactLine(trimmed, authConfig.apiKey), "acp")
    }

    private fun detectOAuthUrl(line: String) {
        val match = OAUTH_URL_REGEX.find(line) ?: return
        listener.onOAuthUrl(match.value)
    }

    private fun cleanupResources() {
        synchronized(clientLock) {
            try {
                activeClient?.close()
            } catch (_: Exception) {}
            activeClient = null
            activeClientWriter = null
            pendingFrames.clear()
        }
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null

        val proc = process
        if (proc != null && proc.isAlive) {
            proc.destroy()
            try {
                if (!proc.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)) {
                    proc.destroyForcibly()
                }
            } catch (_: Exception) {
                proc.destroyForcibly()
            }
        }
        process = null
        processStdin = null
    }

    companion object {
        private const val ACP_LOG_REL_PATH = ".cache/agy-acp-live.log"
        private const val MAX_PENDING_FRAMES = 512
        private const val MAX_LOG_LINE_BYTES = 16384
        private const val LOG_TAIL_POLL_MS = 350L
        private val OAUTH_URL_REGEX = Regex("https://accounts\\.google\\.com/[^\\s\"'<>]+")

        internal fun shouldForwardAcpLog(line: String): Boolean {
            val lower = line.lowercase()
            return lower.contains("retry") ||
                lower.contains("backoff") ||
                lower.contains("reconnect") ||
                lower.contains("429") ||
                lower.contains("rate limit") ||
                lower.contains("rate_limit") ||
                lower.contains("resource_exhausted") ||
                lower.contains("quota") ||
                lower.contains("502") ||
                lower.contains("503") ||
                lower.contains("504") ||
                lower.contains("overloaded") ||
                lower.contains("unavailable") ||
                lower.contains("connection reset") ||
                lower.contains("broken pipe") ||
                lower.contains("unexpected eof") ||
                lower.contains("timeout") ||
                lower.contains("deadline") ||
                lower.contains("stream error") ||
                lower.contains("stream interrupted") ||
                lower.contains("compaction") ||
                lower.contains("compacting") ||
                lower.contains("trajectorystateupdate") ||
                lower.contains("state_waiting_for_tasks") ||
                lower.contains("state_fully_idle") ||
                lower.contains("error") ||
                lower.contains("warn") ||
                lower.contains("fatal")
        }

        fun mergeNoProxy(existing: String?): String {
            val parts = LinkedHashSet<String>()
            if (!existing.isNullOrBlank()) {
                for (entry in existing.split(',')) {
                    val trimmed = entry.trim()
                    if (trimmed.isNotEmpty()) parts.add(trimmed)
                }
            }
            parts.add("127.0.0.1")
            parts.add("localhost")
            parts.add("::1")
            return parts.joinToString(",")
        }

        private fun generateToken(): String {
            val bytes = ByteArray(24)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
