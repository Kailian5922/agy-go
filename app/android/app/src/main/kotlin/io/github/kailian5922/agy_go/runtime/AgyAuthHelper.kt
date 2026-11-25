package io.github.kailian5922.agy_go.runtime

import org.json.JSONObject
import java.io.File

/**
 * Manages ~/.gemini/antigravity-cli/settings.json inside the app-private HOME directory
 * so users can seamlessly switch between Google Account OAuth and Gemini API Key modes.
 */
object AgyAuthHelper {

    data class AuthConfig(
        val mode: String = MODE_OAUTH, // "oauth" | "gemini_api_key"
        val apiKey: String = "",
        val baseUrl: String = "",
    )

    const val MODE_OAUTH = "oauth"
    const val MODE_GEMINI_API_KEY = "gemini_api_key"

    fun settingsFile(homeDir: File): File =
        File(homeDir, ".gemini/antigravity-cli/settings.json")

    fun applySettings(homeDir: File, config: AuthConfig) {
        val file = settingsFile(homeDir)
        file.parentFile?.mkdirs()
        val json = if (file.exists()) {
            try {
                JSONObject(file.readText())
            } catch (_: Exception) {
                JSONObject()
            }
        } else {
            JSONObject()
        }

        if (config.mode == MODE_GEMINI_API_KEY && config.apiKey.isNotBlank()) {
            json.put("modelProvider", "gemini")
        } else {
            json.remove("modelProvider")
        }

        val tmp = File(file.parentFile, "settings.json.tmp")
        tmp.writeText(json.toString(2))
        if (!tmp.renameTo(file)) {
            tmp.copyTo(file, overwrite = true)
            tmp.delete()
        }
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
