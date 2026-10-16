package com.idsiber.sibermobile

import android.content.Context
import android.os.Handler
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Text-to-speech module for the DeviceBridge channel. Keeps one engine
 * instance and resolves each speak call only when the utterance completes
 * (flutter_tts semantics: Flutter rate 0.5 == Android normal speed).
 */
internal class TtsModule(
    private val context: Context,
    private val mainHandler: Handler,
) {
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingSpeak: (() -> Unit)? = null
    private var speakResult: MethodChannel.Result? = null
    private var utteranceCounter = 0

    internal fun ensureTts() {
        if (tts != null) return
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            val pending = pendingSpeak
            pendingSpeak = null
            pending?.invoke()
        }.also { engine ->
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(utteranceId: String?) {
                    resolveSpeak(true)
                }

                override fun onError(utteranceId: String?) {
                    resolveSpeak(false)
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    resolveSpeak(false)
                }

                internal fun resolveSpeak(ok: Boolean) {
                    mainHandler.post {
                        speakResult?.success(ok)
                        speakResult = null
                    }
                }
            })
        }
    }

    /**
     * Speaks [text] and resolves the call only once the utterance finishes
     * (or fails / is stopped). Rate/pitch semantics follow flutter_tts: the
     * Flutter scale runs 0.0-1.0 with 0.5 == Android normal speed, and pitch
     * passes through unchanged.
     */
    internal fun ttsSpeak(
        text: String,
        language: String,
        rate: Float,
        pitch: Float,
        result: MethodChannel.Result,
    ) {
        ensureTts()
        val doSpeak: () -> Unit = doSpeak@{
            val engine = tts
            if (engine == null || !ttsReady) {
                mainHandler.post { result.success(false) }
                return@doSpeak
            }
            // Engines ignore unsupported languages; keep defaults like the
            // previous Dart-side try/catch did.
            try {
                engine.language = Locale.forLanguageTag(language)
            } catch (_: Exception) {}
            engine.setSpeechRate(rate * 2f)
            engine.setPitch(pitch)
            speakResult = result
            val id = "siber_tts_${++utteranceCounter}"
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        }
        if (ttsReady) {
            doSpeak()
        } else {
            pendingSpeak = doSpeak
        }
    }

    internal fun ttsStop(result: MethodChannel.Result) {
        try {
            tts?.stop()
        } catch (_: Exception) {}
        mainHandler.post {
            speakResult?.success(false)
            speakResult = null
            result.success(true)
        }
    }
}
