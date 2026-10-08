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
        imageGenModel: siberImageGenModel,
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

  test('generate_image posts the canonical sibergate body and saves b64',
      () async {
    final dir = await Directory.systemTemp.createTemp('imggen');
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
    );
    Uri? sentUrl;
    Map<String, String> sentHeaders = {};
    Object? sentBody;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/images/generations')) {
        sentUrl = request.url;
        sentHeaders = request.headers;
        sentBody = jsonDecode(request.body);
        return http.Response(
          jsonEncode({
            'created': 1,
            'data': [
              {
                'b64_json':
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
              },
            ],
          }),
          200,
        );
      }
      fail('unexpected request to ${request.url}');
    });

    final out = await GenerateImageTool(client: client).execute(
      {
        'prompt': 'Kucing astronot kartun',
        'outputPath': 'kucing',
        'resolution': '2k',
        'negative_prompt': 'blur',
      },
      gatewayContext(dir.path),
    );
    final res = jsonDecode(out) as Map<String, dynamic>;

    expect(res['ok'], isTrue);
    expect(res['path'], 'kucing.png');
    expect(res['mode'], 'generate');
    expect(res['bytes'], pngBytes.length);
    expect(File('${dir.path}/kucing.png').existsSync(), isTrue);
    expect(File('${dir.path}/kucing.png').readAsBytesSync(), pngBytes);

    expect(
      sentUrl.toString(),
      'https://api.idsiber.com/v1/images/generations',
    );
    expect(sentHeaders['authorization'], 'Bearer provider-key');
    final body = sentBody as Map<String, dynamic>;
    expect(body['model'], 'ds-imagen');
    expect(body['prompt'], 'Kucing astronot kartun');
    expect(body['n'], 1);
    expect(body['aspect_ratio'], '16:9');
    expect(body['resolution'], '2k');
    expect(body['negative_prompt'], 'blur');
    expect(body.containsKey('image'), isFalse);
  });

  test('generate_image downloads url results and infers the extension',
      () async {
    final dir = await Directory.systemTemp.createTemp('imggen-url');
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/images/generations')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'url': 'https://cdn.example.com/img/picture.webp'},
            ],
          }),
          200,
        );
      }
      if (request.url.host == 'cdn.example.com') {
        return http.Response.bytes([1, 2, 3, 4], 200);
      }
      fail('unexpected request to ${request.url}');
    });

    final out = await GenerateImageTool(client: client).execute(
      {'prompt': 'pemandangan'},
      gatewayContext(dir.path),
    );
    final res = jsonDecode(out) as Map<String, dynamic>;

    expect(res['ok'], isTrue);
    expect(res['path'], startsWith('generated-images/'));
    expect(res['path'], endsWith('.webp'));
    final saved = File('${dir.path}/${res['path']}');
    expect(saved.existsSync(), isTrue);
    expect(saved.readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('edit mode inlines the source image as a data URL', () async {
    final dir = await Directory.systemTemp.createTemp('imggen-edit');
    final uploads = Directory('${dir.path}/uploads')..createSync();
    final png = File('${uploads.path}/base.png');
    await png.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 1, 2]);

    Object? sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body);
      return http.Response(
        jsonEncode({
          'data': [
            {
              'b64_json':
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
            },
          ],
        }),
        200,
      );
    });

    final out = await GenerateImageTool(client: client).execute(
      {'prompt': 'buat versi malam', 'image': 'uploads/base.png'},
      gatewayContext(dir.path),
    );
    final res = jsonDecode(out) as Map<String, dynamic>;

    expect(res['mode'], 'edit');
    final image = (sentBody as Map)['image'] as String;
    expect(image, startsWith('data:image/png;base64,'));
  });

  test('generate_image without gateway config explains the restriction',
      () async {
    final out = await GenerateImageTool().execute(
      {'prompt': 'x'},
      ToolContext(workDir: '/tmp'),
    );
    expect(out, contains('idsiber.com'));
  });
}
