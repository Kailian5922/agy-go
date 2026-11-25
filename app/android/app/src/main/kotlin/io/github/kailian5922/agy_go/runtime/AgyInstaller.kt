package io.github.kailian5922.agy_go.runtime

import android.content.Context
import android.os.Build
import android.system.Os
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Downloads, SHA-512 verifies, and atomically installs the official Google Antigravity CLI (`agy`)
 * native Android Bionic arm64 binary into app-private storage (`filesDir/runtime/bin/agy`).
 *
 * Google's official auto-updater manifest (`install.sh` source of truth):
 *   https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/android_arm64.json
 */
class AgyInstaller(private val context: Context) {

    data class ReleaseManifest(
        val platform: String,
        val version: String,
        val url: String,
        val sha512: String,
    )

    data class InstalledInfo(
        val version: String,
        val platform: String,
        val binaryPath: String,
    )

    interface ProgressListener {
        fun onProgress(stage: String, fraction: Double, detail: String)
        fun onLog(line: String)
    }

    val runtimeRoot: File get() = File(context.filesDir, "runtime")
    val binDir: File get() = File(runtimeRoot, "bin")
    val agyBinary: File get() = File(binDir, "agy")
    val versionFile: File get() = File(runtimeRoot, "version.json")
    val homeDir: File get() = File(context.filesDir, "home")
    val workspaceDir: File get() = File(homeDir, "workspace")
    val prootRootfsDir: File get() = File(runtimeRoot, "rootfs")

    fun primaryAbi(): String = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"

    fun nativePlatformForDevice(): String? {
        val abis = Build.SUPPORTED_ABIS
        return if (abis.any { it == "arm64-v8a" }) "android_arm64" else null
    }

    fun isProotAvailable(): Boolean {
        val nativeDir = File(context.applicationInfo.nativeLibraryDir)
        val proot = File(nativeDir, "libproot.so")
        return proot.exists() && prootRootfsDir.exists() && File(prootRootfsDir, "bin/sh").exists()
    }

    fun installedInfo(): InstalledInfo? {
        if (!agyBinary.exists() || !agyBinary.canExecute()) return null
        if (!versionFile.exists()) {
            return InstalledInfo(
                version = "unknown",
                platform = nativePlatformForDevice() ?: "android_arm64",
                binaryPath = agyBinary.absolutePath,
            )
        }
        return try {
            val json = JSONObject(versionFile.readText())
            InstalledInfo(
                version = json.optString("version", "unknown"),
                platform = json.optString("platform", "android_arm64"),
                binaryPath = agyBinary.absolutePath,
            )
        } catch (_: Exception) {
            InstalledInfo("unknown", "android_arm64", agyBinary.absolutePath)
        }
    }

