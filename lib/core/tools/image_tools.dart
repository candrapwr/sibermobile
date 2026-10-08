/// Vision tools: image analysis through the Siber gateway's multimodal
/// OpenAI-compatible endpoint.
///
/// Mirrors siberflow's `analyze_image`: one user message with `text` +
/// `image_url` content parts, local images inlined as base64 data URLs.
/// This tool exists only for idsiber.com providers — no custom endpoint,
/// key or model: the provider settings are reused and the model is static
/// ([siberVisionModel]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../user_agent.dart';
import 'hardware/file_tools.dart';
import 'results.dart';
import 'tool.dart';

const int _maxImageBytes = 20 * 1024 * 1024;
const Duration _requestTimeout = Duration(seconds: 180);
// Generation (and edit) can take minutes when the gateway polls async
// upstream tasks — mirror helix_nebula's generous SiberGate budget.
const Duration _generateTimeout = Duration(seconds: 300);

/// Resolves an image input (workdir-relative path, https URL, or data URL)
/// into a request-safe value. Local sandbox files are inlined as base64
/// data URLs. Throws with a model-readable message.
Future<String> resolveImageSource(String image, ToolContext ctx) async {
  if (image.startsWith('data:image/')) return image;
  if (image.toLowerCase().startsWith('http://') ||
      image.toLowerCase().startsWith('https://')) {
    return image;
  }

  final path = resolveWithin(ctx.workDir, image);
  final file = File(path);
  if (!await file.exists()) {
    throw Exception(
      'Image not found: "$image" (local paths resolve inside the session '
      'work directory)',
    );
  }
  final length = await file.length();
  if (length > _maxImageBytes) {
    throw Exception(
      'Image is too large (${(length / 1024 / 1024).toStringAsFixed(1)} MB); '
      'the limit is 20 MB.',
    );
  }
  final bytes = await file.readAsBytes();
  return 'data:${mimeForPath(path)};base64,${base64Encode(bytes)}';
}

String mimeForPath(String path) {
  final ext = path.toLowerCase().split('.').last;
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/png';
  }
}

/// Analyzes an image with the gateway's vision model.
class AnalyzeImageTool extends Tool {
  AnalyzeImageTool({http.Client? client}) : _client = client;

  final http.Client? _client;

  @override
  String get name => 'analyze_image';

  @override
  String get category => 'Camera';

  @override
  String get description =>
      'Analyze an image with a vision model. Input `image` can be a local '
      'path inside the session sandbox (e.g. a photo from take_photo, like '
      '"uploads/photo.jpg"), an https image URL, or a data:image URL. Use '
      '`prompt` to say what you want: describe the image, read text (OCR), '
      'extract charts/tables, identify objects, or reason about what is '
      'visible. Only available when the provider is the Siber gateway '
      '(idsiber.com).';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'image': <String, dynamic>{
        'type': 'string',
        'description': 'Image path in the session sandbox, https URL, or '
            'data:image URL.',
      },
      'prompt': <String, dynamic>{
        'type': 'string',
        'description': 'What to do with the image, e.g. "Describe this '
            'image" or "Extract all text from this screenshot".',
      },
      'detail': <String, dynamic>{
        'type': 'string',
        'enum': <String>['low', 'high', 'auto'],
        'description': 'Image detail level for the vision model (default '
            'auto).',
      },
    },
    'required': <String>['image', 'prompt'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final image = requireString(args, 'image').trim();
    final prompt = requireString(args, 'prompt').trim();
    final detail = optionalString(args, 'detail') ?? 'auto';

    final baseUrl = ctx.visionBaseUrl.trim();
    final apiKey = ctx.visionApiKey?.trim() ?? '';
    final model = ctx.visionModel.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      return errorResult(
        'Image analysis is only available when the provider is the Siber '
        'gateway (a Base URL containing idsiber.com).',
      );
    }

    final String imageUrl;
    try {
      imageUrl = await resolveImageSource(image, ctx);
    } catch (e) {
      return errorResult(e.toString().replaceFirst('Exception: ', ''));
    }

    final client = _client ?? http.Client();
    final closeClient = _client == null;
    try {
      final response = await client
          .post(
            Uri.parse(
              '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}'
              '/chat/completions',
            ),
            headers: {
              'content-type': 'application/json',
              'user-agent': kDefaultUserAgent,
              'authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': prompt},
                    {
                      'type': 'image_url',
                      'image_url': {'url': imageUrl, 'detail': detail},
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(_requestTimeout);

      final decoded = jsonDecode(response.body);
      final json = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final err = json['error'];
        final message = err is Map && err['message'] != null
            ? err['message'].toString()
            : response.reasonPhrase ?? 'request failed';
        return errorResult(
          'Vision provider returned HTTP ${response.statusCode}: $message',
        );
      }

      final choices = json['choices'];
      final content = choices is List && choices.isNotEmpty
          ? (choices.first is Map ? choices.first['message'] : null)
          : null;
      final text = content is Map
          ? content['content']?.toString().trim()
          : null;
      if (text == null || text.isEmpty) {
        return errorResult('Vision provider returned no text content.');
      }
      return text;
    } catch (e) {
      return errorResult('Image analysis failed: $e');
    } finally {
      if (closeClient) client.close();
    }
  }
}

