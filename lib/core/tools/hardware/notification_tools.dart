/// Notification tools: post a local notification.
library;

import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../permissions.dart';
import '../tool.dart';
import '../results.dart';

/// One lazily-initialized notifications plugin shared by all tools. Android
/// needs a channel created before the first `show`, so initialization also
/// registers a default channel.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'sibermobile_default';
  static const String _channelName = 'Assistant';

  Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    final ok = await _plugin.initialize(settings: settings);
    if (ok != true) return false;
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Notifications posted by the assistant',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    _initialized = true;
    return true;
  }

  FlutterLocalNotificationsPlugin get plugin => _plugin;
  String get channelId => _channelId;
  String get channelName => _channelName;
}

/// Posts a local notification with a title and body.
class ShowNotificationTool extends Tool {
  ShowNotificationTool(this._service);

  final NotificationService _service;
  final Random _random = Random();

  @override
  String get name => 'show_notification';

  @override
  String get category => 'Notification';

  @override
  String get description =>
      'Show a local notification in the system tray with a title and body. '
      'Useful for surfacing a result the user may want to see outside the app.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'title': {'type': 'string', 'description': 'Notification title.'},
      'body': {'type': 'string', 'description': 'Notification body text.'},
      'id': {
        'type': 'integer',
        'description': 'Optional notification id. Omit for a random id.',
      },
    },
    'required': ['title', 'body'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final title = requireString(args, 'title');
    final body = requireString(args, 'body');

    final denied = await ensureNamedPermission('notification');
    if (denied != null) return errorResult(denied);

    if (!await _service.ensureInitialized()) {
      return errorResult('Could not initialize the notification plugin.');
    }

    final id = optionalInt(args, 'id', _random.nextInt(1 << 30));
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _service.channelId,
        _service.channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _service.plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
    return jsonResult({'ok': true, 'id': id, 'title': title});
  }
}

final List<Tool> notificationTools = [
  ShowNotificationTool(NotificationService.instance),
];
