/// The provider contract used by the agent loop.
///
/// Defining a small interface (rather than binding the Agent to the concrete
/// HTTP class) keeps the agent unit-testable: tests supply a scripted provider
/// that replays canned [StreamEvent]s without touching the network.
library;

import 'types.dart';

/// A chat completion provider that speaks the OpenAI wire format.
abstract interface class ChatProvider {
  /// Default model id used when the agent does not override it.
  String get model;

  /// Streams one chat completion as incremental events, ending with a single
  /// [StreamDone] carrying the complete assistant message.
  Stream<StreamEvent> chatStream(ChatRequest request);

  /// Releases any resources held open (HTTP clients).
  void close();
}
