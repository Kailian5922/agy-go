package io.github.kailian5922.agy_go.phone

import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.Executors
import kotlin.concurrent.thread

/**
 * Standard MCP (Model Context Protocol) Streamable HTTP JSON-RPC 2.0 server listening on
 * `http://127.0.0.1:<port>/mcp` with per-session Bearer token authentication.
 *
 * Connected directly to Antigravity CLI (`agy acp`) via ACP `session/new` `mcpServers` or
 * `~/.gemini/antigravity-cli/settings.json` — zero engine binary patching required.
 */
class PhoneMcpServer(
    private val context: Context,
    private val safetyGate: SafetyGate,
    private val isEnabled: () -> Boolean,
    private val onAudit: (tool: String, summary: String, outcome: String) -> Unit,
) {
    val authToken: String = generateToken()
    @Volatile var port: Int = -1
        private set

    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var running = false
    private val pool = Executors.newCachedThreadPool()

    fun url(): String = "http://127.0.0.1:$port/mcp"

    fun start(): Int {
        if (running && port > 0) return port
        val srv = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        serverSocket = srv
        port = srv.localPort
        running = true

        thread(name = "agy-phone-mcp-accept", isDaemon = true) {
            while (running && !srv.isClosed) {
                val client = try {
                    srv.accept()
                } catch (_: Exception) {
                    break
                }
                pool.execute { handleHttp(client) }
            }
        }
        return port
    }

    fun stop() {
        running = false
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null
        port = -1
    }

    private fun handleHttp(socket: Socket) {
        socket.use { sock ->
            sock.soTimeout = 120_000
            val input = BufferedInputStream(sock.getInputStream())
            val output = sock.getOutputStream()

            val headerBytes = readUntilCrlfCrlf(input) ?: return
            val headerText = String(headerBytes, Charsets.ISO_8859_1)
            val lines = headerText.split("\r\n")
            if (lines.isEmpty()) return

            val reqParts = lines[0].split(" ")
            val method = reqParts.getOrNull(0) ?: ""
            val path = reqParts.getOrNull(1) ?: ""

            val headers = mutableMapOf<String, String>()
            for (i in 1 until lines.size) {
                val idx = lines[i].indexOf(':')
                if (idx > 0) {
                    headers[lines[i].substring(0, idx).trim().lowercase()] =
                        lines[i].substring(idx + 1).trim()
                }
            }

            if (headers["authorization"] != "Bearer $authToken") {
                writeHttp(output, 401, "Unauthorized", """{"error":"unauthorized"}""")
                return
            }

            if (method == "GET" && path == "/health") {
                writeHttp(output, 200, "OK", """{"ok":true,"enabled":${isEnabled()}}""")
                return
            }

            if (method != "POST" || !path.startsWith("/mcp")) {
                writeHttp(output, 404, "Not Found", """{"error":"not_found"}""")
                return
            }

            val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
            if (contentLength <= 0 || contentLength > 2 * 1024 * 1024) {
                writeHttp(output, 400, "Bad Request", """{"error":"invalid_content_length"}""")
                return
            }
            val bodyBytes = ByteArray(contentLength)
            var offset = 0
            while (offset < contentLength) {
                val n = input.read(bodyBytes, offset, contentLength - offset)
                if (n < 0) break
                offset += n
            }

            val body = String(bodyBytes, 0, offset, Charsets.UTF_8)
            val reply = handleJsonRpc(body)
            if (reply == null) {
                writeHttp(output, 202, "Accepted", "")
            } else {
                writeHttp(output, 200, "OK", reply.toString())
            }
        }
    }

    private fun handleJsonRpc(raw: String): JSONObject? {
        val req = try {
            JSONObject(raw)
        } catch (e: Exception) {
            return rpcError(JSONObject.NULL, -32700, "Parse error: ${e.message}")
        }

        val hasId = req.has("id") && !req.isNull("id")
        val id = if (hasId) req.get("id") else JSONObject.NULL
        val method = req.optString("method", "")
        val params = req.optJSONObject("params") ?: JSONObject()

        if (!hasId) {
            // Notification such as notifications/initialized.
            return null
        }

        return when (method) {
            "initialize" -> rpcResult(
                id,
                JSONObject().apply {
                    put("protocolVersion", params.optString("protocolVersion", "2024-11-05"))
                    put(
                        "capabilities",
                        JSONObject().put("tools", JSONObject().put("listChanged", false)),
                    )
                    put(
                        "serverInfo",
                        JSONObject().put("name", "agy-go-phone").put("version", "0.1.0"),
                    )
                },
            )
            "ping" -> rpcResult(id, JSONObject())
            "tools/list" -> rpcResult(id, JSONObject().put("tools", toolCatalog()))
            "tools/call" -> rpcResult(id, executeToolCall(params))
            else -> rpcError(id, -32601, "Method not found: $method")
        }
    }

    private fun executeToolCall(params: JSONObject): JSONObject {
        val toolName = params.optString("name", "")
        val args = params.optJSONObject("arguments") ?: JSONObject()

        if (!isEnabled()) {
            onAudit(toolName, "手机操控开关已关闭", "blocked")
            return toolText("Phone control is currently disabled by the user in AGY Go.", isError = true)
        }

        val svc = AgyAccessibilityService.instance
        if (svc == null && toolName != "phone_list_apps" && toolName != "phone_launch_app") {
            onAudit(toolName, "无障碍服务未开启", "error")
            return toolText(
                "AGY Go Accessibility Service is not enabled. Ask the user to enable it in Phone Control settings.",
                isError = true,
            )
        }

        val fgPkg = svc?.foregroundPackage()
        val isMutating = toolName !in setOf("phone_get_screen", "phone_screenshot", "phone_list_apps")
        val summary = describeToolCall(toolName, args)

        val decision = safetyGate.evaluateAndAwait(
            tool = toolName,
            isMutating = isMutating,
            summary = summary,
            foregroundPackage = fgPkg,
        )
        if (!decision.allowed) {
            onAudit(toolName, "$summary (${decision.reason})", "denied")
            return toolText("Action denied by SafetyGate: ${decision.reason}", isError = true)
        }

        return try {
            val out = when (toolName) {
                "phone_get_screen" -> toolText(svc!!.readScreenTree().toString())
                "phone_screenshot" -> {
                    val b64 = svc!!.captureScreenshotJpegBase64()
                    if (b64 == null) {
                        toolText("Screenshot requires Android 11+ (API 30) and Accessibility permission.", isError = true)
                    } else {
                        JSONObject().apply {
                            put(
                                "content",
                                JSONArray().put(
                                    JSONObject()
                                        .put("type", "image")
                                        .put("data", b64)
                                        .put("mimeType", "image/jpeg"),
                                ),
                            )
                            put("isError", false)
                        }
                    }
                }
                "phone_tap" -> {
                    val x = args.getDouble("x").toFloat()
                    val y = args.getDouble("y").toFloat()
                    val dur = args.optLong("durationMs", 60L)
                    val ok = svc!!.tap(x, y, dur)
                    toolText(if (ok) "Tapped ($x, $y)." else "Tap gesture failed.", isError = !ok)
                }
                "phone_swipe" -> {
                    val x1 = args.getDouble("x1").toFloat()
                    val y1 = args.getDouble("y1").toFloat()
                    val x2 = args.getDouble("x2").toFloat()
                    val y2 = args.getDouble("y2").toFloat()
                    val dur = args.optLong("durationMs", 320L)
                    val ok = svc!!.swipe(x1, y1, x2, y2, dur)
                    toolText(if (ok) "Swiped ($x1,$y1)->($x2,$y2)." else "Swipe failed.", isError = !ok)
                }
                "phone_input_text" -> {
                    val text = args.optString("text", "")
                    val ok = svc!!.inputText(text)
                    toolText(if (ok) "Entered text (${text.length} chars)." else "No focused editable input field found.", isError = !ok)
                }
                "phone_press_key" -> {
                    val key = args.optString("key", "back")
                    val ok = svc!!.pressGlobal(key)
                    toolText(if (ok) "Pressed global key '$key'." else "Unsupported or failed key '$key'.", isError = !ok)
                }
                "phone_launch_app" -> {
                    val pkg = args.optString("packageName", "").trim()
                    val intent = context.packageManager.getLaunchIntentForPackage(pkg)
                    if (intent == null) {
                        toolText("App package '$pkg' not found or not launchable.", isError = true)
                    } else {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        toolText("Launched $pkg.")
                    }
                }
                "phone_list_apps" -> {
                    val pm = context.packageManager
                    val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                    val apps = pm.queryIntentActivities(query, 0)
                    val arr = JSONArray()
                    for (ri in apps.take(150)) {
                        arr.put(
                            JSONObject()
                                .put("packageName", ri.activityInfo.packageName)
                                .put("label", ri.loadLabel(pm).toString()),
                        )
                    }
                    toolText(arr.toString())
                }
                else -> toolText("Unknown phone tool: $toolName", isError = true)
            }
            onAudit(toolName, summary, if (out.optBoolean("isError")) "failed" else "ok")
            out
        } catch (e: Throwable) {
            onAudit(toolName, "$summary (${e.message})", "error")
            toolText("Phone tool error: ${e.message}", isError = true)
        }
    }

    private fun describeToolCall(name: String, args: JSONObject): String = when (name) {
        "phone_get_screen" -> "读取当前屏幕元素树"
        "phone_screenshot" -> "截取当前屏幕图像"
        "phone_tap" -> "点击屏幕 (${args.optInt("x")}, ${args.optInt("y")})"
        "phone_swipe" -> "滑动 (${args.optInt("x1")},${args.optInt("y1")}) -> (${args.optInt("x2")},${args.optInt("y2")})"
        "phone_input_text" -> "在输入框键入「${args.optString("text").take(24)}」"
        "phone_press_key" -> "按下系统键 ${args.optString("key")}"
        "phone_launch_app" -> "打开应用 ${args.optString("packageName")}"
        "phone_list_apps" -> "列出已安装应用"
        else -> name
    }

    private fun toolCatalog(): JSONArray = JSONArray().apply {
        put(toolDef("phone_get_screen", "Read the active Android app package and interactive UI element tree with coordinates.", JSONObject()))
        put(toolDef("phone_screenshot", "Capture a JPEG screenshot of the current Android screen (Android 11+).", JSONObject()))
        put(
            toolDef(
                "phone_tap",
                "Tap the screen at pixel coordinates (x, y).",
                JSONObject()
                    .put("x", JSONObject().put("type", "number"))
                    .put("y", JSONObject().put("type", "number"))
                    .put("durationMs", JSONObject().put("type", "integer")),
                listOf("x", "y"),
            ),
        )
        put(
            toolDef(
                "phone_swipe",
                "Swipe from (x1, y1) to (x2, y2).",
                JSONObject()
                    .put("x1", JSONObject().put("type", "number"))
                    .put("y1", JSONObject().put("type", "number"))
                    .put("x2", JSONObject().put("type", "number"))
                    .put("y2", JSONObject().put("type", "number"))
                    .put("durationMs", JSONObject().put("type", "integer")),
                listOf("x1", "y1", "x2", "y2"),
            ),
        )
        put(
            toolDef(
                "phone_input_text",
                "Set text into the currently focused editable field.",
                JSONObject().put("text", JSONObject().put("type", "string")),
                listOf("text"),
            ),
        )
        put(
            toolDef(
                "phone_press_key",
                "Trigger a global Android navigation key: back, home, recents, notifications.",
                JSONObject().put("key", JSONObject().put("type", "string")),
                listOf("key"),
            ),
        )
        put(
            toolDef(
                "phone_launch_app",
                "Launch an installed Android app by packageName.",
                JSONObject().put("packageName", JSONObject().put("type", "string")),
                listOf("packageName"),
            ),
        )
        put(toolDef("phone_list_apps", "List installed launchable Android apps and their package names.", JSONObject()))
    }

    private fun toolDef(
        name: String,
        description: String,
        properties: JSONObject,
        required: List<String> = emptyList(),
    ): JSONObject = JSONObject().apply {
        put("name", name)
        put("description", description)
        put(
            "inputSchema",
            JSONObject()
                .put("type", "object")
                .put("properties", properties)
                .put("required", JSONArray(required)),
        )
    }

    private fun toolText(text: String, isError: Boolean = false): JSONObject = JSONObject().apply {
        put(
            "content",
            JSONArray().put(JSONObject().put("type", "text").put("text", text)),
        )
        put("isError", isError)
    }

    private fun rpcResult(id: Any, result: JSONObject): JSONObject = JSONObject().apply {
        put("jsonrpc", "2.0")
        put("id", id)
        put("result", result)
    }

    private fun rpcError(id: Any, code: Int, message: String): JSONObject = JSONObject().apply {
        put("jsonrpc", "2.0")
        put("id", id)
        put("error", JSONObject().put("code", code).put("message", message))
    }

    private fun readUntilCrlfCrlf(input: BufferedInputStream): ByteArray? {
        val baos = ByteArrayOutputStream()
        var state = 0
        while (baos.size() < 32 * 1024) {
            val b = input.read()
            if (b < 0) return null
            baos.write(b)
            state = when (state) {
                0 -> if (b == '\r'.code) 1 else 0
                1 -> if (b == '\n'.code) 2 else 0
                2 -> if (b == '\r'.code) 3 else 0
                3 -> if (b == '\n'.code) return baos.toByteArray() else 0
                else -> 0
            }
        }
        return null
    }

    private fun writeHttp(output: java.io.OutputStream, status: Int, reason: String, body: String) {
        val bytes = body.toByteArray(Charsets.UTF_8)
        val headers = "HTTP/1.1 $status $reason\r\n" +
            "Content-Type: application/json; charset=utf-8\r\n" +
            "Content-Length: ${bytes.size}\r\n" +
            "Connection: close\r\n\r\n"
        output.write(headers.toByteArray(Charsets.ISO_8859_1))
        if (bytes.isNotEmpty()) output.write(bytes)
        output.flush()
    }

    companion object {
        private fun generateToken(): String {
            val bytes = ByteArray(24)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
