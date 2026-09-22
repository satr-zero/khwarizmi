import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';

/// إدارة مثابرة المهام المستقلة بنفس قاعدة بيانات SQLite الموجودة.
///
/// يستخدم نفس نمط [_Mutex] الموجود في [MemoryDatabase] لمنع race conditions.
class TaskDatabase {
  // يصل للـ DB المشترك عبر MemoryDatabase المهيأة مسبقاً
  static bool _tableCreated = false;

  // ── Initialization ────────────────────────────────────────────────────────

  /// يُنشئ جدول tasks إن لم يكن موجوداً.
  /// يُستدعى مرة واحدة عند بدء التطبيق.
  static Future<void> initialize() async {
    if (_tableCreated) return;
    try {
      // نستخدم نفس DB instance عبر MemoryDatabase._mutex
      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS tasks (
          id TEXT PRIMARY KEY,
          goal TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'running',
          steps_log TEXT NOT NULL DEFAULT '[]',
          step_count INTEGER NOT NULL DEFAULT 0,
          step_cap INTEGER NOT NULL DEFAULT 25,
          created_at INTEGER NOT NULL,
          completed_at INTEGER,
          pending_question TEXT,
          completion_summary TEXT,
          error_message TEXT,
          provider_id TEXT NOT NULL DEFAULT 'gemini',
          model_name TEXT NOT NULL DEFAULT ''
        );
      ''');
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);',
      );
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_tasks_created ON tasks(created_at);',
      );
      _tableCreated = true;
      debugPrint('[TaskDatabase] tasks table ready.');
    } catch (e) {
      debugPrint('[TaskDatabase] Initialization error: $e');
    }
  }

  // ── Write Operations ──────────────────────────────────────────────────────

  static Future<void> insertTask(Task task) async {
    final j = task.toJson();
    await MemoryDatabase.executeRaw('''
      INSERT OR REPLACE INTO tasks (
        id, goal, status, steps_log, step_count, step_cap,
        created_at, completed_at, pending_question, completion_summary,
        error_message, provider_id, model_name
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      j['id'],
      j['goal'],
      j['status'],
      j['stepsLog'],
      j['stepCount'],
      j['stepCap'],
      task.createdAt.millisecondsSinceEpoch,
      task.completedAt?.millisecondsSinceEpoch,
      j['pendingQuestion'],
      j['completionSummary'],
      j['errorMessage'],
      j['providerId'],
      j['modelName'],
    ]);
  }

  static Future<void> updateTask(Task task) => insertTask(task);

  static Future<void> updateTaskStatus(
    String id,
    TaskStatus status, {
    String? pendingQuestion,
    String? completionSummary,
    String? errorMessage,
    DateTime? completedAt,
  }) async {
    await MemoryDatabase.executeRaw('''
      UPDATE tasks SET
        status = ?,
        pending_question = ?,
        completion_summary = ?,
        error_message = ?,
        completed_at = ?
      WHERE id = ?
    ''', [
      status.name,
      pendingQuestion,
      completionSummary,
      errorMessage,
      completedAt?.millisecondsSinceEpoch,
      id,
    ]);
  }

  static Future<void> updateStepProgress(
    String id, {
    required int stepCount,
    required String stepsLogJson,
  }) async {
    await MemoryDatabase.executeRaw('''
      UPDATE tasks SET step_count = ?, steps_log = ? WHERE id = ?
    ''', [stepCount, stepsLogJson, id]);
  }

  static Future<void> deleteTask(String id) async {
    await MemoryDatabase.executeRaw('DELETE FROM tasks WHERE id = ?', [id]);
  }

  static Future<void> clearAll() async {
    await MemoryDatabase.executeRaw('DELETE FROM tasks');
  }

  // ── Read Operations ───────────────────────────────────────────────────────

  static Future<Task?> getTaskById(String id) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM tasks WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return _rowToTask(rows.first);
  }

  static Future<List<Task>> getAllTasks({int limit = 50}) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM tasks ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return rows.map(_rowToTask).toList();
  }

  /// يرجع المهام النشطة فقط (running | waitingForUser | pausedAtLimit)
  static Future<List<Task>> getActiveTasks() async {
    final rows = await MemoryDatabase.queryRaw(
      '''SELECT * FROM tasks
         WHERE status IN ('running','waitingForUser','pausedAtLimit')
         ORDER BY created_at DESC''',
    );
    return rows.map(_rowToTask).toList();
  }

  /// يرجع المهام بحسب حالة محددة
  static Future<List<Task>> getTasksByStatus(TaskStatus status) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM tasks WHERE status = ? ORDER BY created_at DESC',
      [status.name],
    );
    return rows.map(_rowToTask).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Task _rowToTask(Map<String, dynamic> row) {
    final map = <String, dynamic>{
      'id': row['id'],
      'goal': row['goal'],
      'status': row['status'],
      'stepsLog': row['steps_log'] ?? '[]',
      'stepCount': row['step_count'],
      'stepCap': row['step_cap'],
      'createdAt': row['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((row['created_at'] as int)).toIso8601String()
          : DateTime.now().toIso8601String(),
      'completedAt': row['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((row['completed_at'] as int)).toIso8601String()
          : null,
      'pendingQuestion': row['pending_question'],
      'completionSummary': row['completion_summary'],
      'errorMessage': row['error_message'],
      'providerId': row['provider_id'] ?? 'gemini',
      'modelName': row['model_name'] ?? '',
    };
    return Task.fromJson(map);
  }
}
