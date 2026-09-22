import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/scheduler/services/windows_autostart_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WindowsAutostartService reads and writes to Windows registry', () async {
    if (!Platform.isWindows) return;

    SharedPreferences.setMockInitialValues({});

    // Test enabling
    final enabled = await WindowsAutostartService.setAutostart(true);
    expect(enabled, isTrue);

    final isEnabled = await WindowsAutostartService.isAutostartEnabled();
    expect(isEnabled, isTrue);

    // Test disabling
    final disabled = await WindowsAutostartService.setAutostart(false);
    expect(disabled, isTrue);

    final isEnabledAfterDelete = await WindowsAutostartService.isAutostartEnabled();
    expect(isEnabledAfterDelete, isFalse);

    // Re-enable for final state as per specification (default enabled)
    await WindowsAutostartService.setAutostart(true);
    expect(await WindowsAutostartService.isAutostartEnabled(), isTrue);
  });
}
