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
        val storageRoot = if (useProot) PhoneStorage.GUEST_PATH else PhoneStorage.hostRoot()

        val storageBlock = if (phoneStorageMounted) {
            """
            |- 手机共享存储访问权限已开启（根目录 `$storageRoot`）：仅当用户将其子目录设为当前会话工作区或明确点名路径时才读写，修改/删除已有用户文件前请先说明并等待确认。
            """.trimMargin()
        } else {
            """
            |- 手机共享存储（相册、下载、文档）当前未挂载；如果任务需要读写手机文件，请提示用户前往「设置 › 手机存储挂载」开启「允许 agy 访问手机文件」。
            """.trimMargin()
        }

        val toolEnvBlock = if (useProot) {
            ""
        } else {
            """
            |- 本机原生 Bionic 环境的终端命令通过 `PATH` 中的 `bash` 兼容垫片转交给 `/system/bin/sh`（Android mksh + toybox，支持 `ls`/`cat`/`cp`/`mv`/`rm`/`mkdir`/`find`/`grep`/`sed`/`head`/`tail`/`wc`/`tar`/`gzip`/`chmod`/`stat`/`sha256sum` 等标准 POSIX 命令），未预装 `git`/`python3`/`node`/`jq`/`rg`/`curl`；请使用标准 POSIX sh 语法。
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
            |- 工作区隔离规则：只将当前 ACP 会话指定的 `cwd`（以及本会话显式附加的目录）视为唯一工作区，不要主动读取或列出应用私有目录（如 `files/home/workspace`）或其他无关目录。
            |$storageBlock${if (toolEnvBlock.isNotEmpty()) "\n$toolEnvBlock" else ""}
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