/// Generates (or edits) images through the Siber gateway's image endpoint.
///
/// Mirrors helix_nebula's `image_gen` sibergate adapter: one canonical JSON
/// call to `/images/generations` (the gateway maps it to the real vendor
/// server-side, including edit mode via the `image` data-URL field), and the
/// returned `url`/`b64_json` is written into the session workdir so it can be
/// handed to the user with `send_file_to_user`.
class GenerateImageTool extends Tool {
  GenerateImageTool({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const _aspectRatios = [
    '16:9', '9:16', '1:1', '4:3', '3:4', '3:2', '2:3', '21:9',
  ];

  @override
  String get name => 'generate_image';

  @override
  String get category => 'Camera';

  @override
  String get description =>
      'Generate an image from a text prompt, or edit an existing image, via '
      'the Siber gateway image model. The result is saved into the session '
      'working directory (default generated-images/<timestamp>-<slug>.png) — '
      'then offer it to the user with send_file_to_user using the returned '
      'relative path so it shows as an inline preview in the chat. '
      'Parameters: prompt (required, be descriptive); image (optional path '
      'inside the session sandbox to switch to edit mode); aspect_ratio '
      '(16:9 default, also 9:16, 1:1, 4:3, 3:4, 3:2, 2:3, 21:9); resolution '
      '(1k default, 2k only when the user asks for high quality); '
      'negative_prompt (things to avoid). Only available when the provider '
      'is the Siber gateway (idsiber.com). Generation can take up to a few '
      'minutes for complex prompts.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'prompt': <String, dynamic>{
        'type': 'string',
        'description': 'Detailed description of the image to generate, or '
            'the edit instruction when modifying an existing image.',
      },
      'image': <String, dynamic>{
        'type': 'string',
        'description': 'Path to a source image inside the session sandbox to '
            'edit (omit to generate a new image).',
      },
      'outputPath': <String, dynamic>{
        'type': 'string',
        'description': 'Output path inside the session workdir (e.g. '
            '"logo.png"). Defaults to generated-images/<timestamp>-<slug>.png.',
      },
      'aspect_ratio': <String, dynamic>{
        'type': 'string',
        'enum': _aspectRatios,
        'description': 'Image aspect ratio (default 16:9).',
      },
      'resolution': <String, dynamic>{
        'type': 'string',
        'enum': ['1k', '2k'],
        'description': 'Resolution tier; omit unless the user wants high '
            'quality (then 2k). Default 1k.',
      },
      'negative_prompt': <String, dynamic>{
        'type': 'string',
        'description': 'Things to avoid in the image (e.g. "blur, text, '
            'extra fingers").',
      },
    },
    'required': <String>['prompt'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final prompt = requireString(args, 'prompt').trim();
    final baseUrl = ctx.visionBaseUrl.trim();
    final apiKey = ctx.visionApiKey?.trim() ?? '';
    final model = ctx.imageGenModel.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      return errorResult(
        'Image generation is only available when the provider is the Siber '
        'gateway (a Base URL containing idsiber.com).',
      );
    }
    final aspect = optionalString(args, 'aspect_ratio')?.trim() ?? '16:9';
    if (!_aspectRatios.contains(aspect)) {
      return errorResult(
        'aspect_ratio must be one of: ${_aspectRatios.join(", ")}',
      );
    }
    final resolution = optionalString(args, 'resolution')?.trim();
    if (resolution != null && !['1k', '2k'].contains(resolution)) {
      return errorResult('resolution must be "1k" or "2k".');
    }
    final negativePrompt = optionalString(args, 'negative_prompt')?.trim();

