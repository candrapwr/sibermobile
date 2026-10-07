/// Interaction tools: ask the user a question mid-turn, and open system/app
/// settings screens.
library;

import 'package:app_settings/app_settings.dart';

import '../tool.dart';
import '../results.dart';

/// Blocks on a user prompt in the chat UI. When no interactive UI is attached
/// (ctx.askUser is null) it tells the model to proceed with a safe default
/// instead of hanging.
class AskUserTool extends Tool {
  @override
  String get name => 'ask_user';

  @override
  String get category => 'Core';

  @override
  bool get isCoreTool => true;

  @override
  String get description =>
      'Ask the user a question when you need confirmation, a decision, or '
      'free-form input before proceeding. Blocks until the user responds. On '
      'cancel, returns a cancellation message - stop and await instructions. '
      'If interaction is unavailable, returns a fallback message; proceed with '
      'a safe default.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'question': {
        'type': 'string',
        'description': 'The question or prompt to show the user.',
      },
      'choices': {
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
        'description':
            'Predefined options the user can pick from. Omit for free-text.',
      },
      'allowFreeText': {
        'type': 'boolean',
        'description':
            'Also show a free-text input alongside the choices. Default false.',
      },
      'defaultChoice': {
        'type': 'string',
        'description': 'Optional default selection or input placeholder.',
      },
    },
    'required': <String>['question'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final question = requireString(args, 'question');
    final askUser = ctx.askUser;
    if (askUser == null) {
      return 'User interaction is not available right now. Proceed with a safe '
          'default and note the assumption in your answer.';
    }

    final choices = args['choices'];
    final request = AskUserRequest(
      question: question,
      choices: choices is List
          ? choices.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const <String>[],
      allowFreeText: optionalBool(args, 'allowFreeText', false),
      defaultChoice: optionalString(args, 'defaultChoice'),
    );

    final response = await askUser(request);
    if (response.cancelled) {
      return 'The user cancelled the prompt. Stop the current task and await '
          'further instructions.';
    }
    return response.answer;
  }
}

/// Opens an Android system settings screen (or this app's own settings page).
class OpenAppSettingsTool extends Tool {
  @override
  String get name => 'open_app_settings';

  @override
  String get description =>
      'Open a device settings screen so the user can change something the app '
      'cannot change itself (for example granting a permanently denied '
      'permission, enabling location or turning off battery optimisation). '
      'setting: settings | wifi | bluetooth | dataRoaming | location '
      '| notification | batteryOptimization | date | display | sound '
      '| security | appSettings.';

  @override
  String get category => 'System';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'setting': {
        'type': 'string',
        'enum': <String>[
          'settings',
          'wifi',
          'bluetooth',
          'dataRoaming',
          'location',
          'notification',
          'batteryOptimization',
          'date',
          'display',
          'sound',
          'security',
          'appSettings',
        ],
        'description': 'Which settings screen to open.',
      },
    },
    'required': <String>['setting'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final raw = requireString(args, 'setting');
    final type = _typeFor(raw);
    if (type == null) {
      return errorResult(
        'Unknown setting "$raw". Use one of: settings, wifi, bluetooth, '
        'dataRoaming, location, notification, batteryOptimization, date, '
        'display, sound, security, appSettings.',
      );
    }
    await AppSettings.openAppSettings(type: type);
    return jsonResult({'ok': true, 'opened': raw});
  }

  AppSettingsType? _typeFor(String raw) {
    switch (raw.toLowerCase()) {
      case 'settings':
        return AppSettingsType.settings;
      case 'wifi':
        return AppSettingsType.wifi;
      case 'bluetooth':
        return AppSettingsType.bluetooth;
      case 'data':
        return AppSettingsType.dataRoaming;
      case 'location':
        return AppSettingsType.location;
      case 'notifications':
      case 'notification':
        return AppSettingsType.notification;
      case 'battery':
        return AppSettingsType.batteryOptimization;
      case 'batteryoptimization':
        return AppSettingsType.batteryOptimization;
      case 'date':
        return AppSettingsType.date;
      case 'display':
        return AppSettingsType.display;
      case 'sound':
        return AppSettingsType.sound;
      case 'security':
        return AppSettingsType.security;
      case 'appsettings':
        return AppSettingsType.generalSettings;
      default:
        return null;
    }
  }
}

final List<Tool> interactionTools = <Tool>[
  AskUserTool(),
  OpenAppSettingsTool(),
];
