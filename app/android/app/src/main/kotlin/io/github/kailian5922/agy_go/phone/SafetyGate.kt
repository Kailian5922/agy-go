package io.github.kailian5922.agy_go.phone

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Three-tier safety gate for MCP phone control actions.
 *
 * Security invariants:
 * - Protected financial/security packages and sensitive keywords ALWAYS require explicit confirmation.
 * - Any timeout, disconnect, or emergency stop fails closed (denies the action).
 */
class SafetyGate(
    private val onApprovalRequested: (ApprovalPrompt) -> Unit,
) {
    enum class Mode(val wire: String) {
        CONFIRM_ALL("confirm_all"),
        CONFIRM_SENSITIVE("confirm_sensitive"),
        AUTO_NON_FINANCIAL("auto_non_financial");

        companion object {
            fun parse(raw: String?): Mode =
                entries.firstOrNull { it.wire == raw } ?: CONFIRM_ALL
        }
    }

    data class ApprovalPrompt(
        val id: String,
        val tool: String,
        val summary: String,
        val riskLevel: String, // "normal" | "sensitive" | "protected"
        val foregroundPackage: String?,
        val reason: String,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id,
            "tool" to tool,
            "summary" to summary,
            "riskLevel" to riskLevel,
            "foregroundPackage" to foregroundPackage,
            "reason" to reason,
        )
    }

    data class Decision(
        val allowed: Boolean,
        val reason: String,
    )

    private class PendingApproval(
        val prompt: ApprovalPrompt,
    ) {
        val latch = CountDownLatch(1)
        @Volatile var approved: Boolean = false
        @Volatile var reason: String = "Timed out waiting for user confirmation"
    }

    @Volatile var mode: Mode = Mode.CONFIRM_ALL
    private val pending = ConcurrentHashMap<String, PendingApproval>()

    fun evaluateAndAwait(
        tool: String,
        isMutating: Boolean,
        summary: String,
        foregroundPackage: String?,
        screenSnippet: String = "",
        timeoutSeconds: Long = 90,
    ): Decision {
        val protectedPkg = isProtectedPackage(foregroundPackage)
        val sensitiveHit = findSensitiveKeyword("$summary $screenSnippet")

        val riskLevel = when {
            protectedPkg -> "protected"
            sensitiveHit != null -> "sensitive"
            else -> "normal"
        }

        val needsPrompt = when {
            protectedPkg && isMutating -> true
            sensitiveHit != null && isMutating -> true
            !isMutating && !protectedPkg -> false
            mode == Mode.CONFIRM_ALL -> true
            mode == Mode.CONFIRM_SENSITIVE -> isMutating
            mode == Mode.AUTO_NON_FINANCIAL -> protectedPkg || sensitiveHit != null
            else -> true
        }

        if (!needsPrompt) {
            return Decision(true, "Auto-allowed by safety mode (${mode.wire})")
        }

        val promptReason = when {
            protectedPkg -> "当前位于受保护的金融/安全应用 ($foregroundPackage)"
            sensitiveHit != null -> "检测到敏感操作关键词「$sensitiveHit」"
            else -> "安全模式要求人工确认"
        }

        val id = "phone_req_${UUID.randomUUID().toString().take(8)}"
        val prompt = ApprovalPrompt(
            id = id,
            tool = tool,
            summary = summary,
            riskLevel = riskLevel,
            foregroundPackage = foregroundPackage,
            reason = promptReason,
        )
        val holder = PendingApproval(prompt)
        pending[id] = holder
        try {
            onApprovalRequested(prompt)
            val completed = holder.latch.await(timeoutSeconds, TimeUnit.SECONDS)
            if (!completed) {
                return Decision(false, "Confirmation timed out (${timeoutSeconds}s); denied fail-closed.")
            }
            return Decision(holder.approved, holder.reason)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            return Decision(false, "Interrupted while awaiting user confirmation.")
        } finally {
            pending.remove(id)
        }
    }

    fun resolve(id: String, approved: Boolean, reason: String? = null): Boolean {
        val holder = pending[id] ?: return false
        holder.approved = approved
        holder.reason = reason ?: if (approved) "Approved by user" else "Rejected by user"
        holder.latch.countDown()
        return true
    }

    fun emergencyStop() {
        for ((_, holder) in pending) {
            holder.approved = false
            holder.reason = "Cancelled by emergency stop"
            holder.latch.countDown()
        }
        pending.clear()
    }

    fun pendingPrompts(): List<Map<String, Any?>> =
        pending.values.map { it.prompt.toMap() }

    companion object {
        private val PROTECTED_PACKAGES = setOf(
            "com.eg.android.AlipayGphone",
            "com.tencent.mm",
            "com.unionpay",
            "com.icbc",
            "com.chinamworld.main",
            "com.chinamworld.bocmbci",
            "cmb.pb",
            "com.android.bankabc",
            "com.google.android.apps.walletnfcrel",
            "com.agilebits.onepassword",
            "com.x8bit.bitwarden",
            "keepass2android.keepass2android",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
        )

        private val SENSITIVE_KEYWORDS = listOf(
            "支付", "付款", "确认付款", "转账", "提现", "充值",
            "密码", "验证码", "指纹", "面容", "卸载", "删除", "格式化", "恢复出厂",
            "payment", "checkout", "transfer", "password", "passcode", "otp", "uninstall", "factory reset",
        )

        fun isProtectedPackage(pkg: String?): Boolean {
            if (pkg.isNullOrBlank()) return false
            val lower = pkg.lowercase()
            return pkg in PROTECTED_PACKAGES ||
                lower.contains("bank") ||
                lower.contains("wallet") ||
                lower.contains("pay") ||
                lower.contains("keychain") ||
                lower.contains("authenticator")
        }

        fun findSensitiveKeyword(text: String): String? {
            if (text.isBlank()) return null
            val lower = text.lowercase()
            return SENSITIVE_KEYWORDS.firstOrNull { lower.contains(it) }
        }
    }
}
