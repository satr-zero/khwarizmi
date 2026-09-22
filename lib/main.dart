import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/features/skills/services/skill_service.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/agent/data/task_database.dart';
import 'features/agent/services/task_execution_engine.dart';
import 'features/projects/data/project_database.dart';
import 'features/chat/data/chat_history_database.dart';
import 'features/chat/presentation/screens/chat_screen.dart';
import 'features/memory/data/memory_database.dart';
import 'features/scheduler/data/reminder_database.dart';
import 'features/scheduler/services/notification_service.dart';
import 'features/scheduler/services/tray_service.dart';
import 'features/scheduler/services/windows_autostart_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  await MemoryDatabase.initialize();
  await TaskDatabase.initialize(); // مرحلة 7: جدول المهام المستقلة
  await TaskExecutionEngine.instance.recoverInterruptedTasks(); // استعادة المهام المنقطعة
  await ProjectDatabase.initialize(); // مرحلة 9: جداول المشاريع وربط المحادثات
  await ChatHistoryDatabase.initialize(); // سجل المحادثات
  await SkillDatabase.initialize(); // مرحلة 8: قاعدة بيانات الإضافات والـ Skills
  await ReminderDatabase.initialize();
  await NotificationService.initialize();
  await TrayService.instance.initialize();
  await WindowsAutostartService.initDefaultAutostart();

  // تهيئة الأدوات واكتشاف الإضافات الخارجية والمهارات النصية
  ToolRegistry.initialize();
  await SkillService.instance.scanAndDiscoverSkills();
  await TextSkillService.instance.scanAndDiscoverTextSkills();

  final isAutostart =
      args.contains('--autostart') || args.contains('--minimized');

  if (Platform.isWindows) {
    const windowOptions = WindowOptions(
      size: Size(1100, 750),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'خوارزمي — Khwarizmi AI Agent',
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (isAutostart) {
        await windowManager.hide();
        debugPrint(
          '[Main] Khwarizmi started in background via autostart mode. Window hidden to system tray.',
        );
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  runApp(const ProviderScope(child: KhwarizmiApp()));
}

class KhwarizmiApp extends ConsumerWidget {
  const KhwarizmiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'خوارزمي — Khwarizmi AI Agent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      // Arabic / RTL Support
      locale: const Locale('ar', 'SA'),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      home: const ChatScreen(),
    );
  }
}
