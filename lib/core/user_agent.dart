/// Shared outbound User-Agent.
///
/// dart:io's default agent ("Dart/x.y (dart:io)") gets blocked outright by
/// many gateways and CDNs, so every HTTP client in the app — the AI provider,
/// web search and the http_request tool — presents itself as a modern mobile
/// browser instead. Callers can always override it per request.
const String kDefaultUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36';
