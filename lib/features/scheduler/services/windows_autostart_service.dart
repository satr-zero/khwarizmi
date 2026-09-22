import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for managing Windows Autostart (Run on Startup)
/// via the standard Windows Registry key:
/// `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`
class WindowsAutostartService {
  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appName = 'Khwarizmi';
  static const String _prefsAutostartKey = 'khwarizmi_autostart_enabled';
  static const String _firstRunDoneKey = 'khwarizmi_autostart_first_run_done';

  /// Initializes default autostart setting on first app launch (Enabled by default).
  static Future<void> initDefaultAutostart() async {
    if (!Platform.isWindows) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final firstRunDone = prefs.getBool(_firstRunDoneKey) ?? false;

      if (!firstRunDone) {
        debugPrint('[WindowsAutostartService] First run detected. Enabling autostart by default.');
        await setAutostart(true);
        await prefs.setBool(_firstRunDoneKey, true);
      }
    } catch (e) {
      debugPrint('[WindowsAutostartService] Error initializing default autostart: $e');
    }
  }

  /// Checks whether autostart is currently enabled.
  /// Checks both SharedPreferences and queries the Windows Registry directly.
  static Future<bool> isAutostartEnabled() async {
    if (!Platform.isWindows) return false;

    try {
      final result = await Process.run('reg', [
        'query',
        _registryKey,
        '/v',
        _appName,
      ]);

      if (result.exitCode == 0 && result.stdout.toString().contains(_appName)) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[WindowsAutostartService] Error querying registry: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsAutostartKey) ?? true;
    }
  }

  /// Enables or disables autostart in the Windows Registry.
  static Future<bool> setAutostart(bool enable) async {
    if (!Platform.isWindows) return false;

    try {
      final prefs = await SharedPreferences.getInstance();

      if (enable) {
        final executablePath = Platform.resolvedExecutable;
        // Arguments to start minimized directly to Tray on boot
        final commandValue = '"$executablePath" --autostart';

        final result = await Process.run('reg', [
          'add',
          _registryKey,
          '/v',
          _appName,
          '/t',
          'REG_SZ',
          '/d',
          commandValue,
          '/f',
        ]);

        if (result.exitCode == 0) {
          await prefs.setBool(_prefsAutostartKey, true);
          debugPrint('[WindowsAutostartService] Autostart successfully enabled in registry.');
          return true;
        } else {
          debugPrint('[WindowsAutostartService] reg add failed with code ${result.exitCode}: ${result.stderr}');
          return false;
        }
      } else {
        final result = await Process.run('reg', [
          'delete',
          _registryKey,
          '/v',
          _appName,
          '/f',
        ]);

        // exitCode 0: deleted successfully, or 1: key didn't exist
        await prefs.setBool(_prefsAutostartKey, false);
        debugPrint('[WindowsAutostartService] Autostart disabled in registry (code: ${result.exitCode}).');
        return true;
      }
    } catch (e) {
      debugPrint('[WindowsAutostartService] Error toggling autostart: $e');
      return false;
    }
  }
}
