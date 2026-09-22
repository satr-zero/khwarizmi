import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_concurrency_test_');
    testDbPath = '${tempDir.path}/test_concurrency.db';
    await MemoryDatabase.initialize(customPath: testDbPath);
    ReminderDatabase.initialize();
  });

  tearDownAll(() async {
    MemoryDatabase.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('Concurrent DB writes and reads during active agent simulation do not lock or throw', () async {
    // Simulate active agent loop constantly writing and querying memory
    final List<Future> operations = [];

    for (int i = 0; i < 50; i++) {
      // Background agent loop write
      operations.add(MemoryRepository.storeMemory(
        content: 'ملاحظة مهمة من الوكيل رقم $i أثناء توليد الرد',
        category: 'work',
        importance: (i % 5) + 1,
        apiKey: null, // offline
      ));

      // Concurrent UI opening / fetching memories
      operations.add(MemoryRepository.getAllMemories(limit: 100));

      // Concurrent search
      operations.add(MemoryRepository.searchMemory(
        query: 'ملاحظة $i',
        minScore: 0.1,
      ));

      // Concurrent pending count check
      operations.add(MemoryRepository.getPendingEmbeddingsCount());
    }

    // Await all 200 interleaved operations simultaneously
    final results = await Future.wait(operations);
    expect(results.length, equals(200));

    final all = await MemoryRepository.getAllMemories();
    expect(all.length, equals(50));
  });
}
