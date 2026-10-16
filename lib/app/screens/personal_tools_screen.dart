/// Personal Tools: device utilities that work without the AI.
///
/// First entry: the Auto Clicker — a floating crosshair + control bubble
/// driven by an accessibility service. This screen only handles the
/// permission setup and starting/stopping the overlay.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_modal.dart';
import '../widgets/common_widgets.dart';

class PersonalToolsScreen extends StatefulWidget {
  const PersonalToolsScreen({super.key});

  @override
  State<PersonalToolsScreen> createState() => _PersonalToolsScreenState();
}

class _PersonalToolsScreenState extends State<PersonalToolsScreen> {
  static const _channel = MethodChannel('sibermobile/device');

  bool _overlayGranted = false;
  bool _accessibilityOn = false;
  bool _clickerRunning = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'autoClickerStatus',
      );
      if (mounted && status != null) {
        setState(() {
          _overlayGranted = status['overlayGranted'] == true;
          _accessibilityOn = status['accessibilityOn'] == true;
          _clickerRunning = status['running'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _requestOverlay() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<void> _openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<void> _toggleClicker() async {
    if (!Platform.isAndroid) return;
    if (!_overlayGranted || !_accessibilityOn) {
      _showSetupHelp();
      return;
    }
    try {
      await _channel.invokeMethod(
        _clickerRunning
            ? 'autoClickerStop'
            : 'autoClickerStart',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
    await _refreshStatus();
  }

  void _showSetupHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AppModal(
        title: 'Auto Clicker butuh 2 izin',
        icon: Icons.touch_app_rounded,
        onClose: () => Navigator.pop(dialogContext),
        footer: AppModal.actions(dialogContext, [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Mengerti'),
          ),
        ]),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '1. Izin overlay — agar crosshair & tombol kontrol muncul di '
              'atas aplikasi lain.',
            ),
            SizedBox(height: 8),
            Text(
              '2. Izin aksesibilitas — agar SiberMobile bisa menyuntikkan '
              'ketukan. Pilih "SiberMobile" / Auto clicker di daftar layanan '
              'aksesibilitas, lalu aktifkan.',
            ),
            SizedBox(height: 8),
            Text(
              'CATATAN: Di Android 13+, jika muncul "Restricted setting", '
              'buka Settings → Apps → SiberMobile → titik-tiga (⋮) → '
              '"Allow restricted settings" terlebih dahulu.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Kembali ke layar ini setelah kedua izin aktif, lalu tekan '
              'Mulai lagi.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ready = _overlayGranted && _accessibilityOn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Tools'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang status izin',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.touch_app_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto Clicker',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ketuk otomatis di titik yang digeser, dengan '
                            'interval yang bisa diatur — tanpa AI.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PermissionRow(
                  done: _overlayGranted,
                  label: 'Izin overlay (tampil di atas app lain)',
                  actionLabel: 'Buka pengaturan',
                  onAction: _requestOverlay,
                ),
                const SizedBox(height: 6),
                _PermissionRow(
                  done: _accessibilityOn,
                  label: 'Layanan aksesibilitas SiberMobile',
                  actionLabel: 'Aktifkan',
                  onAction: _openAccessibilitySettings,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _toggleClicker,
                        style: FilledButton.styleFrom(
                          backgroundColor: _clickerRunning
                              ? colors.error
                              : null,
                          foregroundColor: _clickerRunning
                              ? colors.onError
                              : null,
                        ),
                        icon: Icon(
                          _clickerRunning
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
                        ),
                        label: Text(
                          !ready
                              ? 'Mulai (lengkapi izin)'
                              : _clickerRunning
                              ? 'Hentikan'
                              : 'Mulai auto clicker',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_clickerRunning) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Crosshair + tombol kontrol melayang di layar. Geser '
                    'crosshair ke titik klik, atur interval dari tombol ⏶/⏷ '
                    'di bubble, tekan ▶ untuk mulai.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.done,
    required this.label,
    required this.actionLabel,
    required this.onAction,
  });

  final bool done;
  final String label;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 18,
          color: done ? colors.primary : colors.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: Text(done ? 'Cek ulang' : actionLabel),
        ),
      ],
    );
  }
}
