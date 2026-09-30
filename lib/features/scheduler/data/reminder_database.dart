import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/scheduler/domain/entities/reminder_item.dart';

/// إدارة مثابرة التذكيرات في SQLite — يستخدم نفس [MemoryDatabase] المشترك
/// لضمان أن جدول `reminders` في نفس الملف مع كل الجداول الأخرى وتحت الـ Mutex.
///
/// كل الدوال async لأن [MemoryDatabase.executeRaw/queryRaw] async.
class ReminderDatabase {
  static bool _initialized = false;

  /// يُنشئ جدول reminders ضمن قاعدة البيانات المشتركة.
  /// يُستدعى مرة واحدة عند بدء التطبيق بعد [MemoryDatabase.initialize()].
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS reminders (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT,
          scheduled_time INTEGER NOT NULL,
          recurrence TEXT NOT NULL DEFAULT 'once',
          is_completed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          completed_at INTEGER
        );
      ''');
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_reminders_time ON reminders(scheduled_time);',
      );
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_reminders_completed ON reminders(is_completed);',
      );
      _initialized = true;
      debugPrint('[ReminderDatabase] Initialized successfully (shared DB).');
    } catch (e) {
      debugPrint('[ReminderDatabase] Initialization error: $e');
    }
  }

  // ── Write Operations ───────────────────────────────────────────────────────

  static Future<void> insertReminder(ReminderItem item) async {
    final map = item.toMap();
    await MemoryDatabase.executeRaw('''
      INSERT OR REPLACE INTO reminders (
        id, title, description, scheduled_time, recurrence,
        is_completed, created_at, completed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      map['id'],
      map['title'],
      map['description'],
      map['scheduled_time'],
      map['recurrence'],
      map['is_completed'],
      map['created_at'],
      map['completed_at'],
    ]);
  }

  static Future<void> updateReminder(ReminderItem item) => insertReminder(item);

  static Future<ReminderItem?> getReminderById(String id) async {
    final rows = await MemoryDatabase.queryRaw('''
      SELECT * FROM reminders WHERE id = ? LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return _rowToItem(rows.first);
  }

  static Future<void> markCompleted(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await MemoryDatabase.executeRaw('''
      UPDATE reminders
      SET is_completed = 1, completed_at = ?
      WHERE id = ?
    ''', [now, id]);
  }

  static Future<void> reschedule(String id, DateTime nextTime) async {
    await MemoryDatabase.executeRaw('''
      UPDATE reminders
      SET scheduled_time = ?, is_completed = 0
      WHERE id = ?
    ''', [nextTime.millisecondsSinceEpoch, id]);
  }

  static Future<void> deleteReminder(String id) async {
    await MemoryDatabase.executeRaw(
      'DELETE FROM reminders WHERE id = ?',
      [id],
    );
  }

  static Future<void> clearAll() async {
    await MemoryDatabase.executeRaw('DELETE FROM reminders');
  }

  // ── Read Operations ────────────────────────────────────────────────────────

  static Future<List<ReminderItem>> getDueReminders(DateTime now) async {
    final rows = await MemoryDatabase.queryRaw('''
      SELECT * FROM reminders
      WHERE is_completed = 0 AND scheduled_time <= ?
      ORDER BY scheduled_time ASC
    ''', [now.millisecondsSinceEpoch]);
    return rows.map(_rowToItem).toList();
  }

  /// يرجع التذكيرات الفائتة (قبل [now]) غير المكتملة.
  static Future<List<ReminderItem>> getMissedReminders(DateTime now) async {
    final rows = await MemoryDatabase.queryRaw('''
      SELECT * FROM reminders
      WHERE is_completed = 0 AND scheduled_time < ?
      ORDER BY scheduled_time ASC
    ''', [now.millisecondsSinceEpoch]);
    return rows.map(_rowToItem).toList();
  }

  static Future<List<ReminderItem>> getAllReminders({int limit = 100}) async {
    final rows = await MemoryDatabase.queryRaw('''
      SELECT * FROM reminders
      ORDER BY is_completed ASC, scheduled_time ASC
      LIMIT ?
    ''', [limit]);
    return rows.map(_rowToItem).toList();
  }

  static Future<List<ReminderItem>> getActiveReminders() async {
    final rows = await MemoryDatabase.queryRaw('''
      SELECT * FROM reminders
      WHERE is_completed = 0
      ORDER BY scheduled_time ASC
    ''');
    return rows.map(_rowToItem).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static ReminderItem _rowToItem(Map<String, dynamic> row) {
    return ReminderItem.fromMap(row);
  }
}
