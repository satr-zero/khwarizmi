import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:khwarizmi/features/memory/domain/entities/memory_entry.dart';

/// A lightweight non-reentrant mutex backed by a Dart [Completer] chain.
///
/// All SQLite operations in [MemoryDatabase] are wrapped in [_lock] so that
/// only one caller at a time accesses the shared [Database] connection.  This
/// prevents "database is locked" errors that occur when the agent loop writes
/// a memory on a background Future while the UI simultaneously tries to read
/// the same table.
class _Mutex {
  Future<void> _chain = Future.value();

  Future<T> protect<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _chain = _chain.whenComplete(() async {
      try {
        final result = await fn();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

class MemoryDatabase {
  static Database? _db;
  static bool _isInitialized = false;

  /// Single mutex serialising all DB access — prevents race conditions and
  /// "database is locked" crashes when the agent loop and the UI both touch
  /// SQLite at the same time.
  static final _Mutex _mutex = _Mutex();

  static Database get _instance {
    if (_db == null) {
      throw StateError(
          'MemoryDatabase has not been initialized. Call initialize() first.');
    }
    return _db!;
  }

  // ── Initialization ────────────────────────────────────────────────────────

  static Future<void> initialize({String? customPath}) async {
    if (_isInitialized && _db != null) return;

    String dbPath;
    if (customPath != null) {
      dbPath = customPath;
    } else {
      try {
        final appDir = await getApplicationSupportDirectory();
        final dir = Directory(p.join(appDir.path, 'Khwarizmi'));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        dbPath = p.join(dir.path, 'khwarizmi_memory.db');
      } catch (e) {
        dbPath = 'khwarizmi_memory.db';
      }
    }

    _db = sqlite3.open(dbPath);
    _db!.execute('PRAGMA busy_timeout=5000;');
    _db!.execute('PRAGMA journal_mode=WAL;');
    _db!.execute('PRAGMA synchronous=NORMAL;');
    _createTables(_db!);
    _isInitialized = true;
    debugPrint('[MemoryDatabase] Initialized SQLite at: $dbPath');
  }

  static void _createTables(Database db) {
    // WAL mode: readers never block writers and writers never block readers,
    // which eliminates the most common source of "database is locked" on Windows.
    db.execute('PRAGMA busy_timeout=5000;');
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA synchronous=NORMAL;');

    // ── نظام الترحيل المركزي (schema_version) ──────────────────────────────
    // يُنشئ جدول الإصدارات ويطبّق كل الترحيلات المفقودة بالتسلسل.
    // لإضافة تغيير مستقبلي: أضف migration جديدة في _migrations مع رقم أعلى.
    _runMigrations(db);
  }

  // ── Schema Migration System ───────────────────────────────────────────────

  /// الإصدار الحالي لمخطط قاعدة البيانات.
  static const int _currentSchemaVersion = 2;

  /// يطبّق جميع الترحيلات الناقصة بالتسلسل على [db].
  static void _runMigrations(Database db) {
    // إنشاء جدول تتبع الإصدار (لا يُلمس بعد ذلك)
    db.execute('''
      CREATE TABLE IF NOT EXISTS schema_version (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        version INTEGER NOT NULL
      );
    ''');

    // قراءة الإصدار الحالي
    final versionRows = db.select('SELECT version FROM schema_version WHERE id = 1');
    int currentVersion = versionRows.isEmpty ? 0 : (versionRows.first['version'] as int);

    debugPrint('[MemoryDatabase] DB schema version: $currentVersion → target: $_currentSchemaVersion');

    // تطبيق الترحيلات المفقودة
    if (currentVersion < 1) _migrateV1(db);
    if (currentVersion < 2) _migrateV2(db);

    // تسجيل الإصدار الجديد
    db.execute('''
      INSERT INTO schema_version (id, version) VALUES (1, $_currentSchemaVersion)
      ON CONFLICT(id) DO UPDATE SET version = $_currentSchemaVersion;
    ''');

    debugPrint('[MemoryDatabase] Schema migration complete. Version: $_currentSchemaVersion');
  }

  /// الترحيل 1: الجداول الأساسية (memories + الإصدار الأولي للمشروع).
  static void _migrateV1(Database db) {
    debugPrint('[MemoryDatabase] Applying migration v1: core tables.');
    db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'general',
        created_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL,
        access_count INTEGER NOT NULL DEFAULT 0,
        importance INTEGER NOT NULL DEFAULT 1,
        embedding BLOB
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at);');
  }

  /// الترحيل 2: جداول المشاريع وربط المحادثات.
  /// يضمن وجود جداول projects و conversation_projects في كل قاعدة بيانات
  /// سواء أُنشئت حديثًا أو كانت موجودة قبل المرحلة 9.
  static void _migrateV2(Database db) {
    debugPrint('[MemoryDatabase] Applying migration v2: projects tables.');
    db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        root_path TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        last_opened_at INTEGER NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_projects (
        conversation_id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        linked_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_projects_path ON projects(root_path);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_conv_proj_project ON conversation_projects(project_id);');
  }



  // ── Write operations (all async — never block the UI thread) ─────────────

  static Future<void> insertMemory(MemoryEntry entry) {
    return _mutex.protect(() async {
      final map = entry.toMap();
      final stmt = _instance.prepare('''
        INSERT OR REPLACE INTO memories (
          id, content, category, created_at, last_accessed_at,
          access_count, importance, embedding
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      try {
        stmt.execute([
          map['id'],
          map['content'],
          map['category'],
          map['created_at'],
          map['last_accessed_at'],
          map['access_count'],
          map['importance'],
          map['embedding'],
        ]);
      } finally {
        stmt.dispose();
      }
    });
  }

  static Future<void> updateAccessStats(String id) {
    return _mutex.protect(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      _instance.execute('''
        UPDATE memories
        SET last_accessed_at = ?, access_count = access_count + 1
        WHERE id = ?
      ''', [now, id]);
    });
  }

  static Future<void> updateMemoryEmbedding(String id, List<double> embedding) {
    return _mutex.protect(() async {
      final blob = MemoryEntry.floatsToBytes(embedding);
      _instance.execute(
          'UPDATE memories SET embedding = ? WHERE id = ?', [blob, id]);
    });
  }

  static Future<void> deleteMemory(String id) {
    return _mutex.protect(() async {
      _instance.execute('DELETE FROM memories WHERE id = ?', [id]);
    });
  }

  static Future<void> clearAll() {
    return _mutex.protect(() async {
      _instance.execute('DELETE FROM memories');
    });
  }

  // ── Read operations (all async — never block the UI thread) ──────────────

  static Future<List<MemoryEntry>> getAllMemories({int limit = 100}) {
    return _mutex.protect(() async {
      final results = _instance.select(
        'SELECT * FROM memories ORDER BY created_at DESC LIMIT ?',
        [limit],
      );
      return results.map((row) => MemoryEntry.fromMap(row)).toList();
    });
  }

  static Future<List<MemoryEntry>> searchByText(String query, {int limit = 20}) {
    return _mutex.protect(() async {
      final cleaned = '%${query.trim()}%';
      final results = _instance.select(
        '''
        SELECT * FROM memories
        WHERE content LIKE ? OR category LIKE ?
        ORDER BY importance DESC, last_accessed_at DESC
        LIMIT ?
        ''',
        [cleaned, cleaned, limit],
      );
      return results.map((row) => MemoryEntry.fromMap(row)).toList();
    });
  }

  static Future<List<MemoryEntry>> getMemoriesPendingEmbedding({int limit = 50}) {
    return _mutex.protect(() async {
      final results = _instance.select(
        'SELECT * FROM memories WHERE embedding IS NULL ORDER BY created_at DESC LIMIT ?',
        [limit],
      );
      return results.map((row) => MemoryEntry.fromMap(row)).toList();
    });
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  static void close() {
    _db?.dispose();
    _db = null;
    _isInitialized = false;
  }

  // ── Raw SQL helpers (for TaskDatabase and other internal tables) ──────────

  /// Executes a raw SQL statement (INSERT/UPDATE/CREATE/DELETE) inside the shared mutex.
  static Future<void> executeRaw(String sql, [List<Object?> params = const []]) {
    return _mutex.protect(() async {
      _instance.execute(sql, params);
    });
  }

  /// Executes a raw SELECT query inside the shared mutex and returns results.
  static Future<List<Map<String, dynamic>>> queryRaw(
    String sql, [
    List<Object?> params = const [],
  ]) {
    return _mutex.protect(() async {
      final results = _instance.select(sql, params);
      return results.map((row) {
        final map = <String, dynamic>{};
        for (final col in row.keys) {
          map[col] = row[col];
        }
        return map;
      }).toList();
    });
  }
}
