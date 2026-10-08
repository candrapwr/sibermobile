/// HTTP tools: a curl-like raw request primitive over dart:io HttpClient.
///
/// No plugin and no platform channel — dart:io runs natively in the VM. The
/// tool is deliberately generic (method, URL, headers, cookies, body) so the
/// model can talk to any HTTP API the user asks about.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'tool.dart';
import 'results.dart';
import '../user_agent.dart';

/// Performs a raw HTTP(S) request and reports the full response.
class HttpRequestTool extends Tool {
  HttpRequestTool();

  @override
  String get name => 'http_request';

  @override
  String get description =>
      'Make a raw HTTP(S) request to any URL — like a small curl. Choose the '
      'method (GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS), set arbitrary headers '
      '(e.g. Authorization), cookies (as "name=value; name2=value2") and a '
      'body (raw text or `jsonBody` object), control redirects and timeout. '
      'Returns status code and reason, all response headers, cookies set by '
      'the server, the redirect chain, the response body (text, capped by '
      'maxResponseChars; binary bodies are reported by size only) and the '
      'elapsed time. Prefer https://; plain http:// is unencrypted — only '
      'use it for local gateways. Only contact URLs the user asked about and '
      'never send secrets to hosts you do not trust.';

  @override
  String get category => 'Network';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'url': <String, dynamic>{
        'type': 'string',
        'description': 'Full URL including scheme, e.g. '
            '"https://api.example.com/v1/ping?a=1".',
      },
      'method': <String, dynamic>{
        'type': 'string',
        'enum': <String>[
          'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS',
        ],
        'description': 'HTTP method (default GET).',
      },
      'headers': <String, dynamic>{
        'type': 'object',
        'description':
            'Request headers as an object, e.g. {"Authorization": '
            '"Bearer ...", "Accept": "application/json"}.',
      },
      'cookies': <String, dynamic>{
        'type': 'string',
        'description': 'Cookie header value: "name=value; name2=value2".',
      },
      'body': <String, dynamic>{
        'type': 'string',
        'description':
            'Raw request body for POST/PUT/PATCH. Set the Content-Type '
            'header yourself when using this.',
      },
      'jsonBody': <String, dynamic>{
        'type': 'object',
        'description':
            'JSON request body (object). Sent as application/json; do not '
            'combine with body.',
      },
      'timeoutSeconds': <String, dynamic>{
        'type': 'integer',
        'description': 'Overall timeout in seconds (default 20, max 60).',
      },
      'followRedirects': <String, dynamic>{
        'type': 'boolean',
        'description': 'Follow 3xx redirects (default true).',
      },
      'maxResponseChars': <String, dynamic>{
        'type': 'integer',
        'description':
            'Cap for the returned body text (default 8000, max 20000).',
      },
    },
    'required': <String>['url'],
    'additionalProperties': false,
  };

  static const int _maxCollectBytes = 2 * 1024 * 1024;

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final url = requireString(args, 'url').trim();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return errorResult('url "$url" is not a valid URL.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return errorResult(
        'Only http:// and https:// URLs are supported (got "${uri.scheme}").',
      );
    }

    final method = (optionalString(args, 'method') ?? 'GET').toUpperCase();
    const allowedMethods = {
      'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS',
    };
    if (!allowedMethods.contains(method)) {
      return errorResult('Unsupported method "$method".');
    }

    final headersArg = args['headers'];
    if (headersArg != null && headersArg is! Map) {
      return errorResult('headers must be an object of name → value.');
    }
    final cookies = optionalString(args, 'cookies');
    var body = optionalString(args, 'body');
    final jsonBody = args['jsonBody'];
    if (jsonBody != null && jsonBody is! Map) {
      return errorResult('jsonBody must be an object.');
    }
    if (body != null && jsonBody != null) {
      return errorResult('Use either body or jsonBody, not both.');
    }

    final timeoutSeconds = optionalInt(args, 'timeoutSeconds', 20).clamp(1, 60);
    final followRedirects = optionalBool(args, 'followRedirects', true);
    final maxChars = optionalInt(args, 'maxResponseChars', 8000)
        .clamp(100, 20000);
    final timeout = Duration(seconds: timeoutSeconds);

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = true;

    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(timeout, onTimeout: () {
        throw TimeoutException('connection timed out', timeout);
      });
      // dart:io rejects redirect loops on its own; no explicit cap needed.
      request.followRedirects = followRedirects;

      if (headersArg is Map) {
        headersArg.forEach((name, value) {
          if (name != null && value != null) {
            request.headers.set(name.toString(), value.toString());
          }
        });
      }
      if (cookies != null && cookies.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookies);
      }
      // Present as a modern browser unless the caller set their own agent.
      // dart:io pre-fills the header with "Dart/x.y (dart:io)", so that
      // default counts as "not set".
      final currentAgent = request.headers.value(HttpHeaders.userAgentHeader);
      if (currentAgent == null || currentAgent.startsWith('Dart/')) {
        request.headers.set(HttpHeaders.userAgentHeader, kDefaultUserAgent);
      }
      if (jsonBody != null) {
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
        body = jsonEncode(jsonBody);
      }

      // contentLength must precede the payload: without it the request goes
      // out chunked, which some servers reject.
      final hasBody =
          body != null && body.isNotEmpty && method != 'GET' && method != 'HEAD';
      if (hasBody) {
        final bodyBytes = utf8.encode(body);
        request.contentLength = bodyBytes.length;
        request.add(bodyBytes);
      } else {
        request.contentLength = 0;
      }

      final response = await request.close().timeout(timeout, onTimeout: () {
        throw TimeoutException(
          'no response within ${timeoutSeconds}s',
          timeout,
        );
      });

      Future<BytesBuilder> collectBody() async {
        final builder = BytesBuilder(copy: false);
        // Cap the collected body so a huge response cannot exhaust memory;
        // the rest of the stream is drained to finish the response.
        await for (final chunk in response) {
          if (builder.length < _maxCollectBytes) builder.add(chunk);
        }
        return builder;
      }
      final builder = await collectBody().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'response body stalled for ${timeoutSeconds}s',
          timeout,
        ),
      );

      final elapsedMs = stopwatch.elapsedMilliseconds;
      final outHeaders = <String, dynamic>{};
      response.headers.forEach((name, values) {
        outHeaders[name] = values.length == 1 ? values.first : values;
      });

      final contentType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      final isText = _looksLikeText(contentType);
      String? text;
      var truncated = false;
      var totalChars = 0;
      if (isText && method != 'HEAD' && builder.isNotEmpty) {
        final full = utf8.decode(builder.takeBytes(), allowMalformed: true);
        totalChars = full.length;
        if (full.length > maxChars) {
          text = full.substring(0, maxChars);
          truncated = true;
        } else {
          text = full;
        }
      }

      return jsonResult({
        'url': url,
        'method': method,
        'statusCode': response.statusCode,
        'reasonPhrase': response.reasonPhrase,
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'responseHeaders': outHeaders,
        'setCookie': response.headers[HttpHeaders.setCookieHeader] ?? [],
        'redirects': [
          for (final r in response.redirects)
            {'statusCode': r.statusCode, 'location': r.location.toString()},
        ],
        'contentType': contentType.isEmpty ? null : contentType,
        'body': text,
        'bodyTruncated': truncated,
        'totalBodyChars': totalChars,
        'binaryBody': isText ? null : true,
        'elapsedMs': elapsedMs,
      });
    } on TimeoutException catch (e) {
      return errorResult('Request timed out: ${e.message}');
    } on HandshakeException catch (e) {
      return errorResult('TLS handshake failed: ${e.message}');
    } on SocketException catch (e) {
      return errorResult('Network error: ${e.message}');
    } on HttpException catch (e) {
      return errorResult('HTTP error: ${e.message}');
    } catch (e) {
      return errorResult('Request failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Responses worth returning as text: anything explicitly textual, JSON,
  /// XML, HTML, scripts and forms. Everything else (images, archives, …) is
  /// reported by size only.
  bool _looksLikeText(String contentType) {
    final ct = contentType.toLowerCase();
    if (ct.startsWith('text/')) return true;
    return [
      'json', 'xml', 'html', 'javascript', 'ecmascript', 'urlencoded',
      'csv', 'yaml', 'x-www-form',
    ].any(ct.contains);
  }
}

final List<Tool> httpTools = [HttpRequestTool()];
