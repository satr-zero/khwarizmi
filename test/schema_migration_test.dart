import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/projects/data/project_database.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';
import 'package:khwarizmi/features/scheduler/domain/entities/reminder_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_migration_test_');
    testDbPath = '${tempDir.path}/legacy_v1.db';
  });

  tearDown(() async {
    MemoryDatabase.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('Legacy database without schema_version or projects is automatically migrated to V2', () async {
    // 1. محاكاة قاعدة بيانات قديمة (v1) أُنشئت يدويًا بمخطط الذكريات فقط
    final rawDb = sqlite3.open(testDbPath);
    rawDb.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'fact',
        importance INTEGER NOT NULL DEFAULT 5,
        created_at INTEGER NOT NULL,
        last_accessed INTEGER NOT NULL,
        access_count INTEGER NOT NULL DEFAULT 0,
        source_conversation_id TEXT
      );
    ''');
    // إدخال بيانات سابقة للتأكد من عدم فقدانها
    rawDb.execute('''
      INSERT INTO memories (id, content, category, importance, created_at, last_accessed, access_count)
      VALUES ('mem_legacy_1', 'اسم المستخدم أحمد', 'fact', 10, 1700000000000, 1700000000000, 1);
    ''');
    rawDb.dispose();

    // 2. تشغيل MemoryDatabase.initialize على هذه القاعدة القديمة
    await MemoryDatabase.initialize(customPath: testDbPath);

    // 3. التحقق من إنشاء جدول schema_version وترقيته للإصدار 2
    final versionRows = await MemoryDatabase.queryRaw('SELECT version FROM schema_version LIMIT 1');
    expect(versionRows.isNotEmpty, isTrue);
    expect((versionRows.first['version'] as num).toInt(), equals(2));

    // 4. التحقق من سلامة البيانات القديمة (لم تُحذف)
    final memoryRows = await MemoryDatabase.queryRaw('SELECT * FROM memories WHERE id = ?', ['mem_legacy_1']);
    expect(memoryRows.isNotEmpty, isTrue);
    expect(memoryRows.first['content'], equals('اسم المستخدم أحمد'));

    // 5. التحقق من وجود جدول projects الجديد والقدرة على الكتابة والقراءة منه
    await ProjectDatabase.initialize();
    final p = await ProjectDatabase.upsertProject(
      name: 'مشروع تجريبي جديد',
      rootPath: 'C:\\test\\demo',
    );
    expect(p.name, equals('مشروع تجريبي جديد'));
    final recentProjects = await ProjectDatabase.getRecentProjects();
    expect(recentProjects.any((proj) => proj.name == 'مشروع تجريبي جديد'), isTrue);

    // 6. التحقق من وجود جدول reminders وإمكانية استخدام ReminderDatabase المحدثة
    await ReminderDatabase.initialize();
    final reminder = ReminderItem(
      id: 'rem_migrated_1',
      title: 'تذكير في بيئة مترقية',
      scheduledTime: DateTime.now().add(const Duration(hours: 1)),
      createdAt: DateTime.now(),
    );
    await ReminderDatabase.insertReminder(reminder);
    final reminders = await ReminderDatabase.getAllReminders();
    expect(reminders.any((r) => r.id == 'rem_migrated_1'), isTrue);
  });
}
