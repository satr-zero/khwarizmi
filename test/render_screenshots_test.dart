import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/core/theme/app_theme.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/screens/chat_screen.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/settings_dialog.dart';
import 'package:khwarizmi/features/chat/presentation/widgets/tool_call_card.dart';
import 'package:khwarizmi/features/memory/presentation/widgets/memory_viewer_dialog.dart';
import 'package:khwarizmi/features/scheduler/presentation/widgets/reminders_viewer_dialog.dart';

import 'package:khwarizmi/features/scheduler/services/scheduler_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> saveScreenshot(WidgetTester tester, String filename) async {
    await tester.runAsync(() async {
      final finder = find.byType(RepaintBoundary).first;
      final boundary = tester.renderObject(finder) as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final dir = Directory('build/screenshots');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final file = File('build/screenshots/$filename');
        file.writeAsBytesSync(byteData.buffer.asUint8List());
      }
    });
  }

  testWidgets('Capture Light and Dark Screenshots of Main Screens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      SchedulerService.instance.stop();
    });

    // 1. ChatScreen - Standard (1100x750) - Dark Mode
    tester.view.physicalSize = const Size(1100, 750);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'chat_screen_dark.png');

    // 2. ChatScreen - Standard (1100x750) - Light Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'chat_screen_light.png');

    // 1b. ChatScreen - Compact (800x700) - Dark Mode
    tester.view.physicalSize = const Size(800, 700);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'chat_screen_compact_dark.png');

    // 2b. ChatScreen - Compact (800x700) - Light Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'chat_screen_compact_light.png');

    // 1c. ChatScreen - Wide (1500x850) - Dark Mode
    tester.view.physicalSize = const Size(1500, 850);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'chat_screen_wide_dark.png');

    // 2c. ChatScreen - Wide (1500x850) - Light Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'chat_screen_wide_light.png');

    // Reset size to 1100x750 for dialogs
    tester.view.physicalSize = const Size(1100, 750);

    // 3. Settings Dialog - Dark Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const Scaffold(body: SettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'settings_dialog_dark.png');

    // 4. Settings Dialog - Light Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const Scaffold(body: SettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'settings_dialog_light.png');

    // 5. Memory Viewer - Dark Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const Scaffold(body: MemoryViewerDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'memory_viewer_dark.png');

    // 6. Memory Viewer - Light Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const Scaffold(body: MemoryViewerDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'memory_viewer_light.png');

    // 7. Reminders Viewer - Dark Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const Scaffold(body: RemindersViewerDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'reminders_viewer_dark.png');

    // 8. Reminders Viewer - Light Mode
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: const Locale('ar', 'SA'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(child: child!),
          ),
          home: const Scaffold(body: RemindersViewerDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveScreenshot(tester, 'reminders_viewer_light.png');

    // 9. ToolCallCard 4 States Showcase - Dark Mode
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        locale: const Locale('ar', 'SA'),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: RepaintBoundary(child: child!),
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '1',
                    toolName: 'web_search',
                    arguments: {'query': 'أحدث أخبار التقنية'},
                    status: ToolCallStatus.running,
                  ),
                ),
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '2',
                    toolName: 'web_search',
                    arguments: {'query': 'أحدث أخبار التقنية'},
                    status: ToolCallStatus.success,
                    summary: 'وجد 5 نتائج بحث مطابقة',
                    result: '{"results": [{"title": "تقنية اليوم"}]}',
                  ),
                ),
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '3',
                    toolName: 'fetch_url',
                    arguments: {'url': 'https://example.com/api'},
                    status: ToolCallStatus.error,
                    summary: 'تعذر الإكمال: تعذر الاتصال بالخادم (HTTP 503)',
                    errorMessage: 'HTTP 503 Service Unavailable',
                  ),
                ),
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '4',
                    toolName: 'agent_browser',
                    arguments: {'action': 'purchase_checkout', 'amount': '150 USD'},
                    status: ToolCallStatus.awaitingConfirmation,
                    summary: 'بانتظار تأكيدك لمتابعة عملية الدفع...',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await saveScreenshot(tester, 'tool_call_cards_dark.png');

    // 10. ToolCallCard 4 States Showcase - Light Mode
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('ar', 'SA'),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: RepaintBoundary(child: child!),
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '1',
                    toolName: 'web_search',
                    arguments: {'query': 'أحدث أخبار التقنية'},
                    status: ToolCallStatus.running,
                  ),
                ),
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '2',
                    toolName: 'web_search',
                    arguments: {'query': 'أحدث أخبار التقنية'},
                    status: ToolCallStatus.success,
                    summary: 'وجد 5 نتائج بحث مطابقة',
                    result: '{"results": [{"title": "تقنية اليوم"}]}',
                  ),
                ),
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '3',
                    toolName: 'fetch_url',
                    arguments: {'url': 'https://example.com/api'},
                    status: ToolCallStatus.error,
                    summary: 'تعذر الإكمال: تعذر الاتصال بالخادم (HTTP 503)',
                    errorMessage: 'HTTP 503 Service Unavailable',
                  ),
                ),
                ToolCallCard(
                  toolCall: ToolCallInfo(
                    callId: '4',
                    toolName: 'agent_browser',
                    arguments: {'action': 'purchase_checkout', 'amount': '150 USD'},
                    status: ToolCallStatus.awaitingConfirmation,
                    summary: 'بانتظار تأكيدك لمتابعة عملية الدفع...',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await saveScreenshot(tester, 'tool_call_cards_light.png');

    SchedulerService.instance.stop();
  });
}
