package io.github.kailian5922.agy_go.voice

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

/**
 * Native Android speech-to-text (SpeechRecognizer) and text-to-speech (TextToSpeech) plugin.
 */
class VoicePlugin(
    private val context: Context,
    private val activityProvider: () -> Activity?,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    @Volatile private var eventSink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    @Volatile private var ttsReady = false
    @Volatile private var isListening = false

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                val stt = SpeechRecognizer.isRecognitionAvailable(context)
                result.success(mapOf("stt" to stt, "tts" to true))
            }
            "startListening" -> {
                val localeTag = call.argument<String>("locale") ?: Locale.getDefault().toLanguageTag()
                mainHandler.post { startListeningInternal(localeTag, result) }
            }
            "stopListening" -> {
                mainHandler.post {
                    try {
                        recognizer?.stopListening()
                    } catch (_: Throwable) {}
                    isListening = false
                    emit(mapOf("type" to "listening", "active" to false))
                    result.success(null)
                }
            }
            "speak" -> {
                val text = call.argument<String>("text") ?: ""
                val localeTag = call.argument<String>("locale")
                mainHandler.post { speakInternal(text, localeTag) }
                result.success(null)
            }
            "stopSpeaking" -> {
                mainHandler.post {
                    try {
                        tts?.stop()
                    } catch (_: Throwable) {}
                    emit(mapOf("type" to "ttsDone"))
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startListeningInternal(localeTag: String, result: MethodChannel.Result) {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            val activity = activityProvider()
            if (activity != null) {
                activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_RECORD_AUDIO)
                result.error("PERMISSION_REQUIRED", "已请求麦克风权限，允许后请再次点击语音按钮。", null)
            } else {
                result.error("PERMISSION_DENIED", "缺少麦克风权限 (RECORD_AUDIO)。", null)
            }
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            result.error("STT_UNAVAILABLE", "当前系统未安装可用的语音识别服务。", null)
            return
        }

        try {
            recognizer?.destroy()
            val sr = SpeechRecognizer.createSpeechRecognizer(context)
            recognizer = sr
            sr.setRecognitionListener(
                object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        isListening = true
                        emit(mapOf("type" to "listening", "active" to true))
                    }

                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {
                        emit(mapOf("type" to "rms", "value" to rmsdB.toDouble()))
                    }

                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {
                        isListening = false
                        emit(mapOf("type" to "listening", "active" to false))
                    }

                    override fun onError(error: Int) {
                        isListening = false
                        emit(mapOf("type" to "listening", "active" to false))
                        emit(mapOf("type" to "error", "code" to error, "message" to errorMessage(error)))
                    }

                    override fun onResults(results: Bundle?) {
                        isListening = false
                        val text = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            .orEmpty()
                        emit(mapOf("type" to "listening", "active" to false))
                        if (text.isNotEmpty()) {
                            emit(mapOf("type" to "final", "text" to text))
                        }
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val text = partialResults
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            .orEmpty()
                        if (text.isNotEmpty()) {
                            emit(mapOf("type" to "partial", "text" to text))
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                },
            )

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
            sr.startListening(intent)
            result.success(true)
        } catch (e: Throwable) {
            result.error("STT_FAILED", e.message, null)
        }
    }

    private fun speakInternal(text: String, localeTag: String?) {
        if (text.isBlank()) return
        val clean = text
            .replace(Regex("```[\\s\\S]*?```"), "（代码块略）")
            .replace(Regex("[`*_#>]"), "")
            .take(3500)

        fun doSpeak(engine: TextToSpeech) {
            if (!localeTag.isNullOrBlank()) {
                engine.language = Locale.forLanguageTag(localeTag)
            }
            val uid = UUID.randomUUID().toString()
            engine.speak(clean, TextToSpeech.QUEUE_FLUSH, null, uid)
        }

        val existing = tts
        if (existing != null && ttsReady) {
            doSpeak(existing)
            return
        }

        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                tts?.setOnUtteranceProgressListener(
                    object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            emit(mapOf("type" to "ttsStart"))
                        }

                        override fun onDone(utteranceId: String?) {
                            emit(mapOf("type" to "ttsDone"))
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            emit(mapOf("type" to "ttsDone"))
                        }
                    },
                )
                tts?.let { doSpeak(it) }
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(event: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(event)
            } catch (_: Throwable) {}
        }
    }

    private fun errorMessage(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "音频录制失败"
        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "语音识别网络超时"
        SpeechRecognizer.ERROR_NO_MATCH -> "未识别到清晰语音"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "长时间未检测到说话"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "缺少麦克风权限"
        else -> "语音识别错误 ($code)"
    }

    fun dispose() {
        mainHandler.post {
            try {
                recognizer?.destroy()
            } catch (_: Throwable) {}
            try {
                tts?.shutdown()
            } catch (_: Throwable) {}
            recognizer = null
            tts = null
        }
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    companion object {
        const val METHOD_CHANNEL = "agy/voice"
        const val EVENT_CHANNEL = "agy/voice/events"
        private const val REQ_RECORD_AUDIO = 4201
    }
}
