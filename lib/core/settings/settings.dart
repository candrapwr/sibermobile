/// App settings: the single custom OpenAI-compatible provider plus agent
/// behaviour. Persisted as JSON in shared_preferences; the API key is stored
/// separately in flutter_secure_storage (EncryptedSharedPreferences).
///
/// Mirrors the desktop `customProvider` settings shape: base URL, model, key.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the settings JSON blob lives.
const String _settingsKey = 'sibermobile.settings.v1';

/// Where the API key lives (secure storage), keyed by provider — here only one.
const String _apiKeyKey = 'custom';
const String _webApiKeyKey = 'exa';

/// Static Exa-compatible endpoint used when the provider itself is the
/// Siber gateway. The provider API key doubles as the web search token, so
/// no separate web search configuration is needed in that mode.
const String siberWebSearchBaseUrl = 'https://api.idsiber.com/v1/generic/exa';

/// Static multimodal model used by the built-in image analysis tool when the
/// provider is the Siber gateway.
const String siberVisionModel = 'ds-vision-flash';
const String defaultWebBaseUrl = 'https://api.exa.ai';

/// Reasoning-effort values forwarded to gateways that understand the field.
enum ReasoningEffort { none, minimal, low, medium, high }

/// Theme preference persisted independently from the Android system theme.
enum AppThemeMode { system, light, dark }

/// Default maximum output size for a provider call when the user has not
/// entered a custom value.
const int defaultMaxTokens = 50000;

/// Optional tools that start disabled until the user turns them on in the
/// Tools screen. Keeping heavy device tools out of the default registry
/// keeps the tool schema — and therefore every request's token cost — small.
/// Note: web_search is NOT here — with the Siber gateway it should work out
/// of the box, and elsewhere it is gated by its own configuration anyway.
const Set<String> defaultDisabledTools = {
  // Device & battery info.
  'get_device_info',
  'get_storage_info',
  'get_app_info',
  'battery_status',
  // Camera & speech.
  'take_photo',
  'pick_gallery_image',
  'speak_text',
  'stop_speaking',
  'speech_to_text',
  // Installed apps.
  'list_installed_apps',
  'launch_app',
  // Network analysis.
  'wifi_scan',
  'cell_scan',
  'net_probe',
  // NFC.
  'nfc_status',
  'nfc_analyze',
  'nfc_transceive',
  'nfc_write_ndef',
  // Shell (power tool).
  'shell_exec',
};

class AppSettings {
  AppSettings({
    this.baseUrl = '',
    this.model = '',
    this.webBaseUrl = defaultWebBaseUrl,
    this.temperature = 0.7,
    this.maxTokens = defaultMaxTokens,
    this.maxTokensCustomized = false,
    this.maxIterations = 25,
    this.includeUsageInStream = true,
    this.sendReasoningEffort = false,
    this.reasoningEffort = ReasoningEffort.medium,
    this.autoContinue = true,
    this.compactContext = true,
    this.contextWindow = 200000,
    this.compactThreshold = 0.8,
    this.compactKeepRecent = 2,
    this.themeMode = AppThemeMode.system,
    this.approveDestructiveTools = true,
    this.disabledTools = defaultDisabledTools,
    this.sessionName = '',
  });

  /// Base URL of the OpenAI-compatible gateway, e.g. `https://api.example.com/v1`.
  String baseUrl;

  /// Model id sent in the request's `model` field.
  String model;

  /// Exa-compatible web search endpoint. `/search` and `/contents` are added
  /// automatically by the web tool.
  String webBaseUrl;

  /// True when the provider is the Siber gateway (idsiber.com): built-in
  /// extras (web search via [siberWebSearchBaseUrl], image analysis via
  /// [siberVisionModel]) then run automatically with the provider API key —
  /// no separate configuration needed.
  bool get usesSiberGateway =>
      baseUrl.toLowerCase().contains('idsiber.com');

  double temperature;
  int maxTokens;

  /// Distinguishes an intentional legacy value of 4096 from the old default.
  bool maxTokensCustomized;
  int maxIterations;
  bool includeUsageInStream;

  /// When true, add `reasoning_effort` to the request body. Off by default
  /// because many gateways reject the unknown field.
  bool sendReasoningEffort;
  ReasoningEffort reasoningEffort;

  bool autoContinue;

  /// Roll older completed turns into an AI summary when the prompt reaches a
  /// configurable portion of the provider context window.
  bool compactContext;
  int contextWindow;
  double compactThreshold;
  int compactKeepRecent;

  /// Whether the UI follows the device, stays light, or stays dark.
  AppThemeMode themeMode;

  /// Require explicit user approval before running tools flagged destructive.
  bool approveDestructiveTools;

  /// Set of tool names the user turned OFF. Empty = everything registered is
  /// enabled. New installs keep `web_search` here until its credentials are
  /// configured, so an optional network capability never activates by surprise.
  Set<String> disabledTools;

  String sessionName;

