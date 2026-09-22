import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/projects/domain/entities/project.dart';
import 'package:uuid/uuid.dart';

/// إدارة مثابرة المشاريع وربطها بالمحادثات في SQLite — المرحلة 9.
///
/// يستخدم نفس [MemoryDatabase] المشترك لتجنب تعدد ملفات قاعدة البيانات.
class ProjectDatabase {
  static const _uuid = Uuid();
  static bool _initialized = false;

  /// يُنشئ الجداول المطلوبة عند بدء التطبيق.
  /// ملاحظة: الجداول تُنشأ أيضًا عبر نظام الترحيل في [MemoryDatabase._migrateV2]،
  /// لذا هذا الاستدعاء آمن (CREATE TABLE IF NOT EXISTS) ولا يُعيد إنشاء ما هو موجود.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      // جدول المشاريع الأخيرة
      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS projects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          root_path TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL,
          last_opened_at INTEGER NOT NULL,
          project_map TEXT
        );
      ''');

      try {
        await MemoryDatabase.executeRaw('ALTER TABLE projects ADD COLUMN project_map TEXT;');
      } catch (_) {
        // العمود موجود مسبقًا
      }

      // جدول ربط المحادثات بالمشاريع (علاقة 1:1 — محادثة ← مشروع)
      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS conversation_projects (
          conversation_id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL,
          linked_at INTEGER NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
        );
      ''');

      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_projects_last_opened ON projects(last_opened_at DESC);',
      );
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_projects_path ON projects(root_path);',
      );
      await MemoryDatabase.executeRaw(
        'CREATE INDEX IF NOT EXISTS idx_conv_proj_project ON conversation_projects(project_id);',
      );

      _initialized = true;
      debugPrint('[ProjectDatabase] Initialized successfully.');
    } catch (e) {
      debugPrint('[ProjectDatabase] Initialization error: $e');
    }
  }


  // ── Project CRUD ──────────────────────────────────────────────────────────

  /// يُنشئ مشروعًا جديدًا أو يُحدّث تاريخ آخر فتح إن كان المسار موجودًا.
  static Future<Project> upsertProject({
    required String rootPath,
    required String name,
  }) async {
    // فحص ما إذا كان المسار موجودًا مسبقًا
    final existing = await getProjectByPath(rootPath);
    if (existing != null) {
      final updated = existing.copyWith(lastOpenedAt: DateTime.now());
      await MemoryDatabase.executeRaw(
        'UPDATE projects SET last_opened_at = ?, name = ? WHERE id = ?',
        [updated.lastOpenedAt.millisecondsSinceEpoch, name, updated.id],
      );
      return updated;
    }

    final project = Project(
      id: _uuid.v4(),
      name: name,
      rootPath: rootPath,
      createdAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );
    await MemoryDatabase.executeRaw(
      'INSERT INTO projects (id, name, root_path, created_at, last_opened_at) VALUES (?, ?, ?, ?, ?)',
      [project.id, project.name, project.rootPath, project.createdAt.millisecondsSinceEpoch, project.lastOpenedAt.millisecondsSinceEpoch],
    );
    return project;
  }

  static Future<Project?> getProjectByPath(String rootPath) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM projects WHERE root_path = ? LIMIT 1',
      [rootPath],
    );
    if (rows.isEmpty) return null;
    return Project.fromMap(rows.first);
  }

  static Future<Project?> getProjectById(String id) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM projects WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return Project.fromMap(rows.first);
  }

  /// يرجع المشاريع الأخيرة مرتبةً بتاريخ آخر فتح (الأحدث أولاً).
  static Future<List<Project>> getRecentProjects({int limit = 10}) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT * FROM projects ORDER BY last_opened_at DESC LIMIT ?',
      [limit],
    );
    return rows.map(Project.fromMap).toList();
  }

  static Future<void> deleteProject(String id) async {
    await MemoryDatabase.executeRaw('DELETE FROM projects WHERE id = ?', [id]);
  }

  /// يحفظ خريطة المشروع المحدثة في جدول المشاريع.
  static Future<void> saveProjectMap(String projectId, String mapContent) async {
    await MemoryDatabase.executeRaw(
      'UPDATE projects SET project_map = ? WHERE id = ?',
      [mapContent, projectId],
    );
  }

  /// يسترجع خريطة المشروع المخزنة إن وُجدت.
  static Future<String?> getProjectMap(String projectId) async {
    final rows = await MemoryDatabase.queryRaw(
      'SELECT project_map FROM projects WHERE id = ? LIMIT 1',
      [projectId],
    );
    if (rows.isEmpty) return null;
    return rows.first['project_map'] as String?;
  }

  // ── Conversation ↔ Project Linking ─────────────────────────────────────────

  /// يربط محادثة بمشروع (يُستدعى عند فتح مشروع ضمن محادثة نشطة).
  static Future<void> linkConversationToProject(
    String conversationId,
    String projectId,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await MemoryDatabase.executeRaw(
      'INSERT OR REPLACE INTO conversation_projects (conversation_id, project_id, linked_at) VALUES (?, ?, ?)',
      [conversationId, projectId, now],
    );
  }

  /// يسترد المشروع المرتبط بمحادثة محددة (لاستعادته عند فتح المحادثة).
  static Future<Project?> getProjectForConversation(String conversationId) async {
    final rows = await MemoryDatabase.queryRaw(
      '''SELECT p.* FROM projects p
         INNER JOIN conversation_projects cp ON p.id = cp.project_id
         WHERE cp.conversation_id = ? LIMIT 1''',
      [conversationId],
    );
    if (rows.isEmpty) return null;
    return Project.fromMap(rows.first);
  }

  static Future<void> unlinkConversationFromProject(String conversationId) async {
    await MemoryDatabase.executeRaw(
      'DELETE FROM conversation_projects WHERE conversation_id = ?',
      [conversationId],
    );
  }
}
