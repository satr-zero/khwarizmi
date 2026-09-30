import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';

/// إدارة مثابرة خطط المهام (Task Plans) في قاعدة بيانات SQLite.
///
/// كل خطة مرتبطة بـ [thread_id] = taskId فريد.
/// تُحفظ تلقائياً بعد كل مهمة فرعية مكتملة لضمان الاستئناف الآمن.
class TaskPlanDatabase {
  static bool _tableCreated = false;

  // ── Initialization ────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_tableCreated) return;
    try {
      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS task_plans (
          task_id TEXT PRIMARY KEY,
          goal TEXT NOT NULL,
          task_list TEXT NOT NULL DEFAULT '[]',
          plan_summary TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_plans_task_id ON task_plans(task_id);',
      );
      _tableCreated = true;
      debugPrint('[TaskPlanDatabase] task_plans table ready.');
    } catch (e) {
      debugPrint('[TaskPlanDatabase] Initialization error: $e');
    }
  }

  // ── Write Operations ──────────────────────────────────────────────────────

  /// حفظ أو تحديث خطة (upsert) — يُستدعى فور إنشاء الخطة وبعد كل مهمة فرعية
  static Future<void> upsertPlan(TaskPlan plan) async {
    final j = plan.toJson();
    final now = DateTime.now().millisecondsSinceEpoch;
    await MemoryDatabase.executeRaw(
      '''
      INSERT OR REPLACE INTO task_plans (
        task_id, goal, task_list, plan_summary, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        j['taskId'],
        j['goal'],
        j['taskList'],
        j['planSummary'],
        plan.createdAt.millisecondsSinceEpoch,
        now,
      ],
    );
  }

  /// تحديث قائمة المهام الفرعية فقط (Checkpoint بعد كل مهمة فرعية)
  static Future<void> updateTaskList(String taskId, TaskPlan plan) async {
    final j = plan.toJson();
    final now = DateTime.now().millisecondsSinceEpoch;
    await MemoryDatabase.executeRaw(
      'UPDATE task_plans SET task_list = ?, updated_at = ? WHERE task_id = ?',
      [j['taskList'], now, taskId],
    );
  }

  static Future<void> deletePlan(String taskId) async {
    await MemoryDatabase.executeRaw(
      'DELETE FROM task_plans WHERE task_id = ?',
      [taskId],
    );
  }

  // ── Read Operations ───────────────────────────────────────────────────────

  /// جلب الخطة بمعرف المهمة (thread_id) — للاستئناف بعد الانقطاع
  static Future<TaskPlan?> getPlanByTaskId(String taskId) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM task_plans WHERE task_id = ? LIMIT 1',
      [taskId],
    );
    if (rows.isEmpty) return null;
    return _rowToPlan(rows.first);
  }

  static Future<List<TaskPlan>> getAllPlans({int limit = 50}) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM task_plans ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return rows.map(_rowToPlan).toList();
  }

  // ── Helper ────────────────────────────────────────────────────────────────

  static TaskPlan _rowToPlan(Map<String, dynamic> row) {
    return TaskPlan.fromJson({
      'taskId': row['task_id'],
      'goal': row['goal'],
      'taskList': row['task_list'] ?? '[]',
      'planSummary': row['plan_summary'],
      'createdAt': row['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (row['created_at'] as int),
            ).toIso8601String()
          : DateTime.now().toIso8601String(),
    });
  }
}
