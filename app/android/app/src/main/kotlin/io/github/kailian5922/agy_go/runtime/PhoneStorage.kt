// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.
package io.github.kailian5922.agy_go.runtime

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.system.Os
import android.system.OsConstants
import java.io.File

/**
 * Optional access to the phone's shared storage from the on-device Antigravity runtime
 * (both Native Android Bionic and PRoot Linux modes).
 *
 * With targetSdk 28 + requestLegacyExternalStorage, READ/WRITE_EXTERNAL_STORAGE grants
 * real POSIX file-path access on Android 8-15; "All files access" (MANAGE_EXTERNAL_STORAGE)
 * acts as the Android 11+ fallback on OEM ROMs that enforce scoped storage regardless.
 */
object PhoneStorage {
    /** Guest mount point inside PRoot Linux rootfs. */
    const val GUEST_PATH = "/sdcard"

    /** Shortcut name placed inside the engine's home directory. */
    const val SHORTCUT_NAME = "手机存储"

    fun hostRoot(): String = Environment.getExternalStorageDirectory().absolutePath // /storage/emulated/0

    fun outputDir(): String = "${hostRoot()}/Download/AGY-Go"

    fun isGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
            return true
        }
        val write = context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        if (!write) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Environment.isExternalStorageLegacy()
    }

    fun status(context: Context): Map<String, Any?> = mapOf(
        "granted" to isGranted(context),
        "permission" to (context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED),
        "legacy" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Environment.isExternalStorageLegacy()),
        "guestPath" to GUEST_PATH,
        "hostPath" to hostRoot(),
        "outputPath" to outputDir(),
        "supportsAllFilesAccess" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R),
        "needsAllFilesFallback" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageLegacy()),
    )

    /** PRoot `-b` bind arguments for shared storage + any extra host workspace folders. */
    fun prootBinds(includePhoneStorage: Boolean, extraPaths: List<String> = emptyList()): List<String> {
        val binds = LinkedHashSet<String>()
        if (includePhoneStorage) {
            val root = hostRoot()
            if (File(root).canRead()) {
                binds += "$root:$GUEST_PATH"
                binds += "/storage"
            }
        }
        for (raw in extraPaths) {
            val clean = raw.trim()
            if (clean.startsWith("/") && File(clean).exists()) {
                binds += clean
            }
        }
        return binds.toList()
    }

    /**
     * Synchronizes the `~/手机存储` shortcut symlink in the active home directory.
     * - Native Bionic mode: `${homeDir}/手机存储` -> `/storage/emulated/0`
     * - PRoot mode: `${rootfsDir}/root/手机存储` -> `/sdcard` (when rootfs exists)
     */
    fun syncShortcuts(homeDir: File, rootfsDir: File, enabled: Boolean) {
        syncOneSymlink(File(homeDir, SHORTCUT_NAME), hostRoot(), enabled)
        if (rootfsDir.isDirectory) {
            val prootRoot = File(rootfsDir, "root")
            if (prootRoot.isDirectory) {
                syncOneSymlink(File(prootRoot, SHORTCUT_NAME), GUEST_PATH, enabled)
            }
        }
    }

    private fun syncOneSymlink(link: File, expectedTarget: String, enabled: Boolean) {
        try {
            val info = Os.lstat(link.path)
            if (!enabled && OsConstants.S_ISLNK(info.st_mode) &&
                (Os.readlink(link.path) == expectedTarget || Os.readlink(link.path) == GUEST_PATH)
            ) {
                link.delete()
            }
            return
        } catch (_: Exception) {
            // Absent; proceed to create if enabled.
        }
        if (enabled) {
            link.parentFile?.mkdirs()
            runCatching { Os.symlink(expectedTarget, link.path) }
        }
    }

    /** Opens the system "All files access" page for this app (Android 11+), with OEM fallback. */
    fun openAllFilesAccess(context: Context, activity: android.app.Activity? = null): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        val candidates = listOf(
            Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            ),
            Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"),
            ),
        )
        for (intent in candidates) {
            val ok = runCatching {
                if (activity != null) {
                    activity.startActivity(intent)
                } else {
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }.isSuccess
            if (ok) return true
        }
        return false
    }
}
