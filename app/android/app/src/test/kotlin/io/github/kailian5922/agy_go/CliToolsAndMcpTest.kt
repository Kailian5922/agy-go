package io.github.kailian5922.agy_go

import android.app.AppOpsManager
import android.content.ContextWrapper
import io.github.kailian5922.agy_go.pet.FloatingAskPlace
import io.github.kailian5922.agy_go.phone.AgyAccessibilityService
import io.github.kailian5922.agy_go.phone.PhoneController
import io.github.kailian5922.agy_go.phone.PhoneMcpServer
import io.github.kailian5922.agy_go.phone.SafetyGate
import io.github.kailian5922.agy_go.runtime.AgyAuthHelper
import io.github.kailian5922.agy_go.runtime.AgyInstaller
import io.github.kailian5922.agy_go.runtime.AgyProcess
import io.github.kailian5922.agy_go.runtime.GuestWorkspaceSetup
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.Socket
import java.nio.file.Files

class CliToolsAndMcpTest {

    private data class HttpReply(
        val statusLine: String,
        val headers: Map<String, String>,
        val body: String,
    )

    private fun sendRawHttp(port: Int, rawRequest: String): HttpReply {
        Socket("127.0.0.1", port).use { sock ->
            sock.soTimeout = 5_000
            val out = sock.getOutputStream()
            out.write(rawRequest.toByteArray(Charsets.UTF_8))
            out.flush()

            val input = BufferedInputStream(sock.getInputStream())
            val all = ByteArrayOutputStream()
            val buf = ByteArray(4096)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                all.write(buf, 0, n)
            }
            val text = String(all.toByteArray(), Charsets.UTF_8)
            val split = text.indexOf("\r\n\r\n")
            val head = if (split >= 0) text.substring(0, split) else text
            val body = if (split >= 0) text.substring(split + 4) else ""
            val lines = head.split("\r\n")
            val headerMap = mutableMapOf<String, String>()
            for (i in 1 until lines.size) {
                val idx = lines[i].indexOf(':')
                if (idx > 0) {
                    headerMap[lines[i].substring(0, idx).trim().lowercase()] =
                        lines[i].substring(idx + 1).trim()
                }
            }
            return HttpReply(lines.firstOrNull().orEmpty(), headerMap, body)
        }
    }

    @Test
    fun phoneMcpServerHandlesContentLengthChunkedStreamableHttpAndUtf8() {
        val gate = SafetyGate { }
        val server = PhoneMcpServer(
            context = ContextWrapper(null),
            safetyGate = gate,
            isEnabled = { true },
            onAudit = { _, _, _ -> },
        )
        val port = server.start()
        try {
            // 1. Unauthorized fails closed with 401.
            val unauth = sendRawHttp(
                port,
                "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer wrong\r\n\r\n",
            )
            assertTrue(unauth.statusLine.contains("401"))

            // 2. Authorized /health returns 200.
            val health = sendRawHttp(
                port,
                "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n\r\n",
            )
            assertTrue(health.statusLine.contains("200"))
            assertTrue(JSONObject(health.body).getBoolean("ok"))

            // 3. MCP Streamable HTTP: GET /mcp returns 405 (not 404), DELETE /mcp returns 200.
            val getMcp = sendRawHttp(
                port,
                "GET /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n\r\n",
            )
            assertTrue(getMcp.statusLine.contains("405"))
            assertTrue(getMcp.headers["allow"].orEmpty().contains("POST"))

            val delMcp = sendRawHttp(
                port,
                "DELETE /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n\r\n",
            )
            assertTrue(delMcp.statusLine.contains("200"))

            // 4. POST /mcp with Content-Length: initialize handshake.
            val initBody = """{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"""
            val initBytes = initBody.toByteArray(Charsets.UTF_8)
            val initReply = sendRawHttp(
                port,
                "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n" +
                    "Content-Type: application/json\r\nContent-Length: ${initBytes.size}\r\n\r\n$initBody",
            )
            assertTrue(initReply.statusLine.contains("200"))
            val initJson = JSONObject(initReply.body).getJSONObject("result")
            assertEquals("2025-03-26", initJson.getString("protocolVersion"))
            assertEquals("agy-go-phone", initJson.getJSONObject("serverInfo").getString("name"))

            // 5. POST /mcp notification (no id) -> 202 Accepted.
            val notifBody = """{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"""
            val notifReply = sendRawHttp(
                port,
                "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n" +
                    "Content-Length: ${notifBody.toByteArray(Charsets.UTF_8).size}\r\n\r\n$notifBody",
            )
            assertTrue(notifReply.statusLine.contains("202"))

            // 6. POST /mcp with Transfer-Encoding: chunked -> tools/list returns all 8 phone tools!
            val part1 = """{"jsonrpc":"2.0","id":2,"""
            val part2 = """"method":"tools/list","params":{"note":"中文测试"}}"""
            val b1 = part1.toByteArray(Charsets.UTF_8)
            val b2 = part2.toByteArray(Charsets.UTF_8)
            val chunkedReq = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n" +
                "Content-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n" +
                "${b1.size.toString(16)}\r\n$part1\r\n" +
                "${b2.size.toString(16)}\r\n$part2\r\n" +
                "0\r\n\r\n"
            val listReply = sendRawHttp(port, chunkedReq)
            assertTrue(listReply.statusLine.contains("200"))
            val tools = JSONObject(listReply.body).getJSONObject("result").getJSONArray("tools")
            assertEquals(8, tools.length())
            assertEquals("phone_get_screen", tools.getJSONObject(0).getString("name"))
        } finally {
            server.stop()
        }
    }

    @Test
    fun guestWorkspaceSetupDocumentsAndroidBionicToolsAndPhoneMcp() {
        val tmpHome = Files.createTempDirectory("agy-home-test").toFile()
        val tmpWs = File(tmpHome, "workspace").apply { mkdirs() }
        try {
            GuestWorkspaceSetup.writeInstructions(
                homeDir = tmpHome,
                workspaceDir = tmpWs,
                useProot = false,
                phoneStorageMounted = true,
                phoneControlEnabled = true,
            )
            val geminiMd = File(tmpHome, ".gemini/GEMINI.md").readText()
            val agentsMd = File(tmpHome, "AGENTS.md").readText()
            assertEquals(geminiMd, agentsMd)
            assertTrue(geminiMd.contains("/system/bin/sh"))
            assertTrue(geminiMd.contains("bash"))
            assertTrue(geminiMd.contains("toybox"))
            assertTrue(geminiMd.contains("工作区隔离规则"))
            assertFalse(geminiMd.contains("默认工作区目录"))
            assertTrue(geminiMd.contains("手机操控（MCP `phone`）"))
        } finally {
            tmpHome.deleteRecursively()
        }
    }

    @Test
    fun bashShimTranslatesFlagsPreservesQuotingAndPropagatesExitCode() {
        val tmpBin = Files.createTempDirectory("agy-bin-test").toFile()
        try {
            val shim = AgyInstaller.writeBashShim(tmpBin)
            assertTrue(shim.isFile)
            assertTrue(shim.canExecute())
            val scriptText = shim.readText(Charsets.UTF_8)
            assertTrue(scriptText.startsWith("#!/system/bin/sh\n"))
            assertFalse(scriptText.contains("\r"))

            fun runShim(vararg args: String): Pair<Int, String> {
                val cmd = buildList {
                    add("/bin/sh")
                    add(shim.absolutePath)
                    addAll(args)
                }
                val proc = ProcessBuilder(cmd).apply {
                    redirectErrorStream(true)
                    environment()["AGY_SH_BIN"] = "/bin/sh"
                }.start()
                val out = proc.inputStream.bufferedReader().use { it.readText() }
                val code = proc.waitFor()
                return code to out
            }

            // 1. --version succeeds
            val (vCode, vOut) = runShim("--version")
            assertEquals(0, vCode)
            assertTrue(vOut.contains("GNU bash"))

            // 2. bash-only flags (--norc --noprofile -lc) + spacing/quotes preserved
            val (qCode, qOut) = runShim("--norc", "--noprofile", "-lc", "printf '%s|%s' 'hello   world' 'ok'")
            assertEquals(0, qCode)
            assertEquals("hello   world|ok", qOut)

            // 3. Exit code propagation
            val (eCode, eOut) = runShim("-c", "printf 'boom' && exit 7")
            assertEquals(7, eCode)
            assertEquals("boom", eOut)

            // 4. --version AFTER -c is passed through to the command rather than intercepted
            val (pCode, pOut) = runShim("-c", "printf '%s' \"\$0\"", "--version")
            assertEquals(0, pCode)
            assertEquals("--version", pOut)

            // 5. --rcfile <path> and -O <opt> skipped cleanly without consuming -c
            val (rCode, rOut) = runShim("--rcfile", "/nonexistent", "-O", "extglob", "-l", "-c", "printf 'clean'")
            assertEquals(0, rCode)
            assertEquals("clean", rOut)
        } finally {
            tmpBin.deleteRecursively()
        }
    }

    @Test
    fun agyAuthHelperPreservesMcpServersAndRedactsSecrets() {
        val tmpHome = Files.createTempDirectory("agy-auth-test").toFile()
        try {
            val file = AgyAuthHelper.settingsFile(tmpHome)
            file.parentFile?.mkdirs()
            file.writeText("""{"mcpServers":{"custom":{"command":"/system/bin/sh"}}}""")

            val defaultPolicy = AgyAuthHelper.ExecutionPolicy(toolPermission = "proceed-in-sandbox")
            assertFalse(defaultPolicy.allowNonWorkspaceAccess)

            AgyAuthHelper.applySettings(
                tmpHome,
                AgyAuthHelper.AuthConfig(mode = AgyAuthHelper.MODE_OAUTH),
                defaultPolicy,
            )
            val saved = JSONObject(file.readText())
            assertEquals("proceed-in-sandbox", saved.getString("toolPermission"))
            assertFalse(saved.getBoolean("allowNonWorkspaceAccess"))
            assertTrue(saved.getJSONObject("mcpServers").has("custom"))

            val redacted = AgyAuthHelper.redactLine(
                "key=AIzaSyDummySecretKey1234567890 token=ya29.a0AfB_testToken1234567890",
                "AIzaSyDummySecretKey1234567890",
            )
            assertTrue(!redacted.contains("AIzaSyDummySecretKey1234567890"))
            assertTrue(!redacted.contains("ya29.a0AfB_testToken1234567890"))
        } finally {
            tmpHome.deleteRecursively()
        }
    }

    @Test
    fun phoneControllerWritesOfficialMcpConfigWithServerUrlAndCleansLegacySettings() {
        val tmpHome = Files.createTempDirectory("agy-phone-mcp-cfg").toFile()
        try {
            // Seed a legacy stale `phone` entry in settings.json plus an existing custom entry in mcp_config.json.
            val legacy = AgyAuthHelper.settingsFile(tmpHome)
            legacy.parentFile?.mkdirs()
            legacy.writeText("""{"mcpServers":{"phone":{"httpUrl":"http://127.0.0.1:9999/mcp"},"keep":{"command":"echo"}}}""")

            val cfg = PhoneController.mcpConfigFile(tmpHome)
            cfg.parentFile?.mkdirs()
            cfg.writeText("""{"mcpServers":{"context7":{"serverUrl":"https://mcp.example.com/mcp"}}}""")

            PhoneController.writePhoneMcpConfig(
                homeDir = tmpHome,
                url = "http://127.0.0.1:45678/mcp",
                token = "tok_live_123",
                register = true,
            )

            assertTrue(cfg.isFile)
            val saved = JSONObject(cfg.readText()).getJSONObject("mcpServers")
            assertTrue(saved.has("context7"))
            val phone = saved.getJSONObject("phone")
            assertEquals("http://127.0.0.1:45678/mcp", phone.getString("serverUrl"))
            assertFalse(phone.has("httpUrl"))
            assertEquals("Bearer tok_live_123", phone.getJSONObject("headers").getString("Authorization"))
            assertEquals(600, phone.getInt("timeoutSeconds"))
            assertTrue(phone.getJSONObject("tools").getJSONObject("phone_get_screen").getBoolean("eager"))

            // Legacy settings.json `phone` entry is cleaned while custom entries survive.
            val legacyAfter = JSONObject(legacy.readText()).getJSONObject("mcpServers")
            assertFalse(legacyAfter.has("phone"))
            assertTrue(legacyAfter.has("keep"))

            // Unregister removes `phone` from mcp_config.json cleanly.
            PhoneController.writePhoneMcpConfig(tmpHome, null, null, register = false)
            val afterDisable = JSONObject(cfg.readText()).getJSONObject("mcpServers")
            assertFalse(afterDisable.has("phone"))
            assertTrue(afterDisable.has("context7"))
        } finally {
            tmpHome.deleteRecursively()
        }
    }

    @Test
    fun phoneMcpServerSupportsSessionHeaderBatchSelfProbeAndClientTelemetry() {
        val gate = SafetyGate { }
        var notifiedClient: String? = null
        val server = PhoneMcpServer(
            context = ContextWrapper(null),
            safetyGate = gate,
            isEnabled = { true },
            onAudit = { _, _, _ -> },
            onClientActivity = { name -> notifiedClient = name },
        )
        val port = server.start()
        try {
            // Self-probe verifies loopback HTTP without falsely marking agy client connected.
            val (probeOk, probeMsg) = server.selfProbe()
            assertTrue(probeMsg, probeOk)
            assertFalse(server.clientInitialized)

            // Batch JSON-RPC request returns JSON array with both responses + Mcp-Session-Id header.
            val batchBody = """[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"antigravity-cli","version":"1.6.0"}}},{"jsonrpc":"2.0","id":2,"method":"ping","params":{}}]"""
            val batchBytes = batchBody.toByteArray(Charsets.UTF_8)
            val batchReply = sendRawHttp(
                port,
                "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n" +
                    "Content-Type: application/json\r\nContent-Length: ${batchBytes.size}\r\n\r\n$batchBody",
            )
            assertTrue(batchReply.statusLine.contains("200"))
            assertEquals(server.sessionId, batchReply.headers["mcp-session-id"])
            val arr = JSONArray(batchReply.body)
            assertEquals(2, arr.length())
            assertTrue(server.clientInitialized)
            assertEquals("antigravity-cli", notifiedClient)

            // 202 Accepted for notifications omits Content-Type header (empty body).
            val notif = """{"jsonrpc":"2.0","method":"notifications/initialized"}"""
            val notifReply = sendRawHttp(
                port,
                "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${server.authToken}\r\n" +
                    "Content-Length: ${notif.toByteArray(Charsets.UTF_8).size}\r\n\r\n$notif",
            )
            assertTrue(notifReply.statusLine.contains("202"))
            assertFalse(notifReply.headers.containsKey("content-type"))
        } finally {
            server.stop()
        }
    }

    @Test
    fun noProxyLoopbackBypassRestrictedSettingsAndFloatingAskGeometryWorkCorrectly() {
        assertEquals("127.0.0.1,localhost,::1", AgyProcess.mergeNoProxy(null))
        assertEquals(
            "corp.internal,127.0.0.1,localhost,::1",
            AgyProcess.mergeNoProxy("corp.internal, 127.0.0.1 "),
        )

        assertEquals(
            AgyAccessibilityService.RESTRICTED_CLEAR,
            AgyAccessibilityService.classifyRestrictedSettings(31, AppOpsManager.MODE_ERRORED, 3),
        )
        assertEquals(
            AgyAccessibilityService.RESTRICTED_GUARDED,
            AgyAccessibilityService.classifyRestrictedSettings(34, AppOpsManager.MODE_ERRORED, 3),
        )
        assertEquals(
            AgyAccessibilityService.RESTRICTED_ACKNOWLEDGED,
            AgyAccessibilityService.classifyRestrictedSettings(34, AppOpsManager.MODE_IGNORED, 4),
        )
        assertEquals(
            AgyAccessibilityService.RESTRICTED_CLEAR,
            AgyAccessibilityService.classifyRestrictedSettings(35, AppOpsManager.MODE_ALLOWED, 3),
        )

        // FloatingAskPlace places bar beside right-docked orb and lifts above soft keyboard.
        val w = FloatingAskPlace.barWidth(
            screenWidth = 1080,
            orbLeft = 900,
            orbRight = 1056,
            dockedRight = true,
            gap = 20,
            margin = 24,
            minWidth = 650,
            maxWidth = 900,
        )
        assertEquals(856, w)

        val pos = FloatingAskPlace.barPosition(
            screenWidth = 1080,
            screenHeight = 2400,
            orbLeft = 900,
            orbRight = 1056,
            orbCenterY = 1200,
            dockedRight = true,
            barWidth = w,
            barHeight = 320,
            gap = 20,
            margin = 24,
            topInset = 90,
            bottomInset = 60,
        )
        assertEquals(24, pos.x)
        assertEquals(1040, pos.y)

        val lifted = FloatingAskPlace.liftForIme(
            restY = 1500,
            currentScreenY = 1500,
            imeOverlap = 420,
            gap = 20,
            minY = 90,
        )
        assertEquals(1060, lifted)
    }
}
