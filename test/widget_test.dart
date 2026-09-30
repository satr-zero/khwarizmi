// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/scheduler/services/scheduler_service.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/main.dart';

void main() {
  testWidgets('KhwarizmiApp smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await MemoryDatabase.initialize(customPath: ':memory:');
    await SkillDatabase.initialize();

    await tester.pumpWidget(
      const ProviderScope(
        child: KhwarizmiApp(),
      ),
    );
    await tester.pump();

    // Verify that the brand title is rendered
    expect(find.text('خوارزمي'), findsWidgets);

    SchedulerService.instance.stop();
  });
}
