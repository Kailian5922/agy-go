package io.github.kailian5922.agy_go.system

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.kailian5922.agy_go.MainActivity
import io.github.kailian5922.agy_go.R
import io.github.kailian5922.agy_go.notify.LiveActivity
import io.github.kailian5922.agy_go.notify.LiveContent
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.concurrent.thread

/**
 * Native Android system utilities:
 * - Status bar immersion toggle
 * - Native gallery / camera / document pickers (for multimodal ACP attachments & wallpaper)
 * - Background turn-finished & approval-needed local notifications
 * - Android 16+ Live Activity / capsule notifications (HyperOS / ColorOS / MagicOS / Pixel)
 * - FileProvider PNG/text sharing (for Conversation Share Cards & Markdown/JSON exports)
 * - Self-update APK download + optional SHA-256 verification + PackageInstaller handoff
 * - Chinese ROM background keep-alive diagnostics & direct vendor settings intents
 */
class SystemPlugin(
    private val context: Context,
    private val activityProvider: () -> Activity? = { null },
    messenger: BinaryMessenger,
    private val onSetHideStatusBar: ((Boolean) -> Unit)? = null,
    private val onSetKeepScreenOn: ((Boolean) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, METHOD_CHANNEL)
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingPickerKind: Int = 0
    private var pendingCameraFile: File? = null

    init {
        channel.setMethodCallHandler(this)
        LiveActivity.refresh(context)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setHideStatusBar" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                mainHandler.post { onSetHideStatusBar?.invoke(enabled) }
                result.success(true)
            }
            "setKeepScreenOn" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                mainHandler.post { onSetKeepScreenOn?.invoke(enabled) }
                result.success(true)
            }
            "pickImage" -> launchDocumentPicker("image/*", REQ_PICK_IMAGE, result)
            "pickFile" -> launchDocumentPicker("*/*", REQ_PICK_FILE, result)
            "capturePhoto" -> launchCameraCapture(result)
            "notifyTurnEvent" -> {
                val title = call.argument<String>("title") ?: "AGY Go"
                val body = call.argument<String>("body") ?: ""
                val urgent = call.argument<Boolean>("urgent") ?: false
                postTurnNotification(title, body, urgent)
                result.success(true)
            }
            "updateLiveActivity" -> {
                val enabled = call.argument<Boolean>("enabled") != false
                val content = LiveContent.fromMap(call.argument<Map<*, *>>("activity"))
                LiveActivity.update(context, enabled = enabled, content = content)
                result.success(true)
            }
            "getLiveActivityStatus" -> {
                thread(name = "agy-live-status", isDaemon = true) {
                    val status = runCatching { LiveActivity.status(context) }.getOrNull()
                    mainHandler.post { result.success(status) }
                }
            }
            "openLiveActivitySettings" -> {
                val opened = startFirstIntent(
                    listOf(
                        LiveActivity.settingsIntent(context),
                        LiveActivity.appNotificationSettingsIntent(context),
                        appDetailsIntent(),
                    ),
                )
                result.success(opened)
            }
            "openNotificationSettings" -> {
                val opened = startFirstIntent(
                    listOf(
                        LiveActivity.appNotificationSettingsIntent(context),
                        appDetailsIntent(),
                    ),
                )
                result.success(opened)
            }
            "previewLiveActivity" -> {
                val accentColor = (call.argument<Any>("accentColor") as? Number)?.toInt()
                thread(name = "agy-live-preview", isDaemon = true) {
                    val posted = runCatching {
                        LiveActivity.postPreview(context, accentColor)
                    }.getOrDefault(false)
                    mainHandler.post { result.success(posted) }
                }
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
                        "versionName" to (pkgInfo.versionName ?: "0.2.0"),
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

    @Suppress("DEPRECATION")
    private fun launchDocumentPicker(mime: String, requestCode: Int, result: MethodChannel.Result) {
        val activity = activityProvider()
        if (activity == null) {
            result.error("NO_ACTIVITY", "No foreground activity", null)
            return
        }
        pendingPickerResult?.success(null)
        pendingPickerResult = result
        pendingPickerKind = requestCode
        pendingCameraFile = null
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (e: Throwable) {
            pendingPickerResult = null
            pendingPickerKind = 0
            result.error("PICKER_UNAVAILABLE", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun launchCameraCapture(result: MethodChannel.Result) {
        val activity = activityProvider()
        if (activity == null) {
            result.error("NO_ACTIVITY", "No foreground activity", null)
            return
        }
        val outDir = File(context.cacheDir, "attachments").apply { mkdirs() }
        val photoFile = File(outDir, "cam_${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            photoFile,
        )
        pendingPickerResult?.success(null)
        pendingPickerResult = result
        pendingPickerKind = REQ_CAPTURE_PHOTO
        pendingCameraFile = photoFile
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQ_CAPTURE_PHOTO)
        } catch (e: Throwable) {
            pendingPickerResult = null
            pendingPickerKind = 0
            pendingCameraFile = null
            result.error("CAMERA_UNAVAILABLE", e.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK_IMAGE &&
            requestCode != REQ_PICK_FILE &&
            requestCode != REQ_CAPTURE_PHOTO
        ) {
            return false
        }
        val callback = pendingPickerResult
        val camFile = pendingCameraFile
        pendingPickerResult = null
        pendingPickerKind = 0
        pendingCameraFile = null
        if (callback == null) return true

        if (resultCode != Activity.RESULT_OK) {
            camFile?.delete()
            callback.success(null)
            return true
        }

        if (requestCode == REQ_CAPTURE_PHOTO) {
            if (camFile == null || !camFile.exists() || camFile.length() == 0L) {
                callback.success(null)
                return true
            }
            thread(name = "agy-cam-read", isDaemon = true) {
                val payload = runCatching {
                    val bytes = if (camFile.length() <= MAX_INLINE_BYTES) camFile.readBytes() else null
                    mapOf(
                        "name" to camFile.name,
                        "path" to camFile.absolutePath,
                        "mimeType" to "image/jpeg",
                        "sizeBytes" to camFile.length(),
                        "bytes" to bytes,
                    )
                }.getOrNull()
                mainHandler.post { callback.success(payload) }
            }
            return true
        }

        val uri = data?.data
        if (uri == null) {
            callback.success(null)
            return true
        }

        thread(name = "agy-doc-copy", isDaemon = true) {
            val payload = runCatching { copyPickedUri(uri, includeBytes = requestCode == REQ_PICK_IMAGE) }.getOrNull()
            mainHandler.post { callback.success(payload) }
        }
        return true
    }

    private fun copyPickedUri(uri: Uri, includeBytes: Boolean): Map<String, Any?>? {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: if (includeBytes) "image/jpeg" else "application/octet-stream"
        var displayName = "attachment_${System.currentTimeMillis()}"
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) {
                    cursor.getString(idx)?.takeIf { it.isNotBlank() }?.let { displayName = it }
                }
            }
        }
        val safeName = displayName.replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5]"), "_")
        val outDir = File(context.cacheDir, "attachments").apply { mkdirs() }
        val outFile = File(outDir, "${System.currentTimeMillis()}_$safeName")
        resolver.openInputStream(uri)?.use { input ->
            FileOutputStream(outFile).use { out ->
                val buf = ByteArray(32 * 1024)
                var total = 0L
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_STAGED_BYTES) {
                        outFile.delete()
                        return null
                    }
                    out.write(buf, 0, n)
                }
            }
        } ?: return null

        val bytes = if ((includeBytes || mime.startsWith("image/")) && outFile.length() <= MAX_INLINE_BYTES) {
            outFile.readBytes()
        } else {
            null
        }
        return mapOf(
            "name" to displayName,
            "path" to outFile.absolutePath,
            "mimeType" to mime,
            "sizeBytes" to outFile.length(),
            "bytes" to bytes,
        )
    }

    private fun postTurnNotification(title: String, body: String, urgent: Boolean) {
        try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            val channelId = if (urgent) CHANNEL_URGENT else CHANNEL_DONE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (nm.getNotificationChannel(channelId) == null) {
                    val ch = NotificationChannel(
                        channelId,
                        if (urgent) "审批与确认提醒" else "回复完成提醒",
                        if (urgent) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_DEFAULT,
                    ).apply {
                        description = if (urgent) {
                            "当 Antigravity 需要你确认命令或文件改动时通知"
                        } else {
                            "当后台长任务生成完毕时通知"
                        }
                    }
                    nm.createNotificationChannel(ch)
                }
            }
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pi = PendingIntent.getActivity(
                context,
                if (urgent) 21 else 22,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notif = builder
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(R.drawable.ic_stat_agy)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            nm.notify(if (urgent) 4201 else 4202, notif)
        } catch (_: Throwable) {
            // Ignore when POST_NOTIFICATIONS is not granted on Android 13+.
        }
    }

    private fun downloadApk(urlString: String, expectedSha256: String?): File {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val target = File(dir, "agy-go-update.apk")
        val conn = (URL(urlString).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 60_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "agy-go/0.2.0")
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

    private fun appDetailsIntent(): Intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:${context.packageName}"),
    )

    private fun startFirstIntent(intents: List<Intent>): Boolean {
        val host = activityProvider()
        for (intent in intents) {
            val ok = runCatching {
                if (host != null) {
                    host.startActivity(intent)
                } else {
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }.isSuccess
            if (ok) return true
        }
        return false
    }

    private fun openAppDetails() {
        startFirstIntent(listOf(appDetailsIntent()))
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPickerResult = null
    }

    companion object {
        const val METHOD_CHANNEL = "agy/system"
        private const val REQ_PICK_IMAGE = 0x601
        private const val REQ_PICK_FILE = 0x602
        private const val REQ_CAPTURE_PHOTO = 0x603
        private const val MAX_INLINE_BYTES = 6L * 1024 * 1024
        private const val MAX_STAGED_BYTES = 40L * 1024 * 1024
        private const val CHANNEL_URGENT = "agy_turn_alerts_urgent"
        private const val CHANNEL_DONE = "agy_turn_alerts_done"
    }
}
