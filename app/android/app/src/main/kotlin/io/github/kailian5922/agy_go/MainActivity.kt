package io.github.kailian5922.agy_go

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.kailian5922.agy_go.notify.LiveActivity
import io.github.kailian5922.agy_go.pet.PetPlugin
import io.github.kailian5922.agy_go.phone.PhonePlugin
import io.github.kailian5922.agy_go.runtime.RuntimePlugin
import io.github.kailian5922.agy_go.system.SystemPlugin
import io.github.kailian5922.agy_go.voice.VoicePlugin

class MainActivity : FlutterActivity() {
    private var runtimePlugin: RuntimePlugin? = null
    private var phonePlugin: PhonePlugin? = null
    private var voicePlugin: VoicePlugin? = null
    private var petPlugin: PetPlugin? = null
    private var systemPlugin: SystemPlugin? = null
    private var hideStatusBar: Boolean = true
    private var keepScreenOn: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
        hideStatusBar = prefs.getBoolean(KEY_HIDE_STATUS_BAR, true)
        configureEdgeToEdge()
        applyStatusBarVisibility()
    }

    override fun onResume() {
        super.onResume()
        applyStatusBarVisibility()
        applyKeepScreenOn()
        // Re-check storage, AccessibilityService, Restricted Settings, overlay permissions, and Live Activity after returning from Settings.
        runtimePlugin?.onResume()
        phonePlugin?.onResume()
        petPlugin?.onResume()
        LiveActivity.refresh(applicationContext)
        intent?.getStringExtra(EXTRA_PREFILL_TEXT)?.let { text ->
            intent.removeExtra(EXTRA_PREFILL_TEXT)
            petPlugin?.deliverPrefillText(text)
        }
    }

    override fun onPause() {
        petPlugin?.onPause()
        super.onPause()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra(EXTRA_PREFILL_TEXT)?.let { text ->
            intent.removeExtra(EXTRA_PREFILL_TEXT)
            petPlugin?.deliverPrefillText(text)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyStatusBarVisibility()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        disposePlugins()
        runtimePlugin = RuntimePlugin(applicationContext, { this }, messenger)
        phonePlugin = PhonePlugin(applicationContext, messenger)
        voicePlugin = VoicePlugin(applicationContext, { this }, messenger)
        petPlugin = PetPlugin(applicationContext, messenger)
        intent?.getStringExtra(EXTRA_PREFILL_TEXT)?.let { text ->
            intent.removeExtra(EXTRA_PREFILL_TEXT)
            petPlugin?.deliverPrefillText(text)
        }
        systemPlugin = SystemPlugin(
            context = applicationContext,
            activityProvider = { this },
            messenger = messenger,
            onSetHideStatusBar = { enabled ->
                hideStatusBar = enabled
                getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(KEY_HIDE_STATUS_BAR, enabled)
                    .apply()
                applyStatusBarVisibility()
            },
            onSetKeepScreenOn = { enabled ->
                keepScreenOn = enabled
                applyKeepScreenOn()
            },
        )
    }

    private fun applyKeepScreenOn() {
        if (keepScreenOn) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (systemPlugin?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (runtimePlugin?.onRequestPermissionsResult(requestCode) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        disposePlugins()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun configureEdgeToEdge() {
        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
    }

    private fun applyStatusBarVisibility() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (hideStatusBar) {
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsets.Type.statusBars())
            } else {
                controller.show(WindowInsets.Type.statusBars())
            }
        } else {
            @Suppress("DEPRECATION")
            val baseFlags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (hideStatusBar) {
                baseFlags or View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            } else {
                baseFlags
            }
        }
    }

    private fun disposePlugins() {
        runtimePlugin?.dispose()
        phonePlugin?.dispose()
        voicePlugin?.dispose()
        petPlugin?.dispose()
        systemPlugin?.dispose()
        runtimePlugin = null
        phonePlugin = null
        voicePlugin = null
        petPlugin = null
        systemPlugin = null
    }

    companion object {
        const val EXTRA_PREFILL_TEXT = "agy_prefill_text"
        private const val UI_PREFS = "agy_ui_prefs"
        private const val KEY_HIDE_STATUS_BAR = "hide_status_bar"
    }
}
