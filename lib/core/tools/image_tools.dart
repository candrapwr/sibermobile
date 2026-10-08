/// Vision tools: image analysis through the Siber gateway's multimodal
/// OpenAI-compatible endpoint.
///
/// Mirrors siberflow's `analyze_image`: one user message with `text` +
/// `image_url` content parts, local images inlined as base64 data URLs.
/// This tool exists only for idsiber.com providers — no custom endpoint,
/// key or model: the provider settings are reused and the model is static
/// ([siberVisionModel]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../user_agent.dart';
import 'hardware/file_tools.dart';
import 'results.dart';
import 'tool.dart';

const int _maxImageBytes = 20 * 1024 * 1024;
const Duration _requestTimeout = Duration(seconds: 180);

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
      imageUrl = await _resolveImageUrl(image, ctx);
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

  /// Local sandbox paths become base64 data URLs; http(s) and data: URLs
  /// pass through untouched (same rules as siberflow's analyze_image).
  Future<String> _resolveImageUrl(String image, ToolContext ctx) async {
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
    return 'data:${_mimeFor(path)};base64,${base64Encode(bytes)}';
  }

  String _mimeFor(String path) {
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
}

final List<Tool> imageTools = <Tool>[AnalyzeImageTool()];
