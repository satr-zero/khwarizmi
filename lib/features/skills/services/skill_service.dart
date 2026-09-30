import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_record.dart';
import 'package:khwarizmi/features/skills/domain/skill_tool.dart';
import 'package:khwarizmi/features/skills/services/sidecar_process_manager.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

/// الخدمة المركزية لاكتشاف وإدارة دورة حياة الـ Skills وتكاملها مع نظام الأدوات.
class SkillService {
  static final SkillService instance = SkillService._();
  SkillService._() {
    // ربط مستمع التعطيل التلقائي عند تكرار انهيار الـ Sidecar
    SidecarProcessManager.instance.onSkillAutoDisabled = (skillName, error) async {
      debugPrint('[SkillService] Auto-disabling skill "$skillName": $error');
      ToolRegistry.unregisterTool(skillName);
      await SkillDatabase.setEnabled(skillName, false, lastError: error);
    };
  }

  String? _customSkillsDir;

  /// تعيين مجلد مخصص للـ Skills (مفيد جداً للاختبارات)
  void setCustomSkillsDirectory(String? dir) {
    _customSkillsDir = dir;
  }

  /// المسار القياسي لمجلد الـ Skills (%APPDATA%\Khwarizmi\Skills\)
  Future<String> getSkillsDirectoryPath() async {
    if (_customSkillsDir != null) {
      return _customSkillsDir!;
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'Khwarizmi', 'Skills');
      }
    }

    // بديل أنظمة التشغيل الأخرى أو في حال تعذر قراءة APPDATA
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'Skills');
  }

  /// مسح مجلد الـ Skills واكتشاف كل المجلدات الفرعية ومطابقة Manifests
  Future<List<SkillRecord>> scanAndDiscoverSkills() async {
    final rootPath = await getSkillsDirectoryPath();
    final rootDir = Directory(rootPath);

    if (!await rootDir.exists()) {
      try {
        await rootDir.create(recursive: true);
        debugPrint('[SkillService] Created skills directory at: $rootPath');
      } catch (e) {
        debugPrint('[SkillService] Could not create skills directory at $rootPath: $e');
        return await SkillDatabase.getAllSkills();
      }
    }

    final discoveredManifests = <SkillManifest>[];

    try {
      final entities = rootDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is Directory) {
          final manifestFile = File(p.join(entity.path, 'manifest.json'));
          if (!await manifestFile.exists()) {
            debugPrint('[SkillService] Skipping folder without manifest.json: ${entity.path}');
            continue;
          }

          try {
            final content = await manifestFile.readAsString();
            final manifest = SkillManifest.fromRawJson(
              content,
              folderPath: entity.path,
            );
            discoveredManifests.add(manifest);
            debugPrint('[SkillService] Successfully parsed manifest for "${manifest.name}" from ${entity.path}');
          } catch (e) {
            // تجاهل آمن لأي ملف تالف أو ناقص مع تحذير واضح
            debugPrint('[SkillService] WARNING: Invalid manifest.json in "${entity.path}": $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[SkillService] Error listing skills directory: $e');
    }

    // مزامنة المكتشف مع قاعدة البيانات
    final now = DateTime.now();
    for (final manifest in discoveredManifests) {
      final existing = await SkillDatabase.getSkill(manifest.name);
      if (existing == null) {
        // اكتشاف لأول مرة: غير معتمد وغير مفعّل تلقائياً قطعيّاً (المتطلب 3.2)
        final newRecord = SkillRecord(
          manifest: manifest,
          isApproved: false,
          isEnabled: false,
          createdAt: now,
          updatedAt: now,
        );
        await SkillDatabase.saveSkill(newRecord);
        debugPrint('[SkillService] New skill discovered pending approval: "${manifest.name}"');
      } else {
        // تحديث الـ manifest في قاعدة البيانات مع الحفاظ على حالة الموافقة والتفعيل
        final updatedRecord = existing.copyWith(
          manifest: manifest,
          updatedAt: now,
        );
        await SkillDatabase.saveSkill(updatedRecord);

        // إن كان مفعّلاً ومعتمداً مسبقاً، نفعله في النظام
        if (updatedRecord.isApproved && updatedRecord.isEnabled) {
          await _activateSkillInRuntime(manifest);
        }
      }
    }

    return await SkillDatabase.getAllSkills();
  }

  /// تفعيل وتشغيل الـ Skill بعد موافقة المستخدم الصريحة
  Future<bool> approveAndEnableSkill(String name) async {
    final record = await SkillDatabase.getSkill(name);
    if (record == null) {
      debugPrint('[SkillService] Cannot approve: Skill "$name" not found.');
      return false;
    }

    final success = await _activateSkillInRuntime(record.manifest);
    if (success) {
      await SkillDatabase.setApproved(name, true);
      await SkillDatabase.setEnabled(name, true, lastError: null);
      debugPrint('[SkillService] Skill "$name" approved and enabled successfully.');
      return true;
    } else {
      await SkillDatabase.setEnabled(name, false, lastError: 'فشل تفعيل الأداة (تصادم أسماء أو تعذر بدء العملية).');
      return false;
    }
  }

  /// تعطيل الـ Skill وإيقاف عمليته فوراً
  Future<void> disableSkill(String name) async {
    ToolRegistry.unregisterTool(name);
    await SidecarProcessManager.instance.stopProcess(name);
    await SkillDatabase.setEnabled(name, false);
    debugPrint('[SkillService] Skill "$name" disabled.');
  }

  /// حذف الـ Skill بالكامل من قاعدة البيانات ومن القرص
  Future<bool> deleteSkill(String name) async {
    final record = await SkillDatabase.getSkill(name);
    await disableSkill(name);
    await SkillDatabase.deleteSkill(name);

    if (record != null && record.manifest.folderPath.isNotEmpty) {
      try {
        final dir = Directory(record.manifest.folderPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          debugPrint('[SkillService] Deleted folder: ${record.manifest.folderPath}');
        }
      } catch (e) {
        debugPrint('[SkillService] Could not delete folder for "$name": $e');
      }
    }
    return true;
  }

  /// جلب المهارات المكتشفة التي تنتظر موافقة المستخدم
  Future<List<SkillRecord>> getPendingApprovalSkills() async {
    final all = await SkillDatabase.getAllSkills();
    return all.where((s) => !s.isApproved).toList();
  }

  /// فتح مجلد الـ Skills في مستكشف ملفات Windows
  Future<void> openSkillsFolder() async {
    final path = await getSkillsDirectoryPath();
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', [path]);
      } catch (e) {
        debugPrint('[SkillService] Could not open folder in explorer: $e');
      }
    }
  }

  /// تفعيل الأداة برمجياً: تسجيلها في ToolRegistry وتشغيل الـ Sidecar إذا لزم
  Future<bool> _activateSkillInRuntime(SkillManifest manifest) async {
    // 1. فحص تصادم الأسماء مع الأدوات المدمجة
    if (ToolRegistry.isBuiltInTool(manifest.name)) {
      debugPrint('[SkillService] ERROR: Cannot register skill "${manifest.name}". Name collides with a core built-in tool.');
      return false;
    }

    // 2. إذا كانت الأداة مسجلة مسبقاً، نلغي تسجيلها لتحديثها بنظافة
    if (ToolRegistry.isToolRegistered(manifest.name)) {
      ToolRegistry.unregisterTool(manifest.name);
    }

    // 3. تسجيل الأداة في ToolRegistry
    final tool = SkillTool(manifest);
    final registered = ToolRegistry.registerTool(tool);
    if (!registered) {
      debugPrint('[SkillService] Failed to register tool "${manifest.name}" in ToolRegistry.');
      return false;
    }

    // 4. تشغيل عملية الـ Sidecar إذا وُجد start_command
    if (manifest.startCommand != null && manifest.startCommand!.isNotEmpty) {
      final started = await SidecarProcessManager.instance.startProcess(manifest);
      if (!started) {
        debugPrint('[SkillService] Warning: Failed to launch sidecar process for "${manifest.name}".');
      }
    }

    return true;
  }
}
