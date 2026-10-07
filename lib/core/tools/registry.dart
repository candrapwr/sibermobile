/// Tool registry: name → tool lookup plus schema export and safe execution.
///
/// Ported from siberflow's `packages/core/src/tools/registry.ts`.
library;

import 'dart:convert';

import '../ai/types.dart';
import 'tool.dart';

class ToolRegistry {
  final Map<String, Tool> _tools = {};

  void register(Tool tool) {
    _tools[tool.name] = tool;
  }

  void registerAll(Iterable<Tool> tools) {
    for (final t in tools) {
      register(t);
    }
  }

  List<Tool> list() => _tools.values.toList();

  List<String> get names => _tools.keys.toList();

  Tool? operator [](String name) => _tools[name];

  bool contains(String name) => _tools.containsKey(name);

  /// JSON schemas for the request's `tools` field.
  List<ToolSchema> schemas() => _tools.values.map((t) => t.schema).toList();

  /// Executes a tool by name, parsing its raw JSON arguments. Every failure
  /// path (unknown tool, bad JSON, thrown error) is returned as a string so the
  /// model can react instead of crashing the turn.
  Future<String> execute(String name, String rawArgs, ToolContext ctx) async {
    final tool = _tools[name];
    if (tool == null) return 'Error: tool "$name" not found';

    Map<String, dynamic> args;
    try {
      final trimmed = rawArgs.trim();
      if (trimmed.isEmpty) {
        args = const {};
      } else {
        final decoded = jsonDecode(trimmed);
        args = decoded is Map ? decoded.cast<String, dynamic>() : const {};
      }
    } catch (e) {
      return 'Error: invalid JSON arguments — $e';
    }

    try {
      // Tools flagged destructive (delete files or open system settings) ask
      // the host for explicit approval first. A null
      // requestApproval callback means approval is turned off in settings, so
      // the tool runs directly.
      if (tool.requiresApproval && ctx.requestApproval != null) {
        final approved = await ctx.requestApproval!(name, args);
        if (!approved) {
          return 'Error: the user declined to run "$name". Do not retry; ask '
              'what they would like to do instead.';
        }
      }
      return await tool.execute(args, ctx);
    } catch (e) {
      return toolError(e);
    }
  }
}
