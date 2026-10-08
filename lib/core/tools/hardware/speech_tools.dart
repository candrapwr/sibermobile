/// Speech tools: text-to-speech (speak aloud) and speech-to-text (dictation).
library;

import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import '../../native/device_bridge.dart';
import '../permissions.dart';
import '../tool.dart';
import '../results.dart';

/// Speaks text aloud through the device speaker. This produces audible output,
/// so it is flagged as requiring approval.
class SpeakTool extends Tool {
  @override
  String get name => 'speak_text';

  @override
  String get description =>
      'Speak the given text aloud through the device speaker using text-to-'
      'speech. Optionally set language (BCP-47, e.g. "id-ID" or "en-US"), '
      'rate (0.0-1.0, default 0.5) and pitch (0.5-2.0, default 1.0). '
      'Resolves once speaking finishes.';

  @override
  String get category => 'Speech';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'text': <String, dynamic>{
        'type': 'string',
        'description': 'The text to speak aloud.',
      },
      'language': <String, dynamic>{
        'type': 'string',
        'description': 'BCP-47 language tag, e.g. "id-ID" or "en-US".',
      },
      'rate': <String, dynamic>{
        'type': 'number',
        'description': 'Speech rate 0.0-1.0 (default 0.5).',
      },
      'pitch': <String, dynamic>{
        'type': 'number',
        'description': 'Voice pitch 0.5-2.0 (default 1.0).',
      },
    },
    'required': <String>['text'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final text = requireString(args, 'text');
    final language = optionalString(args, 'language') ?? 'id-ID';
    final rate = optionalDouble(args, 'rate', 0.5).clamp(0.0, 1.0);
    final pitch = optionalDouble(args, 'pitch', 1.0).clamp(0.5, 2.0);

    // DeviceBridge.speak keeps the native engine's language/rate/pitch per
    // call and blocks until the utterance completes.
    final ok = await DeviceBridge.speak(
      text: text,
      language: language,
      rate: rate,
      pitch: pitch,
    );
    return jsonResult({
      'ok': ok,
      'spoke': text.length,
      'language': language,
    });
  }
}

/// Stops any in-progress speech.
class StopSpeakingTool extends Tool {
  @override
  String get name => 'stop_speaking';

  @override
  String get description => 'Stop any text-to-speech audio currently playing.';

  @override
  String get category => 'Speech';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    await DeviceBridge.stopSpeaking();
    return jsonResult({'ok': true, 'stopped': true});
  }
}

/// Singleton STT engine.
final SpeechToText _stt = SpeechToText();

/// Listens to the microphone and returns the recognized text. Needs the
/// microphone permission; stops after [durationSeconds].
class ListenTool extends Tool {
  @override
  String get name => 'speech_to_text';

  @override
  String get description =>
      'Listen to the microphone and return what the user says as text '
      '(dictation). Requests the microphone permission. Set `durationSeconds` '
      '(default 15, max 60) for how long to listen, and `language` (default '
      '"id-ID"). Returns the final recognized words.';

  @override
  String get category => 'Speech';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'durationSeconds': <String, dynamic>{
        'type': 'integer',
        'description': 'How long to listen, in seconds (default 15, max 60).',
      },
      'language': <String, dynamic>{
        'type': 'string',
        'description': 'Locale to recognize, e.g. "id-ID" or "en-US".',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final micError = await ensureNamedPermission('microphone');
    if (micError != null) return errorResult(micError);

    final duration = optionalInt(args, 'durationSeconds', 15).clamp(1, 60);
    final language = optionalString(args, 'language') ?? 'id-ID';

    final initialized = await _stt.initialize();
    if (!initialized) {
      return errorResult('Speech recognition is not available on this device.');
    }

    final recognized = <String>[];
    final done = Completer<void>();
    late Timer stopTimer;

    final completer = Completer<String>();

    _stt.listen(
      onResult: (result) {
        if (result.recognizedWords.trim().isNotEmpty) {
          recognized.clear();
          recognized.add(result.recognizedWords.trim());
        }
        if (result.finalResult && !done.isCompleted) {
          done.complete();
        }
      },
      listenOptions: SpeechListenOptions(
        onDevice: false,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: language,
        listenFor: Duration(seconds: duration),
      ),
    );

    // Hard stop after the requested window.
    stopTimer = Timer(Duration(seconds: duration + 1), () {
      if (!done.isCompleted) done.complete();
    });

    await done.future;
    stopTimer.cancel();
    await _stt.stop();

    final text = recognized.isNotEmpty ? recognized.last : '';
    if (!completer.isCompleted) {
      completer.complete(text);
    }
    final transcript = await completer.future;
    return jsonResult({
      'transcript': transcript,
      'isEmpty': transcript.isEmpty,
      'language': language,
    });
  }
}

final List<Tool> speechTools = [SpeakTool(), StopSpeakingTool(), ListenTool()];
