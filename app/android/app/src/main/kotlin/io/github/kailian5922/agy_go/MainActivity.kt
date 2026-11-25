package io.github.kailian5922.agy_go

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.kailian5922.agy_go.runtime.RuntimePlugin

class MainActivity : FlutterActivity() {
    private var runtimePlugin: RuntimePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        runtimePlugin?.dispose()
        runtimePlugin = RuntimePlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        runtimePlugin?.dispose()
        runtimePlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
