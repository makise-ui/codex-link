import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class AppNotifier {
  Future<void> initialize();

  Future<void> show({
    required String title,
    required String body,
    String? payload,
  });
}

class LocalAppNotifier implements AppNotifier {
  LocalAppNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  var _initialized = false;
  var _nextId = 1;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open Codex Link'),
      );
      await _plugin.initialize(settings: settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _initialized = true;
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    final normalizedBody = body.trim();
    if (title.trim().isEmpty || normalizedBody.isEmpty) return;
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: normalizedBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'codex_link_events',
            'Codex Link updates',
            channelDescription:
                'Progress, plan, completion, and connection updates.',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
          ),
          linux: LinuxNotificationDetails(
            category: LinuxNotificationCategory.imReceived,
            urgency: LinuxNotificationUrgency.normal,
            transient: true,
          ),
        ),
        payload: payload,
      );
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }
}
