import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await localNotifier.setup(
        appName: 'خوارزمي — Khwarizmi AI',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _isInitialized = true;
      debugPrint('[NotificationService] Windows Local Notifier initialized successfully.');
    } catch (e) {
      debugPrint('[NotificationService] Initialization warning: $e');
    }
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    String? identifier,
  }) async {
    try {
      await initialize();

      final notification = LocalNotification(
        identifier: identifier,
        title: title,
        body: body,
      );

      notification.onShow = () {
        debugPrint('[NotificationService] Notification displayed: $title');
      };

      notification.onClick = () {
        debugPrint('[NotificationService] Notification clicked: $title');
      };

      await notification.show();
    } catch (e) {
      debugPrint('[NotificationService] Failed to show notification: $e');
    }
  }
}
