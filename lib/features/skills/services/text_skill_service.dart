import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/features/skills/domain/entities/text_skill.dart';

/// خدمة إدارة واكتشاف المهارات النصية الإرشادية (Text Skills).
/// مهارات توجيهية خفيفة بدون Sidecar أو كود تنفيذي، تُحمَّل على مرحلتين (فهرس خفيف + تحميل عند الحاجة).
class TextSkillService {
  static final TextSkillService instance = TextSkillService._();
  TextSkillService._();

  String? _customDir;

  /// تعيين مجلد مخصص للمهارات النصية (للاختبارات)
  void setCustomDirectory(String? dir) {
    _customDir = dir;
  }

  /// المسار القياسي لمجلد المهارات النصية (%APPDATA%\Khwarizmi\TextSkills\)
  Future<String> getTextSkillsDirectoryPath() async {
    if (_customDir != null) {
      return _customDir!;
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'Khwarizmi', 'TextSkills');
      }
    }

    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'TextSkills');
  }

  /// مسح المجلد واكتشاف ملفات SKILL.md ومزامنتها مع قاعدة البيانات
  Future<List<TextSkill>> scanAndDiscoverTextSkills() async {
    final rootPath = await getTextSkillsDirectoryPath();
    final rootDir = Directory(rootPath);

    if (!await rootDir.exists()) {
      try {
        await rootDir.create(recursive: true);
        debugPrint('[TextSkillService] Created TextSkills directory at: $rootPath');
      } catch (e) {
        debugPrint('[TextSkillService] Could not create directory: $e');
        return await _loadAllFromDb();
      }
    }

    final discoveredSkills = <TextSkill>[];

    try {
      final entities = rootDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is Directory) {
          final skillFile = File(p.join(entity.path, 'SKILL.md'));
          if (!await skillFile.exists()) continue;

          try {
            final content = await skillFile.readAsString();
            // فحص الحالة المخزنة في قاعدة البيانات
            final existingRow = await SkillDatabase.getTextSkillRow(p.basename(entity.path));
            final isEnabled = existingRow != null ? (existingRow['is_enabled'] as int? ?? 1) == 1 : true;

            final skill = TextSkill.fromFileContent(
              content,
              folderPath: entity.path,
              filePath: skillFile.path,
              isEnabled: isEnabled,
            );

            discoveredSkills.add(skill);

            // حفظ / تحديث في قاعدة البيانات
            await SkillDatabase.saveTextSkillRow(
              name: skill.name,
              description: skill.description,
              folderPath: skill.folderPath,
              filePath: skill.filePath,
              isEnabled: skill.isEnabled,
            );

            debugPrint('[TextSkillService] Discovered text skill "${skill.name}" from ${skill.filePath}');
          } catch (e) {
            // تجاهل آمن لأي ملف ناقص أو تالف مع تسجيل تحذير واضح
            debugPrint('[TextSkillService] WARNING: Skipping invalid SKILL.md in "${entity.path}": $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[TextSkillService] Error scanning TextSkills: $e');
    }

    return discoveredSkills;
  }

  /// جلب جميع المهارات النصية من قاعدة البيانات
  Future<List<TextSkill>> getAllSkills() async {
    return await _loadAllFromDb();
  }

  /// المرحلة 1: إنتاج الفهرس الخفيف (سطر واحد لكل مهارة) للحقن في الـ System Prompt
  /// يمنع تضخم السياق واستهلاك التوكنات، ويعطي النموذج دليلاً بوجود المهارات
  Future<String> getLightweightIndexPrompt() async {
    final all = await _loadAllFromDb();
    final active = all.where((s) => s.isEnabled).toList();

    if (active.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('[المهارات النصية الإرشادية المتاحة]:');
    buffer.writeln('إذا كان طلب المستخدم متعلقاً بأحد هذه المجالات، استدعِ أداة load_text_skill(name) لقراءة دليل التعليمات الكامل وتطبيقه بدقة:');
    for (final skill in active) {
      buffer.writeln('- ${skill.name}: ${skill.description}');
    }

    return buffer.toString().trim();
  }

  /// المرحلة 2: تحميل المحتوى الكامل لمهارة معينة عند استدعاء أداة load_text_skill
  Future<String> loadSkillContent(String name) async {
    final trimmedName = name.trim();
    final row = await SkillDatabase.getTextSkillRow(trimmedName);

    if (row == null) {
      return '{"error": "المهارة النصية \'$trimmedName\' غير موجودة. تأكد من الاسم من قائمة المهارات المتاحة."}';
    }

    final isEnabled = (row['is_enabled'] as int? ?? 1) == 1;
    if (!isEnabled) {
      return '{"error": "المهارة النصية \'$trimmedName\' معطّلة حالياً من قبل المستخدم."}';
    }

    final filePath = row['file_path'] as String? ?? '';
    final file = File(filePath);
    if (!await file.exists()) {
      return '{"error": "ملف المهارة النصية غير موجود على القرص: $filePath"}';
    }

    try {
      final rawContent = await file.readAsString();
      final skill = TextSkill.fromFileContent(
        rawContent,
        folderPath: row['folder_path'] as String? ?? '',
        filePath: filePath,
        isEnabled: isEnabled,
      );

      return '''
[دليل إرشادات المهارة النصية: ${skill.name}]
الوصف: ${skill.description}

---
${skill.content}
---
طبق هذه الإرشادات والتوجيهات أعلاه بدقة على طلب المستخدم الحالي.
'''.trim();
    } catch (e) {
      return '{"error": "تعذر قراءة محتوى المهارة النصية: $e"}';
    }
  }

  /// تفعيل أو تعطيل مهارة نصية
  Future<void> toggleSkill(String name, bool enabled) async {
    await SkillDatabase.setTextSkillEnabled(name, enabled);
    debugPrint('[TextSkillService] Toggled text skill "$name" to $enabled');
  }

  /// حذف مهارة نصية من قاعدة البيانات ومن القرص
  Future<bool> deleteSkill(String name) async {
    final row = await SkillDatabase.getTextSkillRow(name);
    await SkillDatabase.deleteTextSkillRow(name);

    if (row != null) {
      final folderPath = row['folder_path'] as String? ?? '';
      if (folderPath.isNotEmpty) {
        try {
          final dir = Directory(folderPath);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
            debugPrint('[TextSkillService] Deleted text skill folder: $folderPath');
          }
        } catch (e) {
          debugPrint('[TextSkillService] Error deleting folder: $e');
        }
      }
    }
    return true;
  }

  /// فتح مجلد المهارات النصية في Windows Explorer
  Future<void> openTextSkillsFolder() async {
    final path = await getTextSkillsDirectoryPath();
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', [path]);
      } catch (e) {
        debugPrint('[TextSkillService] Could not open folder: $e');
      }
    }
  }

  Future<List<TextSkill>> _loadAllFromDb() async {
    final rows = await SkillDatabase.getAllTextSkillRows();
    final list = <TextSkill>[];

    for (final row in rows) {
      final filePath = row['file_path'] as String? ?? '';
      String content = '';
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          final raw = file.readAsStringSync();
          final parsed = TextSkill.fromFileContent(
            raw,
            folderPath: row['folder_path'] as String? ?? '',
            filePath: filePath,
          );
          content = parsed.content;
        }
      } catch (_) {}

      list.add(TextSkill(
        name: row['name'] as String,
        description: row['description'] as String,
        content: content,
        folderPath: row['folder_path'] as String? ?? '',
        filePath: filePath,
        isEnabled: (row['is_enabled'] as int? ?? 1) == 1,
      ));
    }

    return list;
  }
}
