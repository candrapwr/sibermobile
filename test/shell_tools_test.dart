import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sibermobile/core/tools/hardware/shell_tools.dart';
import 'package:sibermobile/core/tools/tool.dart';

void main() {
  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async {
    final out = await ShellExecTool().execute(args, ToolContext(workDir: '/tmp'));
    expect(out, isNot(contains('"ok": false, "error": "Could not run')));
    return jsonDecode(out) as Map<String, dynamic>;
  }

  test('runs a command and reports stdout with exit code 0', () async {
    final res = await run({'command': 'echo hello-from-shell'});

    expect(res['exitCode'], 0);
    expect(res['timedOut'], isFalse);
    expect(res['stdout'].toString().trim(), 'hello-from-shell');
    expect(res['stderr'].toString().trim(), isEmpty);
    expect(res['durationMs'], isA<int>());
  });

  test('non-zero exit codes and stderr are surfaced', () async {
    final res = await run({'command': 'echo boom 1>&2; exit 3'});

    expect(res['exitCode'], 3);
    expect(res['stderr'].toString().trim(), 'boom');
  });

  test('commands past the timeout are killed and reported', () async {
    final res = await run({
      'command': 'sleep 30',
      'timeoutSeconds': 1,
    });

    expect(res['timedOut'], isTrue);
    expect(res['exitCode'], isNull);
    expect(res['error'].toString(), contains('killed'));
    expect(res['durationMs'] as int, lessThan(10000));
  });

  test('workingDir is free-range and defaults to the filesystem root',
      () async {
    final root = await run({'command': 'pwd'});
    expect(root['stdout'].toString().trim(), '/');
    expect(root['workingDir'], '/');

    final dir = await Directory.systemTemp.createTemp('shellcwd');
    final resolved = await dir.resolveSymbolicLinks();
    final there = await run({
      'command': 'pwd',
      'workingDir': dir.path,
    });
    expect(there['stdout'].toString().trim(), resolved);
  });

  test('huge output is capped instead of exhausting memory', () async {
    final res = await run({'command': 'yes 0123456789 | head -c 262144'});

    // 256KB produced, but only 128KB captured and 12k chars returned.
    expect(res['stdout'].toString().length, lessThanOrEqualTo(12000));
    expect(res['stdoutTruncated'], isTrue);
  });

  test('missing workingDir fails with a clear message', () async {
    final out = await ShellExecTool().execute(
      {'command': 'pwd', 'workingDir': '/no/such/dir'},
      ToolContext(workDir: '/tmp'),
    );
    expect(out, contains('Could not run the command'));
  });
}
