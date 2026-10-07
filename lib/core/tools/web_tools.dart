/// Exa-compatible web search and page-content tools.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'results.dart';
import 'tool.dart';

const String defaultWebBaseUrl = 'https://api.exa.ai';
const int _searchResultCount = 5;
const int _defaultMaxCharacters = 500;
const int _maxMaxCharacters = 15000;
const int _maxOutputCharacters = 200000;
const Duration _requestTimeout = Duration(seconds: 120);

/// Searches the web and reads page contents through an Exa-compatible API.
///
/// The single tool mirrors siberflow's `web_search`: use `mode: "search"` to
/// discover URLs, then `mode: "content"` to read one result in detail.
class WebSearchTool extends Tool {
  WebSearchTool({http.Client? client}) : _client = client;

  final http.Client? _client;

  @override
  String get name => 'web_search';

  @override
  String get category => 'Network';

  @override
  String get description =>
      'Search the web and read page content through an Exa-compatible API. '
      'Use mode "search" with query to find current information and source '
      'URLs (up to 5 results). Use mode "content" with a URL from the search '
      'results, or a URL the user provides, to fetch readable page text. '
      'The configured endpoint may be api.exa.ai or a compatible proxy; the '
      'app appends /search and /contents automatically.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'mode': {
        'type': 'string',
        'enum': ['search', 'content'],
        'description':
            '"search" finds pages; "content" reads one URL in depth.',
      },
      'query': {'type': 'string', 'description': 'Required for mode "search".'},
      'url': {
        'type': 'string',
        'description': 'Required for mode "content"; must be http or https.',
      },
      'maxCharacters': {
        'type': 'integer',
        'description': 'Only for mode "content". Default 500, maximum 15000.',
        'minimum': 100,
        'maximum': _maxMaxCharacters,
      },
    },
    'required': ['mode'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final mode = requireString(args, 'mode').toLowerCase();
    final apiKey = ctx.webApiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      return errorResult(
        'Web search is not configured. Add an Exa API key in Settings.',
      );
    }

    final baseUrl = _normalizeBaseUrl(
      ctx.webBaseUrl.trim().isEmpty ? defaultWebBaseUrl : ctx.webBaseUrl,
    );
    final client = _client ?? http.Client();
    final closeClient = _client == null;
    try {
      switch (mode) {
        case 'search':
          final query = requireString(args, 'query').trim();
          return await _runSearch(client, baseUrl, apiKey, query);
        case 'content':
          final url = requireString(args, 'url').trim();
          _validateHttpUrl(url);
          final maxCharacters = optionalInt(
            args,
            'maxCharacters',
            _defaultMaxCharacters,
          ).clamp(100, _maxMaxCharacters);
          return await _runContent(client, baseUrl, apiKey, url, maxCharacters);
        default:
          return errorResult('`mode` must be either "search" or "content".');
      }
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<String> _runSearch(
    http.Client client,
    String baseUrl,
    String apiKey,
    String query,
  ) async {
    final json = await _postJson(client, '$baseUrl/search', apiKey, {
      'query': query,
      'numResults': _searchResultCount,
      'type': 'auto',
      'contents': {'highlights': true},
    });
    if (json['error'] != null || json['message'] != null) {
      return 'Error: web search failed: ${json['error'] ?? json['message'] ?? 'unknown error'}';
    }

    final rawResults = json['results'];
    final results = rawResults is List
        ? rawResults.whereType<Map>().toList(growable: false)
        : const <Map>[];
    if (results.isEmpty) return 'No results found for query: $query';

    final lines = <String>['Found ${results.length} result(s) for: $query', ''];
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      final title = _clean(result['title']) ?? '(untitled)';
      final url = _clean(result['url']) ?? _clean(result['id']) ?? '(no url)';
      lines
        ..add('${i + 1}. $title')
        ..add('   $url');
      final published = _clean(result['publishedDate']);
      final author = _clean(result['author']);
      if (published != null) lines.add('   published: $published');
      if (author != null) lines.add('   author: $author');
      final highlights = result['highlights'];
      if (highlights is List) {
        final joined = highlights
            .map((item) => item.toString())
            .join(' … ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (joined.isNotEmpty) {
          lines.add('   highlights: ${_truncate(joined, 400)}');
        }
      }
      lines.add('');
    }
    return _truncate(lines.join('\n').trim(), _maxOutputCharacters);
  }

  Future<String> _runContent(
    http.Client client,
    String baseUrl,
    String apiKey,
    String url,
    int maxCharacters,
  ) async {
    final json = await _postJson(client, '$baseUrl/contents', apiKey, {
      'ids': [url],
      'text': {'maxCharacters': maxCharacters},
    });
    if (json['error'] != null || json['message'] != null) {
      return 'Error: web content fetch failed: ${json['error'] ?? json['message'] ?? 'unknown error'}';
    }

    final statuses = json['statuses'];
    if (statuses is List) {
      final status = statuses.whereType<Map>().firstWhere(
        (item) => item['id']?.toString() == url,
        orElse: () => const <String, dynamic>{},
      );
      if (status.isNotEmpty && status['status']?.toString() != 'success') {
        final reason = _clean(status['reason']);
        return 'Error: could not fetch content for $url (status: ${status['status']}${reason == null ? '' : ' — $reason'}).';
      }
    }

    final rawResults = json['results'];
    final result = rawResults is List && rawResults.isNotEmpty
        ? rawResults.first
        : null;
    if (result is! Map) return 'Error: no content returned for $url.';

    final title = _clean(result['title']) ?? '(untitled)';
    final resultUrl = _clean(result['url']) ?? url;
    final text = _clean(result['text']) ?? '';
    if (text.isEmpty) {
      return 'Title: $title\nURL: $resultUrl\n\n(no readable text extracted from this page)';
    }
    return _truncate(
      'Title: $title\nURL: $resultUrl\n\n$text',
      _maxOutputCharacters,
    );
  }

  Future<Map<String, dynamic>> _postJson(
    http.Client client,
    String url,
    String apiKey,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await client
          .post(
            Uri.parse(url),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $apiKey',
              'x-api-key': apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
      final decoded = jsonDecode(response.body);
      final json = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'error':
              'HTTP ${response.statusCode}: ${json['error'] ?? json['message'] ?? response.reasonPhrase ?? 'request failed'}',
        };
      }
      return json;
    } on TimeoutException {
      return {'error': 'request timed out after 120s'};
    } catch (error) {
      return {'error': error.toString()};
    }
  }
}

String _normalizeBaseUrl(String raw) => raw.replaceFirst(RegExp(r'/+$'), '');

void _validateHttpUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    throw ArgumentError('`url` must start with http:// or https://');
  }
}

String? _clean(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _truncate(String text, int maxCharacters) {
  if (text.length <= maxCharacters) return text;
  return '${text.substring(0, maxCharacters)}\n... [truncated ${text.length - maxCharacters} chars]';
}

final List<Tool> webTools = <Tool>[WebSearchTool()];
