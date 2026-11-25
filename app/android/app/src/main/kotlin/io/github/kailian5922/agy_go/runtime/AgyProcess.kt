package io.github.kailian5922.agy_go.runtime

import android.content.Context
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import kotlin.concurrent.thread

/**
 * Spawns the on-device `agy acp` process (Native Android Bionic by default, or optional PRoot Linux)
 * and bridges its stdin/stdout NDJSON stream to a token-authenticated loopback TCP socket.
 *
 * Keeping the child process owned by Android's ForegroundService + loopback bridge means
 * Flutter Activity recreations or backgrounding do not break an active `agy` turn.
 */
class AgyProcess(
    private val context: Context,
    private val installer: AgyInstaller,
    private val authConfig: AgyAuthHelper.AuthConfig,
    private val useProot: Boolean,
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

    fun start() {
        installer.ensureDirectories()
        AgyAuthHelper.applySettings(installer.homeDir, authConfig)

        val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
        serverSocket = server
        listenPort = server.localPort

        val cmd = buildCommand()
        val pb = ProcessBuilder(cmd).apply {
            directory(installer.workspaceDir)
            val env = environment()
            env["HOME"] = installer.homeDir.absolutePath
            env["USER"] = "agy"
            env["TMPDIR"] = File(context.cacheDir, "tmp").absolutePath
            env["XDG_CONFIG_HOME"] = File(installer.homeDir, ".config").absolutePath
            env["XDG_CACHE_HOME"] = File(installer.homeDir, ".cache").absolutePath
            env["XDG_DATA_HOME"] = File(installer.homeDir, ".local/share").absolutePath
            env["TERM"] = "xterm-256color"
            val currentPath = env["PATH"] ?: "/system/bin:/system/xbin"
            env["PATH"] = "${installer.binDir.absolutePath}:$currentPath"
            if (useProot) {
                env["PROOT_TMP_DIR"] = File(context.cacheDir, "proot-tmp").apply { mkdirs() }.absolutePath
                env["LD_LIBRARY_PATH"] = context.applicationInfo.nativeLibraryDir
            }
            for ((k, v) in AgyAuthHelper.environmentOverrides(authConfig)) {
                env[k] = v
            }
        }

        listener.onLog("[runtime] launching ($executionMode): ${cmd.joinToString(" ")}", "system")
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

    private fun buildCommand(): List<String> {
        if (useProot && installer.isProotAvailable()) {
            executionMode = "proot"
            val proot = File(context.applicationInfo.nativeLibraryDir, "libproot.so").absolutePath
            return listOf(
                proot,
                "-r", installer.prootRootfsDir.absolutePath,
                "-0",
                "-w", "/root/workspace",
                "-b", "/dev",
                "-b", "/proc",
                "-b", "/sys",
                "-b", "${installer.homeDir.absolutePath}:/root",
                "/usr/bin/env", "HOME=/root", "PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin",
                "/root/.local/bin/agy", "acp",
            )
        }
        executionMode = "native_bionic"
        return listOf(installer.agyBinary.absolutePath, "acp")
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

    private fun forwardToClient(line: String) {
        synchronized(clientLock) {
            val writer = activeClientWriter ?: return
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
            }
        }
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
        private val OAUTH_URL_REGEX = Regex("https://accounts\\.google\\.com/[^\\s\"'<>]+")

        private fun generateToken(): String {
            val bytes = ByteArray(24)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
