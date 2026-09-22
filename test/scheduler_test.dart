import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';
import 'package:khwarizmi/features/scheduler/domain/entities/reminder_item.dart';
import 'package:khwarizmi/features/scheduler/services/scheduler_service.dart';
import 'package:khwarizmi/features/tools/built_in/reminder_tools.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_scheduler_test_');
    testDbPath = '${tempDir.path}/test_scheduler.db';
    await MemoryDatabase.initialize(customPath: testDbPath);
    await ReminderDatabase.initialize();
  });

  tearDownAll(() async {
    MemoryDatabase.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await ReminderDatabase.clearAll();
  });

  group('Phase 3 Scheduler & Reminders Tests', () {
    test('ReminderDatabase stores, retrieves, and updates ReminderItem', () async {
      final item = ReminderItem(
        id: 'rem_1',
        title: 'اجتماع مع فريق التطوير',
        description: 'مراجعة خوارزمي v1',
        scheduledTime: DateTime.now().add(const Duration(hours: 2)),
        recurrence: 'once',
        createdAt: DateTime.now(),
      );

      await ReminderDatabase.insertReminder(item);

      final all = await ReminderDatabase.getAllReminders();
      expect(all.length, equals(1));
      expect(all.first.id, equals('rem_1'));
      expect(all.first.title, equals('اجتماع مع فريق التطوير'));
      expect(all.first.description, equals('مراجعة خوارزمي v1'));
      expect(all.first.isCompleted, isFalse);

      // Mark completed
      await ReminderDatabase.markCompleted('rem_1');
      final updated = await ReminderDatabase.getAllReminders();
      expect(updated.first.isCompleted, isTrue);
      expect(updated.first.completedAt, isNotNull);
    });

    test('ReminderDatabase filters due reminders accurately', () async {
      final pastItem = ReminderItem(
        id: 'past_1',
        title: 'مهمة قديمة مستحقة',
        scheduledTime: DateTime.now().subtract(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );

      final futureItem = ReminderItem(
        id: 'future_1',
        title: 'مهمة مستقبلية',
        scheduledTime: DateTime.now().add(const Duration(hours: 5)),
        createdAt: DateTime.now(),
      );

      await ReminderDatabase.insertReminder(pastItem);
      await ReminderDatabase.insertReminder(futureItem);

      final due = await ReminderDatabase.getDueReminders(DateTime.now());
      expect(due.length, equals(1));
      expect(due.first.id, equals('past_1'));
    });

    test('SchedulerService schedules and lists active reminders', () async {
      final reminder = await SchedulerService.instance.scheduleReminder(
        title: 'شرب الماء وأخذ استراحة',
        scheduledTime: DateTime.now().add(const Duration(minutes: 45)),
        recurrence: 'daily',
      );

      expect(reminder.id.isNotEmpty, isTrue);
      expect(reminder.title, equals('شرب الماء وأخذ استراحة'));

      final active = await SchedulerService.instance.getActiveReminders();
      expect(active.any((r) => r.id == reminder.id), isTrue);

      // Cancel reminder
      await SchedulerService.instance.cancelReminder(reminder.id);
      final activeAfterCancel = await SchedulerService.instance.getActiveReminders();
      expect(activeAfterCancel.any((r) => r.id == reminder.id), isFalse);
    });

    test('ScheduleReminderTool supports relative offset "+30m" and ISO strings', () async {
      ToolRegistry.initialize();

      final tool = ScheduleReminderTool();

      // Relative offset
      final output1 = await tool.execute({
        'title': 'مراجعة الكود',
        'scheduled_time': '+30m',
        'recurrence': 'once',
      });

      final json1 = jsonDecode(output1) as Map<String, dynamic>;
      expect(json1['status'], equals('success'));
      expect(json1.containsKey('reminder_id'), isTrue);

      // ISO String
      final output2 = await tool.execute({
        'title': 'دفع الفاتورة',
        'scheduled_time': '2026-10-01T10:00:00',
        'recurrence': 'monthly',
      });

      final json2 = jsonDecode(output2) as Map<String, dynamic>;
      expect(json2['status'], equals('success'));
      expect(json2['title'], equals('دفع الفاتورة'));
    });

    test('ListRemindersTool and CancelReminderTool execute cleanly', () async {
      ToolRegistry.initialize();

      // Add a reminder
      final schedTool = ScheduleReminderTool();
      final schedRes = await schedTool.execute({
        'title': 'اختبار الإلغاء',
        'scheduled_time': '+15m',
      });
      final reminderId = (jsonDecode(schedRes) as Map<String, dynamic>)['reminder_id'] as String;

      // List reminders
      final listTool = ListRemindersTool();
      final listOutput = await listTool.execute({});
      final listJson = jsonDecode(listOutput) as Map<String, dynamic>;
      expect(listJson['status'], equals('success'));
      expect((listJson['reminders'] as List).isNotEmpty, isTrue);

      // Cancel reminder
      final cancelTool = CancelReminderTool();
      final cancelOutput = await cancelTool.execute({'id': reminderId});
      final cancelJson = jsonDecode(cancelOutput) as Map<String, dynamic>;
      expect(cancelJson['status'], equals('success'));
    });

    test('ReminderDatabase.getMissedReminders accurately detects past uncompleted reminders', () async {
      final pastUncompleted = ReminderItem(
        id: 'past_uncompleted',
        title: 'تذكير فائت تجريبي',
        scheduledTime: DateTime.now().subtract(const Duration(minutes: 30)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final pastCompleted = ReminderItem(
        id: 'past_completed',
        title: 'تذكير قديم مكتمل',
        scheduledTime: DateTime.now().subtract(const Duration(minutes: 40)),
        isCompleted: true,
        completedAt: DateTime.now().subtract(const Duration(minutes: 35)),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      final futureItem = ReminderItem(
        id: 'future_item',
        title: 'تذكير مستقبلي',
        scheduledTime: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
      );

      await ReminderDatabase.insertReminder(pastUncompleted);
      await ReminderDatabase.insertReminder(pastCompleted);
      await ReminderDatabase.insertReminder(futureItem);

      final missed = await ReminderDatabase.getMissedReminders(DateTime.now());
      expect(missed.length, equals(1));
      expect(missed.first.id, equals('past_uncompleted'));
      expect(missed.first.title, equals('تذكير فائت تجريبي'));
    });

    test('SchedulerService.checkMissedRemindersOnBoot processes missed reminders and applies recurrence', () async {
      // 1. Once reminder (should be marked completed)
      final pastOnce = ReminderItem(
        id: 'past_once',
        title: 'موعد فائت لمرة واحدة',
        scheduledTime: DateTime.now().subtract(const Duration(hours: 2)),
        recurrence: 'once',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      // 2. Daily recurring reminder (should be rescheduled to the future)
      final pastDaily = ReminderItem(
        id: 'past_daily',
        title: 'ورد يومي فائت',
        scheduledTime: DateTime.now().subtract(const Duration(hours: 3)),
        recurrence: 'daily',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      await ReminderDatabase.insertReminder(pastOnce);
      await ReminderDatabase.insertReminder(pastDaily);

      // Run boot check
      await SchedulerService.instance.checkMissedRemindersOnBoot();

      // Verify pastOnce is completed
      final all = await ReminderDatabase.getAllReminders();
      final updatedOnce = all.firstWhere((r) => r.id == 'past_once');
      expect(updatedOnce.isCompleted, isTrue);

      // Verify pastDaily is rescheduled to future and not completed
      final updatedDaily = all.firstWhere((r) => r.id == 'past_daily');
      expect(updatedDaily.isCompleted, isFalse);
      expect(updatedDaily.scheduledTime.isAfter(DateTime.now()), isTrue);
    });
  });
}
