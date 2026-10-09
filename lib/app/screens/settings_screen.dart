/// Settings screen: configure the single custom OpenAI-compatible provider
/// (base URL, API key, model) plus agent tuning and tool defaults.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai/openai_compatible_provider.dart';
import '../../core/settings/settings.dart';
import '../chat_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _webBaseUrl;
  late final TextEditingController _webApiKey;
  late final TextEditingController _temperature;
  late final TextEditingController _maxTokens;
  late final TextEditingController _maxIterations;
  late final TextEditingController _contextWindow;
  late final TextEditingController _compactThreshold;
  late final TextEditingController _compactKeepRecent;

  late bool _includeUsage;
  late bool _sendReasoning;
  late ReasoningEffort _reasoning;
  late bool _autoContinue;
  late bool _compactContext;
  late AppThemeMode _themeMode;
  late bool _approveDestructive;

  bool _obscureKey = true;
  bool _obscureWebKey = true;
  bool _hasStoredKey = false;
  bool _hasStoredWebKey = false;
  bool _fetchingModels = false;
  bool _testing = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<ChatController>().settings;
    _baseUrl = TextEditingController(text: settings.baseUrl);
    _model = TextEditingController(text: settings.model);
    _apiKey = TextEditingController();
    _webBaseUrl = TextEditingController(text: settings.webBaseUrl);
    _webApiKey = TextEditingController();
    _temperature = TextEditingController(
      text: settings.temperature.toStringAsFixed(1),
    );
    _maxTokens = TextEditingController(text: '${settings.maxTokens}');
    _maxIterations = TextEditingController(text: '${settings.maxIterations}');
    _contextWindow = TextEditingController(text: '${settings.contextWindow}');
    _compactThreshold = TextEditingController(
      text: '${(settings.compactThreshold * 100).round()}',
    );
    _compactKeepRecent = TextEditingController(
      text: '${settings.compactKeepRecent}',
    );
    _includeUsage = settings.includeUsageInStream;
    _sendReasoning = settings.sendReasoningEffort;
    _reasoning = settings.reasoningEffort;
    _autoContinue = settings.autoContinue;
    _compactContext = settings.compactContext;
    _themeMode = settings.themeMode;
    _approveDestructive = settings.approveDestructiveTools;
    final controller = context.read<ChatController>();
    _hasStoredKey = controller.hasApiKey;
    _hasStoredWebKey = controller.hasWebApiKey;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _webBaseUrl.dispose();
    _webApiKey.dispose();
    _temperature.dispose();
    _maxTokens.dispose();
    _maxIterations.dispose();
    _contextWindow.dispose();
    _compactThreshold.dispose();
    _compactKeepRecent.dispose();
    super.dispose();
  }

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = isError;
    });
  }

  void _showSaveFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    final colors = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: isError
              ? colors.errorContainer
              : colors.inverseSurface,
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: isError
                    ? colors.onErrorContainer
                    : colors.inversePrimary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError
                        ? colors.onErrorContainer
                        : colors.onInverseSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  String _normalizeBase(String raw) =>
      raw.trim().replaceAll(RegExp(r'/+$'), '');

  bool _validateProviderFields() {
    if (_normalizeBase(_baseUrl.text).isEmpty) {
      _setStatus('Base URL wajib diisi.', isError: true);
      return false;
    }
    final uri = Uri.tryParse(_normalizeBase(_baseUrl.text));
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      _setStatus(
        'Base URL tidak valid. Contoh: https://api.example.com/v1',
        isError: true,
      );
      return false;
    }
    if (_model.text.trim().isEmpty) {
      _setStatus('Nama model wajib diisi.', isError: true);
      return false;
    }
    if (_apiKey.text.trim().isEmpty && !_hasStoredKey) {
      _setStatus('API key wajib diisi.', isError: true);
      return false;
    }
    final webBase = _normalizeBase(_webBaseUrl.text);
    if (webBase.isNotEmpty) {
      final webUri = Uri.tryParse(webBase);
      if (webUri == null ||
          !webUri.hasScheme ||
          !webUri.hasAuthority ||
          !{'http', 'https'}.contains(webUri.scheme.toLowerCase())) {
        _setStatus(
          'Endpoint web tidak valid. Contoh: https://api.exa.ai',
          isError: true,
        );
        return false;
      }
    }
    return true;
  }

  AppSettings _collect() {
    final current = context.read<ChatController>().settings;
    final parsedMaxTokens = int.tryParse(_maxTokens.text.trim());
    return current.copyWith(
      baseUrl: _normalizeBase(_baseUrl.text),
      model: _model.text.trim(),
      webBaseUrl: _normalizeBase(_webBaseUrl.text),
      temperature:
          double.tryParse(_temperature.text.trim()) ?? current.temperature,
      maxTokens: parsedMaxTokens ?? current.maxTokens,
      maxTokensCustomized: parsedMaxTokens == null
          ? current.maxTokensCustomized
          : parsedMaxTokens != defaultMaxTokens,
      maxIterations:
          int.tryParse(_maxIterations.text.trim()) ?? current.maxIterations,
      includeUsageInStream: _includeUsage,
      sendReasoningEffort: _sendReasoning,
      reasoningEffort: _reasoning,
      autoContinue: _autoContinue,
      compactContext: _compactContext,
      contextWindow:
          int.tryParse(_contextWindow.text.trim()) ?? current.contextWindow,
      compactThreshold:
          (double.tryParse(_compactThreshold.text.trim()) ??
              (current.compactThreshold * 100)) /
          100,
      compactKeepRecent:
          int.tryParse(_compactKeepRecent.text.trim()) ??
          current.compactKeepRecent,
      themeMode: _themeMode,
      approveDestructiveTools: _approveDestructive,
    );
  }

  Future<void> _applyTheme(AppThemeMode mode) async {
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);
    final controller = context.read<ChatController>();
    await controller.saveSettings(
      controller.settings.copyWith(themeMode: mode),
    );
    _setStatus('Tema ${_themeLabel(mode).toLowerCase()} diterapkan.');
  }

  Future<void> _save() async {
    if (!_validateProviderFields()) return;
    final controller = context.read<ChatController>();
    final key = _apiKey.text.trim();
    final webKey = _webApiKey.text.trim();
    try {
      await controller.saveSettings(
        _collect(),
        apiKey: key.isEmpty ? null : key,
        webApiKey: webKey.isEmpty ? null : webKey,
      );
      if (key.isNotEmpty) _hasStoredKey = true;
      if (webKey.isNotEmpty) _hasStoredWebKey = true;
      _apiKey.clear();
      _webApiKey.clear();
      _setStatus('Pengaturan tersimpan.', isError: false);
      _showSaveFeedback('Pengaturan berhasil disimpan.');
    } catch (error) {
      _setStatus('Gagal menyimpan pengaturan: $error', isError: true);
      _showSaveFeedback('Pengaturan gagal disimpan.', isError: true);
    }
  }

  Future<void> _fetchModels() async {
    if (!_validateProviderFields()) return;
    setState(() => _fetchingModels = true);
    _setStatus('Mengambil daftar model…');
    final provider = OpenAiCompatibleProvider(
      baseUrl: _normalizeBase(_baseUrl.text),
      apiKey: await _effectiveKey(),
      model: _model.text.trim(),
      includeUsageInStream: _includeUsage,
    );
    try {
      final models = await provider.listModels();
      if (!mounted) return;
      if (models.isEmpty) {
        _setStatus(
          'Gateway tidak mengembalikan daftar model. Isi manual saja.',
          isError: true,
        );
      } else {
        final picked = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => _ModelPickerSheet(models: models),
        );
        if (!mounted) return;
        if (picked != null) {
          _model.text = picked;
          _setStatus('Model dipilih: $picked');
        }
      }
    } catch (e) {
      _setStatus('Gagal mengambil model: $e', isError: true);
    } finally {
      provider.close();
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  /// The key to use for a live call: the freshly typed one, else the stored one.
  Future<String> _effectiveKey() async {
    final typed = _apiKey.text.trim();
    if (typed.isNotEmpty) return typed;
    if (_hasStoredKey) {
      // Read the stored key back for the test call only; never shown in UI.
      final stored = await SettingsStore().readApiKey();
      if (stored != null) return stored;
    }
    return '';
  }

  Future<void> _testConnection() async {
    if (!_validateProviderFields()) return;
    setState(() => _testing = true);
    _setStatus('Menguji koneksi…');
    final provider = OpenAiCompatibleProvider(
      baseUrl: _normalizeBase(_baseUrl.text),
      apiKey: await _effectiveKey(),
      model: _model.text.trim(),
      includeUsageInStream: _includeUsage,
    );
    try {
      final reply = await provider.ping();
      _setStatus('Koneksi OK. Balasan: ${reply.trim()}');
    } catch (e) {
      _setStatus('Koneksi gagal: $e', isError: true);
    } finally {
      provider.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final webReady = controller.hasWebSearchConfig;
    final webEnabled = !controller.settings.disabledTools.contains(
      'web_search',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        actions: [
          IconButton.filledTonal(
            onPressed: _save,
            tooltip: 'Simpan',
            icon: const Icon(Icons.check_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 18),
        children: [
          _ConnectionHero(configured: controller.isConfigured),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(
                  icon: Icons.cloud_outlined,
                  title: 'Provider AI',
                  subtitle: 'OpenAI-compatible • konfigurasi tersimpan lokal',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.example.com/v1',
                    prefixIcon: Icon(Icons.link_rounded),
                    helperText: 'Tanpa /chat/completions di bagian akhir.',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _apiKey,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    prefixIcon: const Icon(Icons.key_rounded),
                    helperText: _hasStoredKey
                        ? 'Key aman tersimpan. Kosongkan untuk tidak mengubah.'
                        : 'Dienkripsi melalui secure storage perangkat.',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      tooltip: _obscureKey
                          ? 'Tampilkan key'
                          : 'Sembunyikan key',
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText: 'nama-model',
                    prefixIcon: Icon(Icons.memory_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _fetchingModels ? null : _fetchModels,
                        icon: _fetchingModels
                            ? const _MiniLoader()
                            : const Icon(Icons.cloud_download_outlined),
                        label: const Text('Ambil model'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const _MiniLoader()
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: const Text('Tes koneksi'),
                      ),
                    ),
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _status == null
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(_status),
                          padding: const EdgeInsets.only(top: 10),
                          child: _StatusMessage(
                            message: _status!,
                            isError: _statusIsError,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(
                  icon: Icons.palette_outlined,
                  title: 'Tampilan',
                  subtitle:
                      'Pilih tema aplikasi secara manual atau ikuti sistem',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AppThemeMode>(
                  initialValue: _themeMode,
                  decoration: const InputDecoration(
                    labelText: 'Tema aplikasi',
                    prefixIcon: Icon(Icons.brightness_6_outlined),
                    isDense: true,
                  ),
                  items: [
                    for (final mode in AppThemeMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(_themeLabel(mode)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _applyTheme(value);
                  },
                ),
                const SizedBox(height: 5),
                Text(
                  'Perubahan tema diterapkan dan disimpan langsung.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(
                  icon: Icons.travel_explore_rounded,
                  title: 'Web search (Exa-compatible)',
                  subtitle: 'Search web dan baca konten halaman dengan aman',
                ),
                const SizedBox(height: 14),
                if (controller.settings.usesSiberGateway) ...[
                  // Siber gateway mode: the static Exa-compatible endpoint on
                  // the gateway is used with the provider key — nothing to
                  // configure here.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(
                        alpha: 0.08,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Otomatis aktif via Siber gateway.\n'
                            'Endpoint: $siberWebSearchBaseUrl\n'
                            'Token: API key provider (sama, tidak perlu '
                            'setting terpisah).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _webBaseUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Endpoint web',
                      hintText: 'https://api.exa.ai',
                      prefixIcon: Icon(Icons.link_rounded),
                      helperText:
                          'Aplikasi otomatis menambahkan /search dan /contents. Bisa memakai proxy kompatibel Exa.',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _webApiKey,
                    obscureText: _obscureWebKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Exa API key',
                      prefixIcon: const Icon(Icons.key_outlined),
                      helperText: _hasStoredWebKey
                          ? 'Key web aman tersimpan. Kosongkan untuk tidak mengubah.'
                          : 'Opsional sampai ingin mengaktifkan tool Web search.',
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: _obscureWebKey
                            ? 'Tampilkan key'
                            : 'Sembunyikan key',
                        icon: Icon(
                          _obscureWebKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscureWebKey = !_obscureWebKey,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: webReady && webEnabled,
                  onChanged: webReady
                      ? (enabled) async {
                          final disabled = Set<String>.of(
                            controller.settings.disabledTools,
                          );
                          enabled
                              ? disabled.remove('web_search')
                              : disabled.add('web_search');
                          await controller.saveSettings(
                            controller.settings.copyWith(
                              disabledTools: disabled,
                            ),
                          );
                        }
                      : null,
                  title: const Text('Aktifkan web_search'),
                  subtitle: Text(
                    webReady
                        ? 'Tool dipakai AI untuk search dan membaca konten web.'
                        : 'Isi endpoint dan API key, lalu simpan pengaturan terlebih dahulu.',
                  ),
                  secondary: Icon(
                    webReady
                        ? Icons.travel_explore_rounded
                        : Icons.lock_outline_rounded,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Toggle ini juga tersedia di layar Tool perangkat.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(
                  icon: Icons.tune_rounded,
                  title: 'Perilaku agent',
                  subtitle: 'Atur kreativitas, panjang jawaban, dan loop tool',
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fieldWidth = (constraints.maxWidth - 8) / 2;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: _temperature,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Temperature',
                              isDense: true,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: _maxTokens,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max tokens',
                              isDense: true,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: _maxIterations,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max iterasi',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                _SettingSwitch(
                  icon: Icons.fast_forward_rounded,
                  title: 'Auto-continue',
                  subtitle: 'Lanjutkan balasan yang terpotong batas token.',
                  value: _autoContinue,
                  onChanged: (value) => setState(() => _autoContinue = value),
                ),
                const SizedBox(height: 6),
                _SettingSwitch(
                  icon: Icons.compress_rounded,
                  title: 'Ringkas konteks otomatis',
                  subtitle:
                      'AI merangkum turn lama saat konteks mendekati batas.',
                  value: _compactContext,
                  onChanged: (value) => setState(() => _compactContext = value),
                ),
                if (_compactContext) ...[
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fieldWidth = (constraints.maxWidth - 8) / 2;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: fieldWidth,
                            child: TextField(
                              controller: _contextWindow,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Context window',
                                suffixText: 'token',
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: TextField(
                              controller: _compactThreshold,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Ringkas pada',
                                suffixText: '%',
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: TextField(
                              controller: _compactKeepRecent,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Turn terbaru disimpan',
                                suffixText: 'turn',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Gunakan context window sesuai batas model. Statistik token dari provider diperlukan agar pemicu berjalan akurat.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                _SettingSwitch(
                  icon: Icons.data_usage_rounded,
                  title: 'stream_options.include_usage',
                  subtitle: 'Matikan bila gateway menolak opsi statistik.',
                  value: _includeUsage,
                  onChanged: (value) => setState(() => _includeUsage = value),
                ),
                const SizedBox(height: 6),
                _SettingSwitch(
                  icon: Icons.psychology_alt_rounded,
                  title: 'Kirim reasoning_effort',
                  subtitle: 'Gunakan hanya pada gateway yang mendukungnya.',
                  value: _sendReasoning,
                  onChanged: (value) => setState(() => _sendReasoning = value),
                ),
                if (_sendReasoning) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ReasoningEffort>(
                    initialValue: _reasoning,
                    decoration: const InputDecoration(
                      labelText: 'Reasoning effort',
                      prefixIcon: Icon(Icons.speed_rounded),
                      isDense: true,
                    ),
                    items: [
                      for (final effort in ReasoningEffort.values)
                        DropdownMenuItem(
                          value: effort,
                          child: Text(effort.name),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => _reasoning = value ?? ReasoningEffort.medium,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                const SectionHeading(
                  icon: Icons.shield_outlined,
                  title: 'Keamanan',
                  subtitle: 'Kontrol aksi yang mengubah perangkat atau data',
                ),
                const SizedBox(height: 12),
                _SettingSwitch(
                  icon: Icons.approval_outlined,
                  title: 'Minta izin untuk aksi berisiko',
                  subtitle:
                      'Tampilkan konfirmasi sebelum hapus file, memakai suara, atau membuka pengaturan.',
                  value: _approveDestructive,
                  onChanged: (value) =>
                      setState(() => _approveDestructive = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan pengaturan'),
          ),
        ],
      ),
    );
  }
}

String _themeLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => 'Ikuti tema perangkat',
  AppThemeMode.light => 'Terang',
  AppThemeMode.dark => 'Gelap',
};

/// Bottom sheet listing models returned by the gateway's /models endpoint.
class _ModelPickerSheet extends StatelessWidget {
  const _ModelPickerSheet({required this.models});

  final List<String> models;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: SectionHeading(
              icon: Icons.memory_rounded,
              title: 'Pilih model',
              subtitle: '${models.length} model tersedia dari gateway',
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 5),
                  child: ListTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.smart_toy_outlined,
                        size: 19,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      model,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    onTap: () => Navigator.of(context).pop(model),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = configured ? AppTheme.accent : theme.colorScheme.error;
    return SurfaceCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              configured ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured ? 'Provider terhubung' : 'Provider belum lengkap',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  configured
                      ? 'Konfigurasi siap digunakan untuk percakapan.'
                      : 'Lengkapi URL, API key, dan model di bawah.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(label: configured ? 'SIAP' : 'BELUM SIAP', color: color),
        ],
      ),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 17,
      height: 17,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : AppTheme.accent;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 5, 7),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
