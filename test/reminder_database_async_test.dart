import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';
import 'package:khwarizmi/features/scheduler/domain/entities/reminder_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_reminder_async_test_');
    testDbPath = '${tempDir.path}/test_async_reminders.db';
    await MemoryDatabase.initialize(customPath: testDbPath);
    await ReminderDatabase.initialize();
  });

  tearDownAll(() async {
    MemoryDatabase.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    await ReminderDatabase.clearAll();
  });

  group('ReminderDatabase Async Operations & Concurrency', () {
    test('insertReminder, getReminderById, and getAllReminders work asynchronously', () async {
      final item = ReminderItem(
        id: 'r_async_1',
        title: 'مراجعة الكود مع الفريق',
        description: 'فحص جودة كود خوارزمي',
        scheduledTime: DateTime.now().add(const Duration(minutes: 30)),
        recurrence: 'once',
        createdAt: DateTime.now(),
      );

      await ReminderDatabase.insertReminder(item);

      final fetched = await ReminderDatabase.getReminderById('r_async_1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('مراجعة الكود مع الفريق'));
      expect(fetched.description, equals('فحص جودة كود خوارزمي'));

      final all = await ReminderDatabase.getAllReminders();
      expect(all.length, equals(1));
    });

    test('updateReminder and markCompleted persist correctly', () async {
      final item = ReminderItem(
        id: 'r_async_2',
        title: 'مهمة للتعديل',
        scheduledTime: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
      );

      await ReminderDatabase.insertReminder(item);

      final updated = item.copyWith(
        title: 'مهمة معدلة بنجاح',
        description: 'تم إضافة تفاصيل جديدة',
      );
      await ReminderDatabase.updateReminder(updated);

      final afterUpdate = await ReminderDatabase.getReminderById('r_async_2');
      expect(afterUpdate!.title, equals('مهمة معدلة بنجاح'));
      expect(afterUpdate.description, equals('تم إضافة تفاصيل جديدة'));

      // Mark completed
      await ReminderDatabase.markCompleted('r_async_2');
      final afterCompleted = await ReminderDatabase.getReminderById('r_async_2');
      expect(afterCompleted!.isCompleted, isTrue);
      expect(afterCompleted.completedAt, isNotNull);
    });

    test('deleteReminder and clearAll work correctly', () async {
      final item1 = ReminderItem(
        id: 'r_del_1',
        title: 'تذكير 1',
        scheduledTime: DateTime.now().add(const Duration(minutes: 10)),
        createdAt: DateTime.now(),
      );
      final item2 = ReminderItem(
        id: 'r_del_2',
        title: 'تذكير 2',
        scheduledTime: DateTime.now().add(const Duration(minutes: 20)),
        createdAt: DateTime.now(),
      );

      await ReminderDatabase.insertReminder(item1);
      await ReminderDatabase.insertReminder(item2);

      expect((await ReminderDatabase.getAllReminders()).length, equals(2));

      await ReminderDatabase.deleteReminder('r_del_1');
      final remaining = await ReminderDatabase.getAllReminders();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('r_del_2'));

      await ReminderDatabase.clearAll();
      expect((await ReminderDatabase.getAllReminders()).isEmpty, isTrue);
    });

    test('getDueReminders and getMissedReminders return accurate results', () async {
      final now = DateTime.now();
      final pastUncompleted = ReminderItem(
        id: 'r_missed',
        title: 'فائت',
        scheduledTime: now.subtract(const Duration(minutes: 15)),
        createdAt: now.subtract(const Duration(hours: 1)),
      );
      final future = ReminderItem(
        id: 'r_future',
        title: 'مستقبلي',
        scheduledTime: now.add(const Duration(minutes: 45)),
        createdAt: now,
      );

      await ReminderDatabase.insertReminder(pastUncompleted);
      await ReminderDatabase.insertReminder(future);

      final due = await ReminderDatabase.getDueReminders(now);
      expect(due.length, equals(1));
      expect(due.first.id, equals('r_missed'));

      final missed = await ReminderDatabase.getMissedReminders(now);
      expect(missed.length, equals(1));
      expect(missed.first.id, equals('r_missed'));
    });

    test('Concurrent writes do not deadlock and share DB lock safely', () async {
      final futures = <Future<void>>[];
      for (int i = 0; i < 20; i++) {
        final item = ReminderItem(
          id: 'concurrent_r_$i',
          title: 'تذكير متزامن $i',
          scheduledTime: DateTime.now().add(Duration(minutes: i + 1)),
          createdAt: DateTime.now(),
        );
        futures.add(ReminderDatabase.insertReminder(item));
      }

      await Future.wait(futures);

      final all = await ReminderDatabase.getAllReminders();
      expect(all.length, equals(20));
    });
  });
}
