import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sibermobile/core/tools/http_tools.dart';
import 'package:sibermobile/core/tools/tool.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/echo') {
        final body = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'method': request.method,
            'contentType': request.headers.value('content-type'),
            'cookie': request.headers.value('cookie'),
            'authorization': request.headers.value('authorization'),
            'userAgent': request.headers.value('user-agent'),
            'body': body,
          }),
        );
      } else if (path == '/redirect') {
        await request.response.redirect(Uri(path: '/final'));
      } else if (path == '/final') {
        request.response.write('landed after redirect');
      } else if (path == '/notfound') {
        request.response.statusCode = 404;
        request.response.reasonPhrase = 'Not Found';
        request.response.write('tidak ada');
      } else if (path == '/cookie') {
        request.response.headers.set(
          'set-cookie',
          'session=abc123; Path=/; HttpOnly',
        );
        request.response.write('ok');
      } else if (path == '/binary') {
        request.response.headers.contentType = ContentType.parse(
          'application/octet-stream',
        );
        request.response.add(List.filled(128, 7));
      } else if (path == '/big') {
        request.response.write('x' * 5000);
      } else {
        request.response.statusCode = 400;
        request.response.write('unknown path');
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async {
    final out = await HttpRequestTool().execute(
      args,
      ToolContext(workDir: '/tmp'),
    );
    expect(out, isNot(startsWith('Error')));
    return jsonDecode(out) as Map<String, dynamic>;
  }

  test('GET returns status, headers and body', () async {
    final res = await run({'url': url('/echo')});

    expect(res['statusCode'], 200);
    expect(res['ok'], isTrue);
    expect(res['method'], 'GET');
    expect(res['contentType'], contains('json'));
    expect(res['elapsedMs'], isA<int>());
  });

  test('POST jsonBody sets content type and forwards the body', () async {
    final res = await run({
      'url': url('/echo'),
      'method': 'POST',
      'jsonBody': {'a': 1, 'b': 'x'},
      'headers': {'Authorization': 'Bearer tok'},
    });

    final body = jsonDecode(res['body'] as String) as Map<String, dynamic>;
    expect(body['method'], 'POST');
    expect(body['contentType'], startsWith('application/json'));
    expect(body['authorization'], 'Bearer tok');
    expect(body['body'], jsonEncode({'a': 1, 'b': 'x'}));
  });

  test('cookies parameter becomes the Cookie header', () async {
    final res = await run({
      'url': url('/echo'),
      'cookies': 'session=abc123; lang=id',
    });

    final body = jsonDecode(res['body'] as String) as Map<String, dynamic>;
    expect(body['cookie'], 'session=abc123; lang=id');
  });

  test('redirects are followed and reported', () async {
    final res = await run({'url': url('/redirect')});

    expect(res['statusCode'], 200);
    expect(res['body'], 'landed after redirect');
    expect(res['redirects'], hasLength(1));
    expect(
      (res['redirects'] as List).first['location'],
      contains('/final'),
    );
  });

  test('non-2xx status is returned, not an error', () async {
    final res = await run({'url': url('/notfound')});

    expect(res['statusCode'], 404);
    expect(res['ok'], isFalse);
    expect(res['body'], 'tidak ada');
  });

  test('server-set cookies are reported', () async {
    final res = await run({'url': url('/cookie')});

    expect(res['setCookie'], isNotEmpty);
    expect(
      (res['setCookie'] as List).first,
      contains('session=abc123'),
    );
  });

  test('binary bodies are reported by size, not dumped', () async {
    final res = await run({'url': url('/binary')});

    expect(res['binaryBody'], isTrue);
    expect(res['body'], isNull);
  });

  test('large text bodies are truncated with a flag', () async {
    final res = await run({
      'url': url('/big'),
      'maxResponseChars': 1000,
    });

    expect(res['bodyTruncated'], isTrue);
    expect((res['body'] as String).length, 1000);
    expect(res['totalBodyChars'], 5000);
  });

  test('default User-Agent looks like a modern browser and can be overridden',
      () async {
    final withDefault = await run({'url': url('/echo')});
    final echoed = jsonDecode(withDefault['body'] as String) as Map;
    expect(echoed['userAgent'], contains('Mozilla/5.0'));
    expect(echoed['userAgent'], contains('Chrome/'));
    expect(echoed['userAgent'], isNot(contains('Dart/')));

    final overridden = await run({
      'url': url('/echo'),
      'headers': {'User-Agent': 'SiberMobile/1.0'},
    });
    final echoed2 = jsonDecode(overridden['body'] as String) as Map;
    expect(echoed2['userAgent'], 'SiberMobile/1.0');
  });

  test('invalid URLs and schemes fail with clear messages', () async {
    final bad = await HttpRequestTool().execute(
      {'url': 'ftp://example.com/x'},
      ToolContext(workDir: '/tmp'),
    );
    expect(bad, contains('Only http:// and https://'));

    final malformed = await HttpRequestTool().execute(
      {'url': 'not a url'},
      ToolContext(workDir: '/tmp'),
    );
    expect(malformed, contains('not a valid URL'));
  });
}
