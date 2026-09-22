import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/memory/domain/entities/memory_entry.dart';
import 'package:khwarizmi/features/memory/services/embedding_service.dart';
import 'package:khwarizmi/features/tools/built_in/memory_tools.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_memory_test_');
    testDbPath = '${tempDir.path}/test_memory.db';
    await MemoryDatabase.initialize(customPath: testDbPath);
  });

  tearDownAll(() async {
    MemoryDatabase.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await MemoryDatabase.clearAll();
  });

  group('Phase 1 & 2 Memory Engine Tests', () {
    test('MemoryDatabase correctly inserts and retrieves MemoryEntry with BLOB embedding', () async {
      final dummyEmbedding = [0.1, 0.2, 0.3, 0.4, 0.5];
      final entry = MemoryEntry(
        id: 'mem_1',
        content: 'المستخدم يفضل لغة دارت ومشاريع فلاتر',
        category: 'preference',
        createdAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
        importance: 4,
        embedding: dummyEmbedding,
      );

      await MemoryDatabase.insertMemory(entry);

      final all = await MemoryDatabase.getAllMemories();
      expect(all.length, equals(1));
      expect(all.first.id, equals('mem_1'));
      expect(all.first.content, equals('المستخدم يفضل لغة دارت ومشاريع فلاتر'));
      expect(all.first.category, equals('preference'));
      expect(all.first.importance, equals(4));
      expect(all.first.embedding, isNotNull);
      expect(all.first.embedding!.length, equals(5));
      expect((all.first.embedding![0] - 0.1).abs() < 0.0001, isTrue);
    });

    test('Cosine similarity accurately computes angle between vectors', () {
      final a = [1.0, 0.0, 0.0];
      final b = [1.0, 0.0, 0.0];
      final c = [0.0, 1.0, 0.0];
      final d = [-1.0, 0.0, 0.0];

      // Identical vectors: similarity is 1.0
      expect((EmbeddingService.cosineSimilarity(a, b) - 1.0).abs() < 0.0001, isTrue);

      // Orthogonal vectors: similarity is 0.0
      expect((EmbeddingService.cosineSimilarity(a, c) - 0.0).abs() < 0.0001, isTrue);

      // Opposite vectors: similarity is -1.0
      expect((EmbeddingService.cosineSimilarity(a, d) - (-1.0)).abs() < 0.0001, isTrue);
    });

    test('MemoryDatabase text search finds matching entries', () async {
      final entry1 = MemoryEntry(
        id: 'mem_1',
        content: 'اسم المستخدم هو عبد الرحمن ويسكن في الرياض',
        category: 'identity',
        createdAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
        importance: 5,
      );
      final entry2 = MemoryEntry(
        id: 'mem_2',
        content: 'مشروع خوارزمي مبني بنظام الوكلاء المستقلين',
        category: 'project',
        createdAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
        importance: 3,
      );

      await MemoryDatabase.insertMemory(entry1);
      await MemoryDatabase.insertMemory(entry2);

      final results = await MemoryDatabase.searchByText('عبد الرحمن');
      expect(results.length, equals(1));
      expect(results.first.id, equals('mem_1'));

      final projectResults = await MemoryDatabase.searchByText('خوارزمي');
      expect(projectResults.length, equals(1));
      expect(projectResults.first.id, equals('mem_2'));
    });

    test('MemoryRepository hybrid search scores and ranks memories', () async {
      await MemoryRepository.storeMemory(
        content: 'المستخدم يفضل الردود المباشرة والمختصرة دائماً',
        category: 'preference',
        importance: 5,
      );
      await MemoryRepository.storeMemory(
        content: 'خوارزمي يعمل على نظام ويندوز فقط',
        category: 'system',
        importance: 2,
      );

      final searchResults = await MemoryRepository.searchMemory(
        query: 'ما هو الأسلوب المفضل للردود؟',
        minScore: 0.1,
      );

      expect(searchResults.isNotEmpty, isTrue);
      expect(searchResults.first.entry.content.contains('المباشرة والمختصرة'), isTrue);
    });

    test('StoreMemoryTool and SearchMemoryTool execute cleanly via ToolRegistry', () async {
      ToolRegistry.initialize();

      // Store a memory via tool
      final storeTool = StoreMemoryTool();
      final storeOutput = await storeTool.execute({
        'content': 'مفتاح المشروع هو خوارزمي الذكي 2026',
        'category': 'secret',
        'importance': 5,
      });

      expect(storeOutput.contains('"status":"success"'), isTrue);

      // Search via tool
      final searchTool = SearchMemoryTool();
      final searchOutput = await searchTool.execute({
        'query': 'خوارزمي الذكي',
      });

      expect(searchOutput.contains('"status":"success"'), isTrue);
      expect(searchOutput.contains('خوارزمي الذكي 2026'), isTrue);
    });

    test('Offline resilience: memory stored without embedding is searchable and gets vector populated after sync', () async {
      // 1. Store memory without API key (simulating offline mode)
      final offlineMemory = await MemoryRepository.storeMemory(
        content: 'المستخدم يحب القهوة السوداء في الصباح',
        category: 'preference',
        importance: 4,
        apiKey: null, // No internet / no API key
      );

      expect(offlineMemory.embedding, isNull);

      // 2. Verify that pending count is 1
      expect(await MemoryRepository.getPendingEmbeddingsCount(), equals(1));
      final pendingList = await MemoryDatabase.getMemoriesPendingEmbedding();
      expect(pendingList.length, equals(1));
      expect(pendingList.first.id, equals(offlineMemory.id));

      // 3. Verify it is still searchable immediately via keyword/text matching
      final searchBeforeSync = await MemoryRepository.searchMemory(
        query: 'القهوة السوداء',
        minScore: 0.1,
      );
      expect(searchBeforeSync.isNotEmpty, isTrue);
      expect(searchBeforeSync.first.entry.content, contains('القهوة السوداء'));
      expect(searchBeforeSync.first.entry.embedding, isNull);

      // 4. Simulate syncing/backfilling embedding (e.g. after internet returns)
      final dummySyncedVector = List<double>.filled(768, 0.05);
      await MemoryDatabase.updateMemoryEmbedding(offlineMemory.id, dummySyncedVector);

      // 5. Verify pending count is now 0
      expect(await MemoryRepository.getPendingEmbeddingsCount(), equals(0));

      // 6. Retrieve memory and verify vector is now populated and accurate
      final all = await MemoryDatabase.getAllMemories();
      final updated = all.firstWhere((m) => m.id == offlineMemory.id);
      expect(updated.embedding, isNotNull);
      expect(updated.embedding!.length, equals(768));
      expect((updated.embedding![0] - 0.05).abs() < 0.0001, isTrue);
    });
  });
}
