package io.github.kailian5922.agy_go

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        disposePlugins()
        runtimePlugin = RuntimePlugin(applicationContext, messenger)
        phonePlugin = PhonePlugin(applicationContext, messenger)
        voicePlugin = VoicePlugin(applicationContext, { this }, messenger)
        petPlugin = PetPlugin(applicationContext, messenger)
        systemPlugin = SystemPlugin(applicationContext, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        disposePlugins()
        super.cleanUpFlutterEngine(flutterEngine)
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
}
