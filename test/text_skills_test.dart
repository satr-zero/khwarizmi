import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/features/skills/domain/entities/text_skill.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  group('Phase 8: Text Skills (المهارات النصية الإرشادية) Unit & Two-Stage Loading Tests', () {
    late Directory tempDir;

    setUpAll(() async {
      await MemoryDatabase.initialize(customPath: ':memory:');
      await SkillDatabase.initialize();
      ToolRegistry.clear();
      ToolRegistry.initialize();
    });

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('text_skills_test_');
      TextSkillService.instance.setCustomDirectory(tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('1. Parses valid SKILL.md with YAML frontmatter and Markdown content', () {
      const validMarkdown = '''
---
name: formal_email_writer
description: إرشادات كتابة رسائل البريد الإلكتروني الرسمية والمهنية
---

# دليل كتابة البريد الرسمي
1. ابدأ دائماً بالتحية الرسمية: "السلام عليكم ورحمة الله وبركاته، تحية طيبة وبعد:".
2. اذكر الهدف من الرسالة في أول فقرة مباشرة.
3. اختتم بـ "وتفضلوا بقبول فائق الاحترام والتقدير".
''';

      final skill = TextSkill.fromFileContent(
        validMarkdown,
        folderPath: '/skills/email',
        filePath: '/skills/email/SKILL.md',
      );

      expect(skill.name, equals('formal_email_writer'));
      expect(skill.description, equals('إرشادات كتابة رسائل البريد الإلكتروني الرسمية والمهنية'));
      expect(skill.content, contains('# دليل كتابة البريد الرسمي'));
      expect(skill.content, contains('وتفضلوا بقبول فائق الاحترام'));
      expect(skill.isEnabled, isTrue);
    });

    test('2. Safely rejects corrupted or incomplete SKILL.md without crashing', () {
      // بدون فاصل إغلاق
      expect(
        () => TextSkill.fromFileContent(
          '---\nname: broken\nmissing closing delimiter',
          folderPath: '/tmp',
          filePath: '/tmp/SKILL.md',
        ),
        throwsFormatException,
      );

      // بدون name
      expect(
        () => TextSkill.fromFileContent(
          '---\ndescription: only description\n---\nBody',
          folderPath: '/tmp',
          filePath: '/tmp/SKILL.md',
        ),
        throwsFormatException,
      );

      // بدون description
      expect(
        () => TextSkill.fromFileContent(
          '---\nname: only_name\n---\nBody',
          folderPath: '/tmp',
          filePath: '/tmp/SKILL.md',
        ),
        throwsFormatException,
      );
    });

    test('3. Two-Stage Loading: Stage 1 injects only lightweight index (names and descriptions, NOT full content)', () async {
      // إنشاء مهارتين نصيتين في المجلد المؤقت
      final emailFolder = Directory('${tempDir.path}/email_skill')..createSync();
      File('${emailFolder.path}/SKILL.md').writeAsStringSync('''
---
name: email_writer
description: متخصصة في صياغة رسائل البريد الرسمية
---
محتوى ضخم جداً من الإرشادات والنماذج التفصيلية للبريد الإلكتروني لا نريده أن يستهلك التوكنات!
''');

      final sqlFolder = Directory('${tempDir.path}/sql_expert')..createSync();
      File('${sqlFolder.path}/SKILL.md').writeAsStringSync('''
---
name: sql_expert
description: إرشادات كتابة وتدقيق استعلامات SQL المعقدة
---
تفاصيل استعلامات الـ JOIN والـ Window Functions وغيرها من الشروحات الطويلة.
''');

      // اكتشاف المهارات النصية
      await TextSkillService.instance.scanAndDiscoverTextSkills();

      // جلب الفهرس الخفيف
      final promptIndex = await TextSkillService.instance.getLightweightIndexPrompt();

      // التحقق من وجود الأسماء والأوصاف
      expect(promptIndex, contains('email_writer: متخصصة في صياغة رسائل البريد الرسمية'));
      expect(promptIndex, contains('sql_expert: إرشادات كتابة وتدقيق استعلامات SQL المعقدة'));
      expect(promptIndex, contains('load_text_skill(name)'));

      // التحقق الصارم: المحتوى الكامل لا يجب أن يظهر في الفهرس الخفيف إطلاقاً!
      expect(promptIndex, isNot(contains('محتوى ضخم جداً')));
      expect(promptIndex, isNot(contains('Window Functions')));
    });

    test('4. Two-Stage Loading: Stage 2 load_text_skill loads full content on-demand via ToolRegistry', () async {
      final codeFolder = Directory('${tempDir.path}/code_reviewer')..createSync();
      File('${codeFolder.path}/SKILL.md').writeAsStringSync('''
---
name: code_reviewer
description: مراجعة الكود واكتشاف الثغرات
---
### إرشادات مراجعة الكود
1. تحقق من صحة المدخلات.
2. تأكد من عدم وجود SQL Injection.
''');

      await TextSkillService.instance.scanAndDiscoverTextSkills();

      // استدعاء الأداة عبر ToolRegistry
      final result = await ToolRegistry.executeTool('load_text_skill', {'name': 'code_reviewer'});

      expect(result, contains('[دليل إرشادات المهارة النصية: code_reviewer]'));
      expect(result, contains('تحقق من صحة المدخلات'));
      expect(result, contains('SQL Injection'));
    });

    test('5. Disabled Text Skill is removed from lightweight index and cannot be loaded', () async {
      final skillFolder = Directory('${tempDir.path}/disabled_test')..createSync();
      File('${skillFolder.path}/SKILL.md').writeAsStringSync('''
---
name: toggle_test
description: مهارة لاختبار التعطيل
---
محتوى المهارة
''');

      await TextSkillService.instance.scanAndDiscoverTextSkills();

      // التحقق من وجودها بالفهرس وهي مفعّلة
      var index = await TextSkillService.instance.getLightweightIndexPrompt();
      expect(index, contains('toggle_test'));

      // تعطيل المهارة
      await TextSkillService.instance.toggleSkill('toggle_test', false);

      // التحقق من اختفائها من الفهرس الخفيف
      index = await TextSkillService.instance.getLightweightIndexPrompt();
      expect(index, isNot(contains('toggle_test')));

      // محاولة استدعاء الأداة لمهارة معطلة ترجع خطأ واضح
      final loadResult = await ToolRegistry.executeTool('load_text_skill', {'name': 'toggle_test'});
      expect(loadResult, contains('معطّلة حالياً من قبل المستخدم'));
    });
  });
}
