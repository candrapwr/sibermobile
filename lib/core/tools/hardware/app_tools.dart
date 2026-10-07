/// App tools: list installed apps and launch one.
library;

import 'package:installed_apps/installed_apps.dart';

import '../tool.dart';
import '../results.dart';

/// Lists installed user apps (name + package + version). Results are capped to
/// keep the context small; use `search` to filter by name or package.
class ListAppsTool extends Tool {
  @override
  String get name => 'list_installed_apps';

  @override
  String get description =>
      'List apps installed on the device (name, package name, version). '
      'Optional `search` filters by name/package substring; `limit` caps the '
      'result (default 100).';

  @override
  String get category => 'Apps';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'search': {
        'type': 'string',
        'description': 'Case-insensitive substring to filter by.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Max entries to return (default 100, max 500).',
      },
      'includeSystemApps': {
        'type': 'boolean',
        'description': 'Include system apps (default false).',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final search = optionalString(args, 'search')?.toLowerCase();
    final limit = optionalInt(args, 'limit', 100).clamp(1, 500);
    final includeSystem = optionalBool(args, 'includeSystemApps', false);

    final apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: !includeSystem,
      excludeNonLaunchableApps: false,
      withIcon: false,
      detectPlatformType: false,
    );

    var filtered = apps;
    if (search != null && search.isNotEmpty) {
      filtered = apps
          .where(
            (a) =>
                a.name.toLowerCase().contains(search) ||
                a.packageName.toLowerCase().contains(search),
          )
          .toList();
    }
    final out = filtered
        .take(limit)
        .map(
          (a) => {
            'name': a.name,
            'packageName': a.packageName,
            'versionName': a.versionName,
          },
        )
        .toList();

    return jsonResult({
      'total': filtered.length,
      'returned': out.length,
      'apps': out,
    });
  }
}

/// Launches an app by package name (opens it in the foreground).
class LaunchAppTool extends Tool {
  @override
  String get name => 'launch_app';

  @override
  String get description =>
      'Launch an installed app by its package name (e.g. com.whatsapp). '
      'Returns ok:false when the package is not installed or cannot be started.';

  @override
  String get category => 'Apps';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'packageName': {
        'type': 'string',
        'description': 'The Android package name of the app to launch.',
      },
    },
    'required': ['packageName'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final package = requireString(args, 'packageName').trim();
    final installed = await InstalledApps.isAppInstalled(package);
    if (installed != true) {
      return errorResult('App "$package" is not installed on this device.');
    }
    final ok = await InstalledApps.startApp(package);
    return jsonResult({'ok': ok == true, 'packageName': package});
  }
}

final List<Tool> appTools = [ListAppsTool(), LaunchAppTool()];
