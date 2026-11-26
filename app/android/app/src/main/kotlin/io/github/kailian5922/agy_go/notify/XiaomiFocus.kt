// Adapted from DSH Go (AGPL-3.0) — see THIRD_PARTY_NOTICES.md.

package io.github.kailian5922.agy_go.notify

import android.app.Notification
import android.content.Context
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import org.json.JSONObject

/**
 * Xiaomi HyperOS Focus Notification / 超级岛 (`miui.focus.param` + `miui.focus.pics`).
 *
 * Attached only when HyperOS SystemUI explicitly permits focus notifications for this package
 * (`canShowFocus`). On HyperOS 3.1+, standard Android 16 Live Updates ([LiveActivity]) are also
 * promoted directly into the island even without store allowlisting.
 */
object XiaomiFocus {
    const val EXTRA_PARAM = "miui.focus.param"
    const val EXTRA_PICS = "miui.focus.pics"
    const val PIC_ICON = "miui.focus.pic_icon"

    private const val PROTOCOL_SETTING = "notification_focus_protocol"
    private const val PROVIDER = "content://miui.statusbar.notification.public"
    private const val CHECK_TTL_MS = 60_000L

    /** Xiaomi Focus JSON payload cap in UTF-8 bytes. */
    const val PARAM_MAX_BYTES = 3072

    /** Island text slot fits ~4-6 concise CJK characters cleanly. */
    private const val ISLAND_CHARS = 6

    @Volatile private var checked: Pair<Long, Boolean>? = null

    fun isXiaomiDevice(): Boolean {
        val m = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase()
        return m.contains("xiaomi") || m.contains("redmi") || m.contains("poco")
    }

    /** Builds the `miui.focus.param` JSON template capped within [PARAM_MAX_BYTES]. */
    fun param(c: LiveContent): String {
        val word = (c.chip ?: c.title).take(ISLAND_CHARS)
        var title = c.title
        var text = c.text
        while (true) {
            val json = templateJson(c, word, title, text).toString()
            if (json.toByteArray(Charsets.UTF_8).size <= PARAM_MAX_BYTES || (title.length <= 8 && text.isEmpty())) {
                return json
            }
            if (text.isNotEmpty()) {
                text = text.take(text.length / 2)
            } else {
                title = title.take(title.length / 2)
            }
        }
    }

    private fun templateJson(c: LiveContent, word: String, title: String, text: String): JSONObject {
        val pic = JSONObject()
            .put("type", 1)
            .put("pic", PIC_ICON)

        val imageTextLeft = JSONObject()
            .put("type", 1)
            .put("picInfo", pic)
            .put("textInfo", JSONObject().put("title", word))

        val paramIsland = JSONObject()
            .put("islandProperty", 1)
            .put("bigIslandArea", JSONObject().put("imageTextInfoLeft", imageTextLeft))
            .put("smallIslandArea", JSONObject().put("picInfo", pic))

        val baseInfo = JSONObject()
            .put("type", 2)
            .put("title", title)
            .put("content", text)

        val paramV2 = JSONObject()
            .put("protocol", 1)
            .put("business", "agy_live_${c.kind.wire}")
            .put("updatable", true)
            .put("enableFloat", false)
            .put("ticker", "$word · $title")
            .put("aodTitle", word)
            .put("param_island", paramIsland)
            .put("baseInfo", baseInfo)

        return JSONObject().put("param_v2", paramV2)
    }

    /** Attaches HyperOS Focus extras to [builder] when SystemUI allows it. Call off main thread. */
    fun apply(context: Context, builder: Notification.Builder, c: LiveContent, picture: Icon) {
        if (!allowed(context)) return
        builder.addExtras(
            Bundle().apply {
                putString(EXTRA_PARAM, param(c))
                putBundle(EXTRA_PICS, Bundle().apply { putParcelable(PIC_ICON, picture) })
            },
        )
    }

    /** Whether HyperOS SystemUI accepts focus notifications from this package (60s cached). */
    fun allowed(context: Context): Boolean {
        val now = SystemClock.elapsedRealtime()
        checked?.let { (at, ok) -> if (now - at < CHECK_TTL_MS) return ok }
        val ok = protocol(context) >= 1 && canShowFocus(context)
        checked = now to ok
        return ok
    }

    /** 1: HyperOS 1, 2: HyperOS 2, 3: HyperOS 3 (超级岛); 0 elsewhere. */
    fun protocol(context: Context): Int {
        if (!isXiaomiDevice()) return 0
        return runCatching {
            Settings.System.getInt(context.contentResolver, PROTOCOL_SETTING, 0)
        }.getOrDefault(0)
    }

    private fun canShowFocus(context: Context): Boolean = runCatching {
        val extras = Bundle().apply { putString("package", context.packageName) }
        context.contentResolver
            .call(Uri.parse(PROVIDER), "canShowFocus", null, extras)
            ?.getBoolean("canShowFocus", false) == true
    }.getOrDefault(false)
}
