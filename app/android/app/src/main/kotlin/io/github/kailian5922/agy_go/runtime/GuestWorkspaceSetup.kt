package io.github.kailian5922.agy_go.runtime

import java.io.File

/**
 * Maintains managed workspace context instructions (`GEMINI.md` / `AGENTS.md`) inside the
 * on-device runtime home directory so `agy` immediately knows about mounted Android storage
 * paths, workspaces, and optional MCP phone control.
 *
 * If the user removes the `<!-- agy-go:managed` header line, the file is left untouched.
 */
object GuestWorkspaceSetup {
    private const val MARKER = "<!-- agy-go:managed"

    fun writeInstructions(
        homeDir: File,
        workspaceDir: File,
        useProot: Boolean,
        phoneStorageMounted: Boolean,
        phoneControlEnabled: Boolean,
    ) {
        val envDesc = if (useProot) {
            "Ubuntu 24.04 Linux 环境（PRoot，免 Root）"
        } else {
            "Android 原生 Bionic 运行环境（免 Root、免 PRoot）"
        }
        val workspacePath = if (useProot) "/root/workspace" else workspaceDir.absolutePath
        val storageRoot = if (useProot) PhoneStorage.GUEST_PATH else PhoneStorage.hostRoot()
        val shortcutPath = if (useProot) "/root/${PhoneStorage.SHORTCUT_NAME}" else File(homeDir, PhoneStorage.SHORTCUT_NAME).absolutePath

        val storageBlock = if (phoneStorageMounted) {
            """
            |- 用户已授权挂载手机共享存储：内部存储位于 `$storageRoot`（快捷方式 `$shortcutPath`；相册在 `$storageRoot/DCIM`，下载在 `$storageRoot/Download`，文档在 `$storageRoot/Documents`）。
            |- 修改或删除手机里的已有用户文件前请先说明并等待确认；为用户新生成的文件优先输出到 `$storageRoot/Download/AGY-Go/`。
            """.trimMargin()
        } else {
            """
            |- 手机共享存储（相册、下载、文档）当前未挂载；如果任务需要读写手机文件，请提示用户前往「设置 › 手机存储挂载」开启「允许 agy 访问手机文件」。
            """.trimMargin()
        }

        val phoneControlBlock = if (phoneControlEnabled) {
            """
            |
            |## 手机操控（MCP `phone`）
            |- 当前会话已挂载本机 `phone` MCP 服务，可读取当前屏幕节点与执行点击/滑动/输入等操作；所有敏感动作受本机 SafetyGate 审批保护。
            """.trimMargin()
        } else {
            ""
        }

        val content = """
            |<!-- agy-go:managed — 删除此行后，AGY Go 将不再自动更新本文件 -->
            |# 运行环境（AGY Go Android）
            |
            |- 当前运行在 $envDesc 中，由 AGY Go 通过官方 `agy acp` 协议驱动。
            |- 默认工作区目录：`$workspacePath`（每个会话可能通过 ACP `cwd` 切换到用户选择的任意工作区目录）。
            |$storageBlock
            |- 手机屏幕较窄：回复尽量清晰精炼，代码块避免过宽行；使用与用户相同的语言回复。$phoneControlBlock
            |
        """.trimMargin()

        for (target in listOf(
            File(homeDir, ".gemini/GEMINI.md"),
            File(homeDir, "AGENTS.md"),
        )) {
            writeManagedIfAllowed(target, content)
        }
    }

    private fun writeManagedIfAllowed(file: File, content: String) {
        try {
            if (file.exists()) {
                val existing = file.readText()
                if (!existing.startsWith(MARKER)) return
                if (existing == content) return
            }
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, ".${file.name}.tmp")
            tmp.writeText(content)
            if (!tmp.renameTo(file)) {
                file.writeText(content)
                tmp.delete()
            }
        } catch (_: Exception) {
            // Non-fatal: never block engine launch.
        }
    }
}
