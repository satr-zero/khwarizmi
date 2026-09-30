import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  group('Phase 8: Real TextSkills Live APPDATA Discovery & Loading Test', () {
    setUpAll(() async {
      await MemoryDatabase.initialize(customPath: ':memory:');
      await SkillDatabase.initialize();
      ToolRegistry.clear();
      ToolRegistry.initialize();

      // Ensure formal_email_writer fixture is present in the real TextSkills directory
      final textSkillsDir = await TextSkillService.instance.getTextSkillsDirectoryPath();
      final skillDir = Directory(p.join(textSkillsDir, 'formal_email_writer'));
      if (!await skillDir.exists()) {
        await skillDir.create(recursive: true);
      }
      final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
      if (!await skillFile.exists()) {
        await skillFile.writeAsString('''---
name: formal_email_writer
description: إرشادات كتابة رسائل البريد الإلكتروني الرسمية والمهنية باللغة العربية
---

# إرشادات كتابة البريد الرسمي
1. ابدأ دائماً بالتحية: "السلام عليكم ورحمة الله وبركاته، وبعد:"
2. السطر الافتتاحي: اذكر الغرض من الرسالة باختصار ووضوح.
3. الخاتمة: "شاكرين ومقدّرين حسن تعاونكم، وتفضلوا بقبول فائق الاحترام والتقدير".
''', flush: true);
      }
    });

    test('Discovers real formal_email_writer skill from APPDATA, generates lightweight index, and executes load_text_skill', () async {
      final service = TextSkillService.instance;

      // 1. اكتشاف المهارات النصية من مسار APPDATA الفعلي
      final discovered = await service.scanAndDiscoverTextSkills();
      expect(discovered.any((s) => s.name == 'formal_email_writer'), isTrue);

      final skill = discovered.firstWhere((s) => s.name == 'formal_email_writer');
      expect(skill.isEnabled, isTrue, reason: 'Text skills are auto-enabled by default without approval modal');

      // 2. التحقق من الفهرس الخفيف (سطر واحد فقط، بدون المتن الكامل)
      final lightweightIndex = await service.getLightweightIndexPrompt();
      expect(lightweightIndex, contains('- formal_email_writer: إرشادات كتابة رسائل البريد الإلكتروني الرسمية والمهنية باللغة العربية'));
      expect(lightweightIndex, isNot(contains('السطر الافتتاحي: اذكر الغرض')));

      // 3. محاكاة استدعاء النموذج للأداة load_text_skill عند طلب كتابة بريد رسمي
      final result = await ToolRegistry.executeTool('load_text_skill', {'name': 'formal_email_writer'});

      // ignore: avoid_print
      print('=== LOAD_TEXT_SKILL REAL RESULT ===\n$result\n===================================');

      expect(result, contains('[دليل إرشادات المهارة النصية: formal_email_writer]'));
      expect(result, contains('السلام عليكم ورحمة الله وبركاته'));
      expect(result, contains('شاكرين ومقدّرين حسن تعاونكم'));

      // 4. التحقق من وجود load_text_skill ضمن أدوات الشات وأدوات المهام المستقلة
      final chatTools = ToolRegistry.getChatDefinitions();
      expect(chatTools.any((t) => t.name == 'load_text_skill'), isTrue);

      final autoTools = ToolRegistry.getAutonomousDefinitions();
      expect(autoTools.any((t) => t.name == 'load_text_skill'), isTrue);
    });
  });
}