  AppSettings copyWith({
    String? baseUrl,
    String? model,
    String? webBaseUrl,
    double? temperature,
    int? maxTokens,
    bool? maxTokensCustomized,
    int? maxIterations,
    bool? includeUsageInStream,
    bool? sendReasoningEffort,
    ReasoningEffort? reasoningEffort,
    bool? autoContinue,
    bool? compactContext,
    int? contextWindow,
    double? compactThreshold,
    int? compactKeepRecent,
    AppThemeMode? themeMode,
    bool? approveDestructiveTools,
    Set<String>? disabledTools,
    String? sessionName,
  }) => AppSettings(
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    webBaseUrl: webBaseUrl ?? this.webBaseUrl,
    temperature: temperature ?? this.temperature,
    maxTokens: maxTokens ?? this.maxTokens,
    maxTokensCustomized: maxTokensCustomized ?? this.maxTokensCustomized,
    maxIterations: maxIterations ?? this.maxIterations,
    includeUsageInStream: includeUsageInStream ?? this.includeUsageInStream,
    sendReasoningEffort: sendReasoningEffort ?? this.sendReasoningEffort,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    autoContinue: autoContinue ?? this.autoContinue,
    compactContext: compactContext ?? this.compactContext,
    contextWindow: contextWindow ?? this.contextWindow,
    compactThreshold: compactThreshold ?? this.compactThreshold,
    compactKeepRecent: compactKeepRecent ?? this.compactKeepRecent,
    themeMode: themeMode ?? this.themeMode,
    approveDestructiveTools:
        approveDestructiveTools ?? this.approveDestructiveTools,
    disabledTools: disabledTools ?? this.disabledTools,
    sessionName: sessionName ?? this.sessionName,
  );

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'webBaseUrl': webBaseUrl,
    'temperature': temperature,
    'maxTokens': maxTokens,
    'maxTokensCustomized': maxTokensCustomized,
    'maxIterations': maxIterations,
    'includeUsageInStream': includeUsageInStream,
    'sendReasoningEffort': sendReasoningEffort,
    'reasoningEffort': reasoningEffort.name,
    'autoContinue': autoContinue,
    'compactContext': compactContext,
    'contextWindow': contextWindow,
    'compactThreshold': compactThreshold,
    'compactKeepRecent': compactKeepRecent,
    'themeMode': themeMode.name,
    'approveDestructiveTools': approveDestructiveTools,
    'disabledTools': disabledTools.toList(),
    'sessionName': sessionName,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    baseUrl: json['baseUrl']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    webBaseUrl: json['webBaseUrl']?.toString() ?? defaultWebBaseUrl,
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    maxTokens: _maxTokensFrom(json),
    maxTokensCustomized: _maxTokensCustomizedFrom(json),
    maxIterations: (json['maxIterations'] as num?)?.toInt() ?? 25,
    includeUsageInStream: json['includeUsageInStream'] as bool? ?? true,
    sendReasoningEffort: json['sendReasoningEffort'] as bool? ?? false,
    reasoningEffort: ReasoningEffort.values.firstWhere(
      (e) => e.name == json['reasoningEffort'],
      orElse: () => ReasoningEffort.medium,
    ),
    autoContinue: json['autoContinue'] as bool? ?? true,
    compactContext: json['compactContext'] as bool? ?? true,
    contextWindow: _contextWindowFrom(json['contextWindow']),
    compactThreshold: _thresholdFrom(json['compactThreshold']),
    compactKeepRecent: _keepRecentFrom(json['compactKeepRecent']),
    themeMode: AppThemeMode.values.firstWhere(
      (mode) => mode.name == json['themeMode'],
      orElse: () => AppThemeMode.system,
    ),
    approveDestructiveTools: json['approveDestructiveTools'] as bool? ?? true,
    disabledTools:
        (json['disabledTools'] as List?)?.map((e) => e.toString()).toSet() ??
        defaultDisabledTools,
    sessionName: json['sessionName']?.toString() ?? '',
  );

  static int _contextWindowFrom(Object? value) {
    final tokens = (value as num?)?.toInt() ?? 200000;
    return tokens.clamp(1000, 2000000).toInt();
  }

  static int _maxTokensFrom(Map<String, dynamic> json) {
    final value = (json['maxTokens'] as num?)?.toInt();
    if (value == null) return defaultMaxTokens;
    // 4096 was the previous default. Old settings have no way to distinguish
    // that default from a deliberate choice, so treat it as default unless the
    // new explicit marker says the user customized it.
    if (value == 4096 && json['maxTokensCustomized'] != true) {
      return defaultMaxTokens;
    }
    return value;
  }

  static bool _maxTokensCustomizedFrom(Map<String, dynamic> json) {
    final value = (json['maxTokens'] as num?)?.toInt();
    if (json['maxTokensCustomized'] is bool) {
      return json['maxTokensCustomized'] as bool;
    }
    return value != null && value != 4096;
  }

  static double _thresholdFrom(Object? value) {
    final ratio = (value as num?)?.toDouble() ?? 0.8;
    return ratio.clamp(0.1, 1.0).toDouble();
  }

  static int _keepRecentFrom(Object? value) {
    final turns = (value as num?)?.toInt() ?? 2;
    return turns.clamp(0, 20).toInt();
  }
}

/// Loads/saves [AppSettings] and the API key.
///
/// The API key never lives in the plain settings JSON — it goes through
/// flutter_secure_storage. On platforms where secure storage is unavailable
/// (rare on Android), reads return null and writes throw.
class SettingsStore {
  SettingsStore({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return AppSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return AppSettings.fromJson(decoded);
    } catch (_) {
      // Corrupt blob — fall back to defaults rather than crashing the app.
    }
    return AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<String?> readApiKey() async {
    try {
      return await _secure.read(key: _apiKeyKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeApiKey(String key) async {
    await _secure.write(key: _apiKeyKey, value: key);
  }

  Future<void> deleteApiKey() async {
    try {
      await _secure.delete(key: _apiKeyKey);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<String?> readWebApiKey() async {
    try {
      return await _secure.read(key: _webApiKeyKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeWebApiKey(String key) async {
    await _secure.write(key: _webApiKeyKey, value: key);
  }

  Future<void> deleteWebApiKey() async {
    try {
      await _secure.delete(key: _webApiKeyKey);
    } catch (_) {
      // Best-effort.
    }
  }
}