    final client = _client ?? http.Client();
    final closeClient = _client == null;
    try {
      final body = <String, dynamic>{
        'model': model,
        'prompt': prompt,
        'n': 1,
        'aspect_ratio': aspect,
        if (resolution != null && resolution.isNotEmpty)
          'resolution': resolution,
        if (negativePrompt != null && negativePrompt.isNotEmpty)
          'negative_prompt': negativePrompt,
      };

      final sourceImage = optionalString(args, 'image')?.trim();
      final mode =
          sourceImage == null || sourceImage.isEmpty ? 'generate' : 'edit';
      if (sourceImage != null && sourceImage.isNotEmpty) {
        try {
          body['image'] = await resolveImageSource(sourceImage, ctx);
        } catch (e) {
          return errorResult(e.toString().replaceFirst('Exception: ', ''));
        }
      }

      final response = await client
          .post(
            Uri.parse(
              '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}'
              '/images/generations',
            ),
            headers: {
              'content-type': 'application/json',
              'user-agent': kDefaultUserAgent,
              'authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(_generateTimeout);

      final decoded = jsonDecode(response.body);
      final json = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final err = json['error'];
        final message = err is Map && err['message'] != null
            ? err['message'].toString()
            : response.reasonPhrase ?? 'request failed';
        return errorResult(
          'Image generation returned HTTP ${response.statusCode}: $message',
        );
      }

      final data = json['data'];
      final item = data is List && data.isNotEmpty && data.first is Map
          ? data.first as Map
          : null;
      if (item == null) {
        return errorResult('The gateway returned no image data.');
      }

      return await _saveResult(ctx, item, client, mode, model, prompt, args);
    } on TimeoutException {
      return errorResult(
        'Image generation timed out after 5 minutes — try a simpler prompt '
        'or a smaller resolution.',
      );
    } catch (e) {
      return errorResult('Image generation failed: $e');
    } finally {
      if (closeClient) client.close();
    }
  }

  /// Persists the returned image (`b64_json`, or downloads `url`) into the
  /// session workdir and summarizes it for the model.
  Future<String> _saveResult(
    ToolContext ctx,
    Map item,
    http.Client client,
    String mode,
    String model,
    String prompt,
    Map<String, dynamic> args,
  ) async {
    List<int> bytes;
    var format = 'png';
    final url = item['url']?.toString();
    final b64 = item['b64_json']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      bytes = base64Decode(b64);
    } else if (url != null && url.isNotEmpty) {
      final res = await client.get(Uri.parse(url)).timeout(_generateTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return errorResult(
          'The gateway returned an image URL but downloading it failed '
          '(HTTP ${res.statusCode}).',
        );
      }
      bytes = res.bodyBytes;
      final last = Uri.parse(url).pathSegments.lastOrNull;
      final ext = last != null && last.contains('.')
          ? last.split('.').last.toLowerCase()
          : null;
      if (ext != null && ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        format = ext == 'jpeg' ? 'jpg' : ext;
      }
    } else {
      return errorResult('The gateway returned no image url or b64_json.');
    }

    final requested = optionalString(args, 'outputPath')?.trim();
    final relative = _outputPath(requested, format, prompt);
    try {
      final abs = resolveWithin(ctx.workDir, relative);
      final file = File(abs);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return jsonResult({
        'ok': true,
        'mode': mode,
        'model': model,
        'path': relative,
        'bytes': bytes.length,
        'hint': 'Offer this image to the user via send_file_to_user with '
            'path "$relative" — it renders as an inline preview in the chat.',
      });
    } catch (e) {
      return errorResult('Could not save the generated image: $e');
    }
  }

  String _outputPath(String? requested, String format, String prompt) {
    var name = requested ?? '';
    if (name.isEmpty) {
      final slug = prompt
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final trimmedSlug = slug.length > 48 ? slug.substring(0, 48) : slug;
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      name =
          'generated-images/$stamp-${trimmedSlug.isEmpty ? 'image' : trimmedSlug}.'
          '$format';
    } else if (!name.contains('.')) {
      name = '$name.$format';
    }
    return name;
  }
}

final List<Tool> imageTools = <Tool>[AnalyzeImageTool(), GenerateImageTool()];
