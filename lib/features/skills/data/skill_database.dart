import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_record.dart';

/// إدارة استمرارية الـ Skills في SQLite.
class SkillDatabase {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS skills (
          name TEXT PRIMARY KEY,
          display_name TEXT NOT NULL,
          description TEXT NOT NULL,
          endpoint TEXT NOT NULL,
          input_schema TEXT NOT NULL,
          permissions TEXT NOT NULL,
          version TEXT NOT NULL,
          folder_path TEXT NOT NULL,
          start_command TEXT,
          is_approved INTEGER NOT NULL DEFAULT 0,
          is_enabled INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');

      await MemoryDatabase.executeRaw('''
        CREATE TABLE IF NOT EXISTS text_skills (
          name TEXT PRIMARY KEY,
          description TEXT NOT NULL,
          folder_path TEXT NOT NULL,
          file_path TEXT NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');

      _initialized = true;
      debugPrint('[SkillDatabase] Initialized successfully.');
    } catch (e) {
      debugPrint('[SkillDatabase] Initialization error: $e');
    }
  }

  static Future<List<SkillRecord>> getAllSkills() async {
    try {
      final rows = await MemoryDatabase.queryRaw(
        'SELECT * FROM skills ORDER BY name ASC',
      );
      return rows.map(_rowToRecord).toList();
    } catch (e) {
      debugPrint('[SkillDatabase] Error fetching skills: $e');
      return [];
    }
  }

  static Future<SkillRecord?> getSkill(String name) async {
    try {
      final rows = await MemoryDatabase.queryRaw(
        'SELECT * FROM skills WHERE name = ? LIMIT 1',
        [name],
      );
      if (rows.isEmpty) return null;
      return _rowToRecord(rows.first);
    } catch (e) {
      debugPrint('[SkillDatabase] Error fetching skill "$name": $e');
      return null;
    }
  }

  static Future<void> saveSkill(SkillRecord record) async {
    final m = record.manifest;
    await MemoryDatabase.executeRaw('''
      INSERT OR REPLACE INTO skills (
        name, display_name, description, endpoint, input_schema,
        permissions, version, folder_path, start_command,
        is_approved, is_enabled, last_error, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      m.name,
      m.displayName,
      m.description,
      m.endpoint,
      jsonEncode(m.inputSchema),
      jsonEncode(m.permissions),
      m.version,
      m.folderPath,
      m.startCommand,
      record.isApproved ? 1 : 0,
      record.isEnabled ? 1 : 0,
      record.lastError,
      record.createdAt.millisecondsSinceEpoch,
      record.updatedAt.millisecondsSinceEpoch,
    ]);
  }

  static Future<void> setApproved(String name, bool isApproved) async {
    await MemoryDatabase.executeRaw('''
      UPDATE skills
      SET is_approved = ?, updated_at = ?
      WHERE name = ?
    ''', [
      isApproved ? 1 : 0,
      DateTime.now().millisecondsSinceEpoch,
      name,
    ]);
  }

  static Future<void> setEnabled(String name, bool isEnabled, {String? lastError}) async {
    await MemoryDatabase.executeRaw('''
      UPDATE skills
      SET is_enabled = ?, last_error = ?, updated_at = ?
      WHERE name = ?
    ''', [
      isEnabled ? 1 : 0,
      lastError,
      DateTime.now().millisecondsSinceEpoch,
      name,
    ]);
  }

  static Future<void> deleteSkill(String name) async {
    await MemoryDatabase.executeRaw(
      'DELETE FROM skills WHERE name = ?',
      [name],
    );
  }

  static SkillRecord _rowToRecord(Map<String, dynamic> row) {
    List<String> permissions = [];
    try {
      final decodedPerms = jsonDecode(row['permissions'] as String? ?? '[]');
      if (decodedPerms is List) {
        permissions = decodedPerms.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    Map<String, dynamic> inputSchema = {};
    try {
      final decodedSchema = jsonDecode(row['input_schema'] as String? ?? '{}');
      if (decodedSchema is Map) {
        inputSchema = Map<String, dynamic>.from(decodedSchema);
      }
    } catch (_) {}

    final manifest = SkillManifest(
      name: row['name'] as String,
      displayName: row['display_name'] as String,
      description: row['description'] as String,
      endpoint: row['endpoint'] as String,
      inputSchema: inputSchema,
      permissions: permissions,
      version: row['version'] as String? ?? '1.0.0',
      folderPath: row['folder_path'] as String? ?? '',
      startCommand: row['start_command'] as String?,
    );

    return SkillRecord(
      manifest: manifest,
      isApproved: (row['is_approved'] as int? ?? 0) == 1,
      isEnabled: (row['is_enabled'] as int? ?? 0) == 1,
      lastError: row['last_error'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int? ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int? ?? 0),
    );
  }

  // ── Text Skills (المهارات النصية) Operations ───────────────────────────────

  static Future<List<Map<String, dynamic>>> getAllTextSkillRows() async {
    try {
      return await MemoryDatabase.queryRaw(
        'SELECT * FROM text_skills ORDER BY name ASC',
      );
    } catch (e) {
      debugPrint('[SkillDatabase] Error fetching text_skills: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getTextSkillRow(String name) async {
    try {
      final rows = await MemoryDatabase.queryRaw(
        'SELECT * FROM text_skills WHERE name = ? LIMIT 1',
        [name],
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      debugPrint('[SkillDatabase] Error fetching text_skill "$name": $e');
      return null;
    }
  }

  static Future<void> saveTextSkillRow({
    required String name,
    required String description,
    required String folderPath,
    required String filePath,
    required bool isEnabled,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await MemoryDatabase.executeRaw('''
      INSERT OR REPLACE INTO text_skills (
        name, description, folder_path, file_path, is_enabled, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', [
      name,
      description,
      folderPath,
      filePath,
      isEnabled ? 1 : 0,
      now,
      now,
    ]);
  }

  static Future<void> setTextSkillEnabled(String name, bool isEnabled) async {
    await MemoryDatabase.executeRaw('''
      UPDATE text_skills
      SET is_enabled = ?, updated_at = ?
      WHERE name = ?
    ''', [
      isEnabled ? 1 : 0,
      DateTime.now().millisecondsSinceEpoch,
      name,
    ]);
  }

  static Future<void> deleteTextSkillRow(String name) async {
    await MemoryDatabase.executeRaw(
      'DELETE FROM text_skills WHERE name = ?',
      [name],
    );
  }
}
