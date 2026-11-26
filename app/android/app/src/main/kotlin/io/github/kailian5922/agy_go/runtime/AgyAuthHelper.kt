package io.github.kailian5922.agy_go.runtime

import org.json.JSONObject
import java.io.File

/**
 * Manages `~/.gemini/antigravity-cli/settings.json` inside the app-private HOME directory
 * so AGY Go stays aligned with official Antigravity CLI (`agy`) settings:
 * - Auth mode (Google Account OAuth vs Gemini API Key)
 * - Execution mode (`agentMode`: "", "accept-edits", "auto", "plan")
 * - Tool permission preset (`toolPermission`: "strict", "request-review", "proceed-in-sandbox", "always-proceed")
 * - Artifact review policy (`artifactReviewPolicy`), `allowNonWorkspaceAccess`, `queuedMessages`
 *
 * Unknown keys (`permissions`, `mcpServers`, `customModelsConfig`, etc.) are always preserved.
 */
object AgyAuthHelper {

    data class AuthConfig(
        val mode: String = MODE_OAUTH, // "oauth" | "gemini_api_key"
        val apiKey: String = "",
        val baseUrl: String = "",
    )

    data class ExecutionPolicy(
        val agentMode: String = "", // "" (default) | "accept-edits" | "auto" | "plan"
        val toolPermission: String = "request-review", // "strict" | "request-review" | "proceed-in-sandbox" | "always-proceed"
        val artifactReviewPolicy: String = "asks-for-review", // "asks-for-review" | "always-proceed"
        val allowNonWorkspaceAccess: Boolean = true,
        val queuedMessages: String = "queue", // "queue" | "send-immediately"
    ) {
        val skipPermissions: Boolean get() = toolPermission == "always-proceed"
    }

    const val MODE_OAUTH = "oauth"
    const val MODE_GEMINI_API_KEY = "gemini_api_key"

    fun settingsFile(homeDir: File): File =
        File(homeDir, ".gemini/antigravity-cli/settings.json")

    private fun readJson(file: File): JSONObject {
        if (!file.exists()) return JSONObject()
        return try {
            JSONObject(file.readText())
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun writeJsonAtomic(file: File, json: JSONObject) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "settings.json.tmp")
        tmp.writeText(json.toString(2))
        if (!tmp.renameTo(file)) {
            tmp.copyTo(file, overwrite = true)
            tmp.delete()
        }
    }

    fun applySettings(homeDir: File, config: AuthConfig, policy: ExecutionPolicy? = null) {
        val file = settingsFile(homeDir)
        val json = readJson(file)

        if (config.mode == MODE_GEMINI_API_KEY && config.apiKey.isNotBlank()) {
            json.put("modelProvider", "gemini")
        } else {
            json.remove("modelProvider")
        }

        if (policy != null) {
            applyPolicyKeys(json, policy)
        }

        writeJsonAtomic(file, json)
    }

    fun applyExecutionPolicy(homeDir: File, policy: ExecutionPolicy) {
        val file = settingsFile(homeDir)
        val json = readJson(file)
        applyPolicyKeys(json, policy)
        writeJsonAtomic(file, json)
    }

    private fun applyPolicyKeys(json: JSONObject, policy: ExecutionPolicy) {
        if (policy.agentMode.isBlank() || policy.agentMode == "default") {
            json.put("agentMode", "")
        } else {
            json.put("agentMode", policy.agentMode)
        }
        json.put("toolPermission", policy.toolPermission)
        json.put("artifactReviewPolicy", policy.artifactReviewPolicy)
        json.put("allowNonWorkspaceAccess", policy.allowNonWorkspaceAccess)
        json.put("queuedMessages", policy.queuedMessages)
    }

    fun environmentOverrides(config: AuthConfig): Map<String, String> {
        val env = mutableMapOf<String, String>()
        if (config.mode == MODE_GEMINI_API_KEY && config.apiKey.isNotBlank()) {
            env["GEMINI_API_KEY"] = config.apiKey.trim()
            if (config.baseUrl.isNotBlank()) {
                env["GOOGLE_GEMINI_BASE_URL"] = config.baseUrl.trim()
            }
        }
        return env
    }

    /** Redacts API keys or bearer tokens before logging to UI / storage. */
    fun redactLine(line: String, apiKey: String): String {
        var out = line
        if (apiKey.length >= 8) {
            out = out.replace(apiKey, "[REDACTED_API_KEY]")
        }
        return out
            .replace(Regex("AIza[0-9A-Za-z_-]{20,}"), "[REDACTED_GEMINI_KEY]")
            .replace(Regex("ya29\\.[0-9A-Za-z._-]{20,}"), "[REDACTED_OAUTH_TOKEN]")
    }
}
