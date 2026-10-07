/// Shared helpers for building tool result strings.
///
/// Every tool returns a String for the model. Returning compact JSON keeps
/// results easy for the model to parse and avoids prose that could be
/// mistaken for device facts.
library;

import 'dart:convert';

import 'tool.dart';

/// Renders a map as pretty JSON, truncating to [truncateResult]'s cap so one
/// huge tool call cannot blow up the context window.
String jsonResult(Map<String, dynamic> data) =>
    truncateResult(const JsonEncoder.withIndent('  ').convert(data));

/// Renders a JSON list with the same truncation policy.
String jsonListResult(List<dynamic> data) =>
    truncateResult(const JsonEncoder.withIndent('  ').convert(data));

/// Renders a single-line error result the model can react to.
String errorResult(String message) =>
    jsonResult({'ok': false, 'error': message});

/// Rounds a double for display so results stay readable.
double round2(double v) => double.parse(v.toStringAsFixed(2));

/// Rounds to 3 decimals for compact numeric tool results.
double round3(double v) => double.parse(v.toStringAsFixed(3));

/// Reads a value from the parsed argument map, returning a model-readable
/// error when a required key is missing.
T requireArg<T>(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is T) return value;
  throw ArgumentError('`$key` is required and must be of type ${T.toString()}');
}
