/// Minimal Server-Sent-Events parser for OpenAI-compatible chat streams.
///
/// Ported from siberflow's `packages/core/src/providers/sse.ts`: an SSE frame
/// is one or more `data:` lines terminated by a blank line; OpenAI ends the
/// stream with `data: [DONE]`.
library;

import 'dart:async';
import 'dart:convert';

/// Decodes a byte stream into SSE `data:` payloads (already `[DONE]`-filtered
/// and JSON-decoded).
///
/// [idleTimeout] aborts the stream when no bytes arrive for that long — some
/// gateways leave the HTTP stream open after their terminal chunk.
Stream<Map<String, dynamic>> parseSse(
  Stream<List<int>> bytes, {
  Duration idleTimeout = const Duration(seconds: 90),
  Duration initialTimeout = const Duration(seconds: 90),
  Duration Function()? idleTimeoutForNextData,
}) async* {
  final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
  final subscription = lines.listen(null);
  final controller = StreamController<String>();

  var firstEvent = true;
  Timer? timer;

  void scheduleTimeout() {
    timer?.cancel();
    final limit = firstEvent
        ? initialTimeout
        : (idleTimeoutForNextData?.call() ?? idleTimeout);
    timer = Timer(limit, () {
      if (!controller.isClosed) {
        controller.addError(
          TimeoutException('No data received from the model provider', limit),
        );
      }
    });
  }

  scheduleTimeout();

  subscription.onData((line) {
    firstEvent = false;
    scheduleTimeout();
    controller.add(line);
  });
  subscription.onError((Object e, StackTrace st) {
    timer?.cancel();
    controller.addError(e, st);
  });
  subscription.onDone(() {
    timer?.cancel();
    controller.close();
  });

  try {
    var buffer = <String>[];
    await for (final line in controller.stream) {
      if (line.isEmpty) {
        // Blank line = end of frame; emit the accumulated data lines.
        if (buffer.isNotEmpty) {
          final payload = buffer.join('\n');
          buffer = [];
          final decoded = _decodeData(payload);
          if (decoded == _done) return;
          if (decoded != null) {
            yield decoded;
            // The consumer may have learned from this frame that the stream
            // is terminal. Re-arm after yielding so a dynamic timeout callback
            // sees that state even when a whole SSE frame arrived in one byte
            // chunk (before the consumer processed it).
            scheduleTimeout();
          }
        }
        continue;
      }
      if (line.startsWith(':')) continue; // SSE comment / keep-alive
      if (line.startsWith('data:')) {
        buffer.add(line.substring(5).replaceFirst(RegExp(r'^\s'), ''));
        continue;
      }
      if (line.startsWith('event:') ||
          line.startsWith('id:') ||
          line.startsWith('retry:')) {
        continue;
      }
      // Bare line without a field name: treat as data (some gateways do this).
      buffer.add(line);
    }
    // Flush a trailing frame that was never terminated by a blank line.
    if (buffer.isNotEmpty) {
      final decoded = _decodeData(buffer.join('\n'));
      if (decoded != null && decoded != _done) {
        yield decoded;
        scheduleTimeout();
      }
    }
  } finally {
    timer?.cancel();
    await subscription.cancel();
    await controller.close();
  }
}

const Map<String, dynamic> _done = {'__sse_done__': true};

Map<String, dynamic>? _decodeData(String payload) {
  final text = payload.trim();
  if (text.isEmpty) return null;
  if (text == '[DONE]') return _done;
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