    fun fetchManifest(platform: String = "android_arm64"): ReleaseManifest {
        val manifestUrl = "$MANIFEST_BASE_URL/manifests/$platform.json"
        val conn = (URL(manifestUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 20_000
            requestMethod = "GET"
            setRequestProperty("User-Agent", "agy-go/0.1.0")
        }
        try {
            val code = conn.responseCode
            if (code !in 200..299) {
                throw IOException("Manifest request failed with HTTP $code ($manifestUrl)")
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val version = json.getString("version")
            val url = json.getString("url")
            val sha512 = json.getString("sha512").lowercase().trim()
            if (version.isBlank() || url.isBlank() || sha512.length != 128) {
                throw IOException("Malformed release manifest for $platform")
            }
            return ReleaseManifest(platform, version, url, sha512)
        } finally {
            conn.disconnect()
        }
    }

    fun installOrUpdate(listener: ProgressListener): InstalledInfo {
        val platform = nativePlatformForDevice()
            ?: throw UnsupportedOperationException(
                "Native Android binary requires arm64-v8a (current ABI: ${primaryAbi()}). " +
                    "On x86_64 emulators, use SSH remote mode or install the optional PRoot Ubuntu rootfs.",
            )

        ensureDirectories()

        listener.onProgress("manifest", 0.05, "Querying official Antigravity CLI manifest ($platform)...")
        listener.onLog("[installer] fetching manifest for $platform")
        val manifest = fetchManifest(platform)
        listener.onLog("[installer] latest version: ${manifest.version}")

        val stagingDir = File(context.cacheDir, "agy-staging").apply {
            deleteRecursively()
            mkdirs()
        }
        val archiveFile = File(stagingDir, "agy.tar.gz")
        val extractedFile = File(stagingDir, "antigravity")

        try {
            listener.onProgress("download", 0.1, "Downloading agy ${manifest.version}...")
            downloadAndHash(manifest.url, archiveFile, manifest.sha512, listener)

            listener.onProgress("extract", 0.85, "Extracting agy ${manifest.version}...")
            extractBinaryFromTarGz(archiveFile, extractedFile)
            listener.onLog("[installer] extracted ${extractedFile.length()} bytes")

            listener.onProgress("finalize", 0.95, "Activating runtime...")
            binDir.mkdirs()
            val stagedTarget = File(binDir, "agy.new")
            extractedFile.copyTo(stagedTarget, overwrite = true)
            try {
                Os.chmod(stagedTarget.absolutePath, 0b111_101_101) // 0755
            } catch (_: Throwable) {
                stagedTarget.setExecutable(true, false)
            }
            if (!stagedTarget.renameTo(agyBinary)) {
                stagedTarget.copyTo(agyBinary, overwrite = true)
                stagedTarget.delete()
                agyBinary.setExecutable(true, false)
            }

            val meta = JSONObject().apply {
                put("version", manifest.version)
                put("platform", manifest.platform)
                put("sha512", manifest.sha512)
                put("installedAtMs", System.currentTimeMillis())
            }
            val metaTmp = File(runtimeRoot, "version.json.tmp")
            metaTmp.writeText(meta.toString(2))
            if (!metaTmp.renameTo(versionFile)) {
                metaTmp.copyTo(versionFile, overwrite = true)
                metaTmp.delete()
            }

            listener.onProgress("done", 1.0, "Installed agy ${manifest.version}")
            listener.onLog("[installer] ready at ${agyBinary.absolutePath}")
            return InstalledInfo(manifest.version, manifest.platform, agyBinary.absolutePath)
        } finally {
            stagingDir.deleteRecursively()
        }
    }

    fun ensureDirectories() {
        runtimeRoot.mkdirs()
        binDir.mkdirs()
        homeDir.mkdirs()
        workspaceDir.mkdirs()
        File(context.cacheDir, "tmp").mkdirs()
    }

    fun resetRuntime(keepHome: Boolean = true) {
        runtimeRoot.deleteRecursively()
        if (!keepHome) {
            homeDir.deleteRecursively()
        }
        ensureDirectories()
    }

    private fun downloadAndHash(
        urlString: String,
        dest: File,
        expectedSha512: String,
        listener: ProgressListener,
    ) {
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            connectTimeout = 25_000
            readTimeout = 60_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "agy-go/0.1.0")
        }
        try {
            val code = conn.responseCode
            if (code !in 200..299) {
                throw IOException("Download failed with HTTP $code")
            }
            val total = conn.contentLengthLong
            val digest = MessageDigest.getInstance("SHA-512")
            var downloaded = 0L
            var lastReportedPct = -1

            BufferedInputStream(conn.inputStream).use { input ->
                FileOutputStream(dest).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        digest.update(buffer, 0, read)
                        downloaded += read
                        if (total > 0) {
                            val pct = ((downloaded * 100) / total).toInt()
                            if (pct != lastReportedPct && pct % 2 == 0) {
                                lastReportedPct = pct
                                val fraction = 0.1 + (0.72 * downloaded / total.toDouble())
                                val mb = downloaded / (1024.0 * 1024.0)
                                val totalMb = total / (1024.0 * 1024.0)
                                listener.onProgress(
                                    "download",
                                    fraction.coerceIn(0.1, 0.82),
                                    String.format("Downloading %.1f / %.1f MB (%d%%)", mb, totalMb, pct),
                                )
                            }
                        }
                    }
                }
            }

            listener.onProgress("verify", 0.83, "Verifying SHA-512 signature...")
            val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
            if (actualHash != expectedSha512) {
                dest.delete()
                throw SecurityException(
                    "SHA-512 checksum mismatch! Expected $expectedSha512, got $actualHash",
                )
            }
            listener.onLog("[installer] SHA-512 verified (${downloaded / 1024} KB)")
        } finally {
            conn.disconnect()
        }
    }

    private fun extractBinaryFromTarGz(archive: File, outputFile: File) {
        TarArchiveInputStream(GzipCompressorInputStream(BufferedInputStream(FileInputStream(archive)))).use { tar ->
            var entry = tar.nextEntry
            while (entry != null) {
                val baseName = File(entry.name).name
                if (!entry.isDirectory && (baseName == "antigravity" || baseName == "agy")) {
                    FileOutputStream(outputFile).use { out ->
                        tar.copyTo(out)
                    }
                    return
                }
                entry = tar.nextEntry
            }
        }
        throw IOException("Archive did not contain expected 'antigravity' binary")
    }

    companion object {
        const val MANIFEST_BASE_URL =
            "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
    }
}
