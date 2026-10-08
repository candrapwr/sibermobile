/// Shell tools: run shell commands as the app's own (unprivileged) user.
///
/// Pure dart:io — no root and no native bridge needed. Android lets apps
/// exec system binaries such as sh, ls, ps, getprop or netstat. The command
/// runs with free access to everything the app user may read (no session
/// sandbox); the only walls are the OS ones: no root, no other apps' private
/// data, no system modifications.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../tool.dart';
import '../results.dart';

const int _maxCaptureBytes = 128 * 1024;
const int _maxOutputChars = 12000;

/// Runs a shell command via `sh -c` with a hard timeout.
class ShellExecTool extends Tool {
  @override
  String get name => 'shell_exec';

  @override
  String get description =>
      'Run any shell command on the device via `sh -c` and get back stdout, '
      'stderr, exit code and duration. Explore freely — you decide what to '
      'run; if a command fails, its error output comes back in the result. '
      'Runs unprivileged (no root). Use workingDir to pick the starting '
      'directory (default "/"); each call is its own shell, so cd only '
      'matters within a single command line. Commands that never exit are '
      'killed by the timeout (default 20s).';

  @override
  String get category => 'System';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'command': <String, dynamic>{
        'type': 'string',
        'description': 'The shell command line to execute, e.g. '
            '"getprop ro.build.version.release" or "cat /proc/cpuinfo".',
      },
      'workingDir': <String, dynamic>{
        'type': 'string',
        'description': 'Directory the command starts in (default "/"). Use '
            'any readable path; absolute paths work regardless.',
      },
      'timeoutSeconds': <String, dynamic>{
        'type': 'integer',
        'description': 'Hard timeout; the process is killed when it expires '
            '(default 20, max 60).',
      },
    },
    'required': <String>['command'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final command = requireString(args, 'command').trim();
    if (command.isEmpty) {
      return errorResult('command must not be empty.');
    }
    final timeoutSeconds =
        optionalInt(args, 'timeoutSeconds', 20).clamp(1, 60);
    final timeout = Duration(seconds: timeoutSeconds);

    // Free-range working directory: any readable path the model picks, no
    // session-sandbox scoping (the OS sandbox still applies, root or not).
    final workingDir = optionalString(args, 'workingDir')?.trim() ?? '/';

    final stopwatch = Stopwatch()..start();
    try {
      final process = await Process.start(
        'sh',
        ['-c', command],
        workingDirectory: workingDir,
      );

      // Start collecting before awaiting exit so output is not lost; each
      // stream is capped so a command spewing output cannot exhaust memory.
      final stdoutFuture = _cappedBytes(process.stdout);
      final stderrFuture = _cappedBytes(process.stderr);

      var timedOut = false;
      var exitCode = -1;
      try {
        exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
          process.kill();
          timedOut = true;
          return -1;
        });
      } on TimeoutException {
        timedOut = true;
      }

      final durationMs = stopwatch.elapsedMilliseconds;
      final stdoutText =
          utf8.decode(await stdoutFuture, allowMalformed: true);
      final stderrText =
          utf8.decode(await stderrFuture, allowMalformed: true);

      return jsonResult({
        'command': command,
        'exitCode': timedOut ? null : exitCode,
        'timedOut': timedOut,
        if (timedOut)
          'error': 'Command was killed after ${timeoutSeconds}s — likely an '
              'interactive command (top, vi, an endless loop).',
        'stdout': _clamp(stdoutText),
        'stdoutTruncated': stdoutText.length > _maxOutputChars,
        'stderr': _clamp(stderrText),
        'stderrTruncated': stderrText.length > _maxOutputChars,
        'durationMs': durationMs,
        'workingDir': workingDir,
      });
    } on ProcessException catch (e) {
      return errorResult(
        'Could not run the command: ${e.message}. Check that workingDir '
        'exists and is readable, and that this is an Android/sh environment.',
      );
    } catch (e) {
      return errorResult('shell_exec failed: $e');
    }
  }

  Future<List<int>> _cappedBytes(Stream<List<int>> stream) async {
    final out = <int>[];
    await for (final chunk in stream) {
      if (out.length >= _maxCaptureBytes) continue;
      final remaining = _maxCaptureBytes - out.length;
      out.addAll(chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
    }
    return out;
  }

  String _clamp(String text) =>
      text.length <= _maxOutputChars ? text : text.substring(0, _maxOutputChars);
}

final List<Tool> shellTools = <Tool>[ShellExecTool()];
