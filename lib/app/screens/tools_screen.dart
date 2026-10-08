import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tools/registry_builder.dart';
import '../../core/tools/tool.dart';
import '../chat_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final next = _search.text.trim().toLowerCase();
      if (next != _query) setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final disabled = controller.settings.disabledTools;
    final unavailable = allTools
        .where((tool) => !_isAvailable(controller, tool))
        .map((tool) => tool.name)
        .toSet();
    final enabledCount = allTools
        .where(
          (tool) =>
              !unavailable.contains(tool.name) &&
              (tool.isCoreTool || !disabled.contains(tool.name)),
        )
        .length;
    final coreCount = allTools.where((tool) => tool.isCoreTool).length;
    final visible = allTools.where((tool) {
      if (_query.isEmpty) return true;
      return tool.name.toLowerCase().contains(_query) ||
          tool.category.toLowerCase().contains(_query) ||
          tool.description.toLowerCase().contains(_query);
    }).toList();
    final grouped = <String, List<Tool>>{};
    for (final tool in visible) {
      grouped.putIfAbsent(tool.category, () => []).add(tool);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tool perangkat')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 18),
        children: [
          _ToolOverview(
            enabled: enabledCount,
            total: allTools.length,
            coreCount: coreCount,
            onEnableAll: () => _setAll(controller, true),
            onDisableAll: () => _setAll(controller, false),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Cari nama atau fungsi tool',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      onPressed: _search.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (grouped.isEmpty)
            const _NoToolResult()
          else
            for (final entry in grouped.entries) ...[
              _CategoryCard(
                category: entry.key,
                tools: entry.value,
                disabled: disabled,
                unavailable: unavailable,
                onToggle: (tool, value) =>
                    _setToolEnabled(controller, tool, value),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Future<void> _setAll(ChatController controller, bool enabled) async {
    await controller.saveSettings(
      controller.settings.copyWith(
        disabledTools: enabled
            ? <String>{}
            : optionalTools.map((tool) => tool.name).toSet(),
      ),
    );
  }

  Future<void> _setToolEnabled(
    ChatController controller,
    Tool tool,
    bool enabled,
  ) async {
    if (tool.isCoreTool || !_isAvailable(controller, tool)) return;
    final disabled = Set<String>.of(controller.settings.disabledTools);
    enabled ? disabled.remove(tool.name) : disabled.add(tool.name);
    await controller.saveSettings(
      controller.settings.copyWith(disabledTools: disabled),
    );
  }
}

bool _isAvailable(ChatController controller, Tool tool) {
  if (tool.name == 'web_search') return controller.hasWebSearchConfig;
  if (tool.name == 'analyze_image') {
    return controller.settings.usesSiberGateway && controller.hasApiKey;
  }
  return true;
}

class _ToolOverview extends StatelessWidget {
  const _ToolOverview({
    required this.enabled,
    required this.total,
    required this.coreCount,
    required this.onEnableAll,
    required this.onDisableAll,
  });

  final int enabled;
  final int total;
  final int coreCount;
  final VoidCallback onEnableAll;
  final VoidCallback onDisableAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_fix_high_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                '$enabled/$total',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Kemampuan AI',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 3),
          Text(
            '$enabled tool aktif dan siap digunakan sesuai kebutuhan.'
            '${coreCount == 0 ? '' : ' $coreCount tool inti selalu aktif.'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onEnableAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    minimumSize: const Size(0, 38),
                  ),
                  child: const Text('Aktifkan semua'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onDisableAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    minimumSize: const Size(0, 38),
                  ),
                  child: const Text('Matikan semua'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.tools,
    required this.disabled,
    required this.unavailable,
    required this.onToggle,
  });

  final String category;
  final List<Tool> tools;
  final Set<String> disabled;
  final Set<String> unavailable;
  final void Function(Tool tool, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _categoryIcon(category);
    final active = tools
        .where(
          (tool) =>
              !unavailable.contains(tool.name) &&
              (tool.isCoreTool || !disabled.contains(tool.name)),
        )
        .length;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
            child: SectionHeading(
              icon: icon,
              title: category,
              subtitle: '$active dari ${tools.length} aktif',
            ),
          ),
          Divider(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
          for (var i = 0; i < tools.length; i++) ...[
            _ToolRow(
              tool: tools[i],
              available: !unavailable.contains(tools[i].name),
              enabled:
                  !unavailable.contains(tools[i].name) &&
                  (tools[i].isCoreTool || !disabled.contains(tools[i].name)),
              onChanged: (value) => onToggle(tools[i], value),
            ),
            if (i != tools.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Divider(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.tool,
    required this.available,
    required this.enabled,
    required this.onChanged,
  });

  final Tool tool;
  final bool available;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = !available && tool.name == 'web_search'
        ? 'Isi endpoint dan API key Exa di Pengaturan terlebih dahulu.'
        : !available && tool.name == 'analyze_image'
        ? 'Hanya tersedia saat provider adalah Siber gateway (Base URL '
              'mengandung idsiber.com).'
        : tool.description.split('.').first;
    return InkWell(
      onTap: tool.isCoreTool || !available ? null : () => onChanged(!enabled),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: enabled
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                tool.isCoreTool
                    ? Icons.auto_awesome_rounded
                    : tool.requiresApproval
                    ? Icons.shield_outlined
                    : Icons.bolt_rounded,
                size: 16,
                color: enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tool.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (tool.isCoreTool) ...[
                        const SizedBox(width: 5),
                        const StatusPill(
                          label: 'INTI',
                          color: Color(0xFF6366F1),
                          icon: Icons.lock_rounded,
                        ),
                      ] else if (!available) ...[
                        const SizedBox(width: 5),
                        const StatusPill(
                          label: 'ATUR',
                          color: Color(0xFF94A3B8),
                          icon: Icons.lock_outline_rounded,
                        ),
                      ] else if (tool.requiresApproval) ...[
                        const SizedBox(width: 5),
                        const StatusPill(
                          label: 'IZIN',
                          color: Color(0xFFF59E0B),
                          icon: Icons.lock_outline_rounded,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (tool.isCoreTool)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.lock_rounded, size: 18),
              )
            else
              Switch(value: enabled, onChanged: available ? onChanged : null),
          ],
        ),
      ),
    );
  }
}

class _NoToolResult extends StatelessWidget {
  const _NoToolResult();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('Tool tidak ditemukan', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Coba kata kunci lain.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _categoryIcon(String category) {
  return switch (category.toLowerCase()) {
    'core' => Icons.auto_awesome_rounded,
    'device' => Icons.phone_android_rounded,
    'battery' => Icons.battery_charging_full_rounded,
    'network' => Icons.wifi_rounded,
    'location' => Icons.location_on_rounded,
    'hardware' || 'camera' => Icons.camera_alt_rounded,
    'speech' => Icons.mic_rounded,
    'media' => Icons.play_circle_rounded,
    'notification' => Icons.notifications_rounded,
    'contacts' => Icons.contacts_rounded,
    'apps' => Icons.apps_rounded,
    'files' => Icons.folder_rounded,
    'interaction' => Icons.touch_app_rounded,
    _ => Icons.extension_rounded,
  };
}
