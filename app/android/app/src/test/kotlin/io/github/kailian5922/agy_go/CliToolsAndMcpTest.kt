package io.github.kailian5922.agy_go

import android.content.ContextWrapper
import io.github.kailian5922.agy_go.phone.PhoneMcpServer
import io.github.kailian5922.agy_go.phone.SafetyGate
import io.github.kailian5922.agy_go.runtime.AgyAuthHelper
import io.github.kailian5922.agy_go.runtime.GuestWorkspaceSetup
import org.json.JSONObject
import org.junit.Assert.assertEquals
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
            assertTrue(geminiMd.contains("toybox"))
            assertTrue(geminiMd.contains("手机操控（MCP `phone`）"))
        } finally {
            tmpHome.deleteRecursively()
        }
    }

    @Test
    fun agyAuthHelperPreservesMcpServersAndRedactsSecrets() {
        val tmpHome = Files.createTempDirectory("agy-auth-test").toFile()
        try {
            val file = AgyAuthHelper.settingsFile(tmpHome)
            file.parentFile?.mkdirs()
            file.writeText("""{"mcpServers":{"custom":{"command":"/system/bin/sh"}}}""")

            AgyAuthHelper.applySettings(
                tmpHome,
                AgyAuthHelper.AuthConfig(mode = AgyAuthHelper.MODE_OAUTH),
                AgyAuthHelper.ExecutionPolicy(toolPermission = "proceed-in-sandbox"),
            )
            val saved = JSONObject(file.readText())
            assertEquals("proceed-in-sandbox", saved.getString("toolPermission"))
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
}
