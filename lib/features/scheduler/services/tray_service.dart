import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/skills/services/sidecar_process_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener, WindowListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  static bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      trayManager.addListener(this);
      windowManager.addListener(this);

      // Prevent default window closing so we can intercept and hide to tray
      await windowManager.setPreventClose(true);

      final menu = Menu(
        items: [
          MenuItem(key: 'brand', label: 'خوارزمي — AI Agent', disabled: true),
          MenuItem.separator(),
          MenuItem(key: 'open', label: 'فتح خوارزمي'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'إنهاء خوارزمي بالكامل'),
        ],
      );

      await trayManager.setContextMenu(menu);
      _isInitialized = true;
      debugPrint('[TrayService] Windows System Tray and WindowListener initialized successfully.');
    } catch (e) {
      debugPrint('[TrayService] Tray initialization note: $e');
    }
  }

  /// Shows the application window and brings it to the foreground
  Future<void> showAppWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[TrayService] Error showing window: $e');
    }
  }

  /// Hides the application window to system tray
  Future<void> hideAppWindow() async {
    try {
      await windowManager.hide();
    } catch (e) {
      debugPrint('[TrayService] Error hiding window: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'open') {
      await showAppWindow();
    } else if (menuItem.key == 'exit') {
      // Explicit full app termination requested by user
      debugPrint('[TrayService] Full termination requested by user from Tray menu.');
      try {
        await SidecarProcessManager.instance.stopAll();
      } catch (e) {
        debugPrint('[TrayService] Error stopping sidecars on exit: $e');
      }
      await windowManager.destroy();
      exit(0);
    }
  }

  /// Window Close Interception (Window Close Override)
  /// Intercepts the default Windows (X) close button. Instead of killing the process,
  /// hides the window so background services (SchedulerService) continue running.
  @override
  void onWindowClose() async {
    debugPrint('[TrayService] Window close (X) intercepted. Hiding window to system tray.');
    await hideAppWindow();
  }

  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
