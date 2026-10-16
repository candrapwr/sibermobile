/// Personal Tools hub: device utilities that work without the AI.
///
/// This screen is only a launcher — each tool opens in its own window with
/// its own permission setup and controls, so adding tools never crowds one
/// screen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/common_widgets.dart';
import 'auto_clicker_screen.dart';

class PersonalToolsScreen extends StatefulWidget {
  const PersonalToolsScreen({super.key});

  @override
  State<PersonalToolsScreen> createState() => _PersonalToolsScreenState();
}

class _PersonalToolsScreenState extends State<PersonalToolsScreen> {
  static const _channel = MethodChannel('sibermobile/device');

  /// Which tools are currently active, keyed by index. Refreshed when the
  /// hub opens and again after any tool window closes.
  final Map<int, bool> _running = {};

  @override
  void initState() {
    super.initState();
    _refreshRunning();
  }

  Future<void> _refreshRunning() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'autoClickerStatus',
      );
      if (mounted && status != null) {
        setState(() => _running[0] = status['running'] == true);
      }
    } catch (_) {}
  }

  Future<void> _openAutoClicker() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AutoClickerScreen()));
    await _refreshRunning();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Tools')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
        children: [
          _ToolCard(
            icon: Icons.touch_app_rounded,
            name: 'Auto Kliker',
            description:
                'Ketuk otomatis di titik target dengan interval bebas '
                'dan pola acak anti-deteksi.',
            running: _running[0] ?? false,
            onTap: _openAutoClicker,
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.name,
    required this.description,
    required this.onTap,
    this.running = false,
  });

  final IconData icon;
  final String name;
  final String description;
  final VoidCallback onTap;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: colors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (running) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'AKTIF',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            color: colors.onSurfaceVariant,
            size: 22,
          ),
        ],
      ),
    );
  }
}
