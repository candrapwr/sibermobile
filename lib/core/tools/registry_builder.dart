/// Registry builder: assembles every optional device tool and applies the
/// user's enable/disable choices from settings.
///
/// One list per category keeps the tools screen grouped the same way the
/// registry is built, so the UI never drifts from what the model can call.
library;

import '../settings/settings.dart';
import 'core_tools.dart';
import 'http_tools.dart';
import 'image_tools.dart';
import 'registry.dart';
import 'tool.dart';
import 'web_tools.dart';

import 'hardware/app_tools.dart';
import 'hardware/battery_tools.dart';
import 'hardware/contact_tools.dart';
import 'hardware/device_tools.dart';
import 'hardware/file_tools.dart';
import 'hardware/interaction_tools.dart';
import 'hardware/location_tools.dart';
import 'hardware/media_tools.dart';
import 'hardware/network_analysis_tools.dart';
import 'hardware/nfc_tools.dart';
import 'hardware/notification_tools.dart';
import 'hardware/shell_tools.dart';
import 'hardware/ssh_tools.dart';
import 'hardware/speech_tools.dart';

/// Every tool the app can expose, including tools the user cannot turn off.
///
/// This remains the source of truth for the registry and tools screen.
final List<Tool> allTools = <Tool>[
  ...coreTools,
  ...webTools,
  ...imageTools,
  ...httpTools,
  ...deviceTools,
  ...batteryTools,
  ...networkAnalysisTools,
  ...locationTools,
  ...mediaTools,
  ...speechTools,
  ...notificationTools,
  ...shellTools,
  ...sshTools,
  ...contactTools,
  ...appTools,
  ...nfcTools,
  ...fileTools,
  ...interactionTools,
];

/// The subset the user may enable or disable from Settings.
final List<Tool> optionalTools = allTools
    .where((tool) => !tool.isCoreTool)
    .toList(growable: false);

/// Tool names the app knows about, grouped by category for the settings/tools
/// screen. Derived from [allTools] so it can never drift.
Map<String, List<Tool>> toolsByCategory() {
  final grouped = <String, List<Tool>>{};
  for (final tool in allTools) {
    grouped.putIfAbsent(tool.category, () => <Tool>[]).add(tool);
  }
  // Stable category order rather than map-insertion order.
  final order = <String>{
    'Core',
    'Device',
    'Battery',
    'Network',
    'Location',
    'Camera',
    'Media',
    'Speech',
    'Notification',
    'System',
    'SSH',
    'Contacts',
    'Apps',
    'NFC',
    'Files',
  };
  final sorted = <String, List<Tool>>{};
  for (final c in order) {
    if (grouped.containsKey(c)) sorted[c] = grouped[c]!;
  }
  for (final c in grouped.keys) {
    if (!sorted.containsKey(c)) sorted[c] = grouped[c]!;
  }
  return sorted;
}

/// Builds a [ToolRegistry] from [settings]. Core tools always remain present;
/// optional tools listed in `settings.disabledTools` are skipped.
///
/// `webSearchAvailable` gates `web_search` (configured manually or via the
/// Siber gateway); `imageToolsAvailable` gates the Siber-gateway-only image
/// tools (`analyze_image`, `generate_image`).
ToolRegistry buildRegistry(
  AppSettings settings, {
  bool webSearchAvailable = false,
  bool imageToolsAvailable = false,
}) {
  final registry = ToolRegistry();
  for (final tool in allTools) {
    if (tool.name == 'web_search' && !webSearchAvailable) continue;
    if (tool.name == 'analyze_image' && !imageToolsAvailable) continue;
    if (tool.name == 'generate_image' && !imageToolsAvailable) continue;
    if (!tool.isCoreTool && settings.disabledTools.contains(tool.name)) {
      continue;
    }
    registry.register(tool);
  }
  return registry;
}
