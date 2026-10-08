import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sibermobile/core/settings/settings.dart';
import 'package:sibermobile/core/tools/image_tools.dart';
import 'package:sibermobile/core/tools/tool.dart';

void main() {
  ToolContext gatewayContext(String workDir) => ToolContext(
        workDir: workDir,
        visionBaseUrl: 'https://api.idsiber.com/v1',
        visionApiKey: 'provider-key',
        visionModel: siberVisionModel,
      );

  test('builds the multimodal chat/completions request like siberflow',
      () async {
    Uri? sentUrl;
    Map<String, String> sentHeaders = {};
    Object? sentBody;

    final client = MockClient((request) async {
      sentUrl = request.url;
      sentHeaders = request.headers;
      sentBody = jsonDecode(request.body);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'Foto menampilkan seekor kucing oranye.',
              },
            },
          ],
        }),
        200,
      );
    });

    final out = await AnalyzeImageTool(client: client).execute(
      {
        'image': 'https://example.com/cat.jpg',
        'prompt': 'Describe this image',
      },
      gatewayContext('/tmp'),
    );

    expect(out, 'Foto menampilkan seekor kucing oranye.');
    expect(sentUrl.toString(), 'https://api.idsiber.com/v1/chat/completions');
    expect(sentHeaders['authorization'], 'Bearer provider-key');
    expect(sentHeaders['user-agent'], contains('Mozilla/5.0'));

    final body = sentBody as Map<String, dynamic>;
    expect(body['model'], 'ds-vision-flash');
    final content =
        ((body['messages'] as List).first as Map)['content'] as List;
    expect((content[0] as Map)['text'], 'Describe this image');
    final imageUrl = (content[1] as Map)['image_url'] as Map;
    expect(imageUrl['url'], 'https://example.com/cat.jpg');
    expect(imageUrl['detail'], 'auto');
  });

  test('local sandbox images are inlined as base64 data URLs', () async {
    final dir = await Directory.systemTemp.createTemp('vision');
    final uploads = Directory('${dir.path}${Platform.pathSeparator}uploads')
      ..createSync();
    final png = File('${uploads.path}${Platform.pathSeparator}photo.png');
    await png.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

    Object? capturedUrl;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final content =
          ((body['messages'] as List).first as Map)['content'] as List;
      capturedUrl =
          ((content[1] as Map)['image_url'] as Map)['url'];
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'ok'}},
          ],
        }),
        200,
      );
    });

    final out = await AnalyzeImageTool(client: client).execute(
      {'image': 'uploads/photo.png', 'prompt': 'apa ini?'},
      gatewayContext(dir.path),
    );

    expect(out, 'ok');
    expect(capturedUrl, startsWith('data:image/png;base64,'));
  });

  test('without gateway config the tool explains the restriction',
      () async {
    final out = await AnalyzeImageTool().execute(
      {'image': 'x.png', 'prompt': 'apa ini?'},
      ToolContext(workDir: '/tmp'),
    );
    expect(out, contains('idsiber.com'));
  });

  test('path escapes outside the sandbox are rejected', () async {
    final dir = await Directory.systemTemp.createTemp('vision-escape');
    final out = await AnalyzeImageTool(client: MockClient((r) async {
      fail('request should never be sent');
    })).execute(
      {'image': '../../etc/passwd.png', 'prompt': 'apa ini?'},
      gatewayContext(dir.path),
    );
    expect(out, contains('resolves outside the session directory'));
  });

  test('missing files and provider errors are reported clearly', () async {
    final dir = await Directory.systemTemp.createTemp('vision-missing');
    final missing = await AnalyzeImageTool().execute(
      {'image': 'uploads/nope.png', 'prompt': 'apa ini?'},
      gatewayContext(dir.path),
    );
    expect(missing, contains('Image not found'));

    final failing = AnalyzeImageTool(
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({'error': {'message': 'model overloaded'}}),
          503,
        ),
      ),
    );
    final err = await failing.execute(
      {'image': 'https://x/y.png', 'prompt': 'apa ini?'},
      gatewayContext('/tmp'),
    );
    expect(err, contains('503'));
    expect(err, contains('model overloaded'));
  });
}
