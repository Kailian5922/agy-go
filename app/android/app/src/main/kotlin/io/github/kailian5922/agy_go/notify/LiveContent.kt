// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

package io.github.kailian5922.agy_go.notify

/**
 * Pure value model for AGY Go's Live Activity / capsule notification:
 * promoted to an Android 16+ Live Update status-bar chip / island (HyperOS 3.1+ 超级岛,
 * ColorOS 16 流体云, MagicOS 10 灵动胶囊, Pixel Live Updates), and accompanied by
 * Xiaomi HyperOS Focus extras where SystemUI permits them.
 */
data class LiveContent(
    val kind: Kind,
    val title: String,
    val text: String,
    /** Concise status label for the status-bar chip / island (e.g. 「思考中」「待确认」「完成」). */
    val chip: String?,
    /** Privacy-safe lock-screen summary shown when sensitive notification content is hidden. */
    val publicText: String,
    /** Wall-clock start timestamp in epoch ms; enables the live ticking chronometer while running. */
    val sinceMs: Long? = null,
    /** Optional theme accent color ARGB int forwarded from Flutter. */
    val accentColor: Int? = null,
    /** Conversation session ID opened when the capsule is tapped. */
    val sessionId: String? = null,
    /** Optional override timeout (used for explicit 10-second test previews). */
    val timeoutMs: Long? = null,
) {
    enum class Kind(val wire: String) {
        PHONE("phone"),
        WAITING("waiting"),
        RUNNING("running"),
        DONE("done"),
        FAILED("failed");

        companion object {
            fun parse(wire: Any?): Kind? = entries.firstOrNull { it.wire == wire }
        }
    }

    /** Active work in progress: indeterminate progress bar and periodic refresh. */
    val busy: Boolean get() = kind == Kind.PHONE || kind == Kind.RUNNING

    /** Brief completion/failure receipt: short timeout so stale status clears itself. */
    val ending: Boolean get() = kind == Kind.DONE || kind == Kind.FAILED

    /**
     * Status-bar chip text for Android 16 `setShortCriticalText`:
     * returns null while a timed run counts up so Android 16 renders the live ticking clock
     * directly inside the status-bar capsule (exact DSH Go behavior).
     */
    val chipWords: String? get() = if (kind == Kind.RUNNING && sinceMs != null) null else chip

    companion object {
        const val TITLE_MAX = 80
        const val TEXT_MAX = 160
        /** Android 16 shows up to ~7-12 characters cleanly inside a status-bar capsule chip. */
        const val CHIP_MAX = 12

        fun fromMap(m: Map<*, *>?): LiveContent? {
            m ?: return null
            val kind = Kind.parse(m["kind"]) ?: return null
            val title = (m["title"] as? String)?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            fun str(key: String, max: Int): String? =
                (m[key] as? String)?.trim()?.takeIf { it.isNotEmpty() }?.take(max)

            return LiveContent(
                kind = kind,
                title = title.take(TITLE_MAX),
                text = str("text", TEXT_MAX).orEmpty(),
                chip = str("chip", CHIP_MAX),
                publicText = str("publicText", TEXT_MAX) ?: title.take(TITLE_MAX),
                sinceMs = (m["sinceMs"] as? Number)?.toLong()?.takeIf { it > 0L },
                accentColor = (m["accentColor"] as? Number)?.toInt(),
                sessionId = str("sessionId", 200),
                timeoutMs = (m["timeoutMs"] as? Number)?.toLong()?.takeIf { it > 0L },
            )
        }
    }
}
