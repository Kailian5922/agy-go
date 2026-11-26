package io.github.kailian5922.agy_go.system

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.concurrent.thread

/**
 * Native Android system utilities:
 * - FileProvider PNG/text sharing (for Conversation Share Cards & Markdown/JSON exports)
 * - Self-update APK download + optional SHA-256 verification + PackageInstaller handoff
 * - Chinese ROM background keep-alive diagnostics & direct vendor settings intents
 */
class SystemPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
    private val onSetHideStatusBar: ((Boolean) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, METHOD_CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setHideStatusBar" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                mainHandler.post { onSetHideStatusBar?.invoke(enabled) }
                result.success(true)
            }
            "getDeviceInfo" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                val ignoringBattery = pm.isIgnoringBatteryOptimizations(context.packageName)
                val pkgInfo = context.packageManager.getPackageInfo(context.packageName, 0)
                val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pkgInfo.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    pkgInfo.versionCode.toLong()
                }
                result.success(
                    mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "brand" to Build.BRAND,
                        "model" to Build.MODEL,
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "ignoringBatteryOptimizations" to ignoringBattery,
                        "versionName" to (pkgInfo.versionName ?: "0.1.0"),
                        "versionCode" to versionCode,
                    ),
                )
            }
            "requestIgnoreBatteryOptimization" -> {
                try {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:${context.packageName}"),
                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                    context.startActivity(intent)
                    result.success(true)
                } catch (_: Throwable) {
                    openAppDetails()
                    result.success(false)
                }
            }
            "openVendorBackgroundSettings" -> {
                val opened = openVendorAutostartSettings()
                result.success(opened)
            }
            "shareBytes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val filename = call.argument<String>("filename") ?: "agy-share.png"
                val mimeType = call.argument<String>("mimeType") ?: "image/png"
                val title = call.argument<String>("title") ?: "分享"
                if (bytes == null) {
                    result.error("INVALID_ARGS", "bytes required", null)
                    return
                }
                try {
                    val outDir = File(context.cacheDir, "shares").apply { mkdirs() }
                    val file = File(outDir, filename.replace(Regex("[^A-Za-z0-9._-]"), "_"))
                    file.writeBytes(bytes)
                    val uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file,
                    )
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    val chooser = Intent.createChooser(shareIntent, title).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(chooser)
                    result.success(file.absolutePath)
                } catch (e: Throwable) {
                    result.error("SHARE_FAILED", e.message, null)
                }
            }
            "downloadAndInstallApk" -> {
                val url = call.argument<String>("url") ?: ""
                val expectedSha256 = call.argument<String>("sha256")?.lowercase()?.trim()
                if (url.isBlank()) {
                    result.error("INVALID_URL", "Download URL is empty", null)
                    return
                }
                thread(name = "agy-apk-update", isDaemon = true) {
                    try {
                        val apkFile = downloadApk(url, expectedSha256)
                        mainHandler.post {
                            installApkFile(apkFile)
                            result.success(apkFile.absolutePath)
                        }
                    } catch (e: Throwable) {
                        mainHandler.post {
                            result.error("UPDATE_FAILED", e.message, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun downloadApk(urlString: String, expectedSha256: String?): File {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val target = File(dir, "agy-go-update.apk")
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 60_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "agy-go/0.1.0")
        }
        try {
            if (conn.responseCode !in 200..299) {
                throw IllegalStateException("APK download failed with HTTP ${conn.responseCode}")
            }
            val digest = MessageDigest.getInstance("SHA-256")
            BufferedInputStream(conn.inputStream).use { input ->
                FileOutputStream(target).use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        digest.update(buf, 0, n)
                    }
                }
            }
            if (!expectedSha256.isNullOrBlank()) {
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (actual != expectedSha256) {
                    target.delete()
                    throw SecurityException("APK SHA-256 mismatch: expected $expectedSha256, got $actual")
                }
            }
            return target
        } finally {
            conn.disconnect()
        }
    }

    private fun installApkFile(apkFile: File) {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            apkFile,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(intent)
    }

    private fun openVendorAutostartSettings(): Boolean {
        val m = Build.MANUFACTURER.lowercase()
        val candidates = mutableListOf<ComponentName>()
        when {
            m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") -> {
                candidates.add(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"))
                candidates.add(ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"))
            }
            m.contains("huawei") || m.contains("honor") -> {
                candidates.add(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"))
                candidates.add(ComponentName("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"))
            }
            m.contains("oppo") || m.contains("oneplus") || m.contains("realme") -> {
                candidates.add(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"))
                candidates.add(ComponentName("com.oplus.battery", "com.oplus.powermanager.fuelgaue.PowerUsageModelActivity"))
            }
            m.contains("vivo") || m.contains("iqoo") -> {
                candidates.add(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"))
                candidates.add(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"))
            }
            m.contains("samsung") -> {
                candidates.add(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"))
            }
        }

        for (comp in candidates) {
            try {
                val intent = Intent().apply {
                    component = comp
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (context.packageManager.resolveActivity(intent, 0) != null) {
                    context.startActivity(intent)
                    return true
                }
            } catch (_: Throwable) {}
        }

        openAppDetails()
        return false
    }

    private fun openAppDetails() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${context.packageName}"),
        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        context.startActivity(intent)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val METHOD_CHANNEL = "agy/system"
    }
}
