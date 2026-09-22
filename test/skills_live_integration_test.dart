import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/features/skills/services/sidecar_process_manager.dart';
import 'package:khwarizmi/features/skills/services/skill_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  group('Phase 8: Real Sidecar Process & Skill Live Lifecycle Integration Test', () {
    setUpAll(() async {
      await MemoryDatabase.initialize(customPath: ':memory:');
      await SkillDatabase.initialize();
      ToolRegistry.clear();
      ToolRegistry.initialize();
    });

    tearDownAll(() async {
      await SidecarProcessManager.instance.stopAll();
    });

    test('Full End-to-End Test: Real Discovery, Automatic Sidecar Process Start, Live Execution, and Clean Disable', () async {
      final skillService = SkillService.instance;

      // 1. اكتشاف الـ Skill من المجلد الفعلي %APPDATA%\Khwarizmi\Skills
      final discovered = await skillService.scanAndDiscoverSkills();
      expect(discovered.any((s) => s.manifest.name == 'get_mock_weather'), isTrue,
          reason: 'Must discover get_mock_weather from APPDATA');

      final record = discovered.firstWhere((s) => s.manifest.name == 'get_mock_weather');

      // 2. التحقق من قاعدة الأمان الإلزامية: لا تفعيل تلقائي عند أول اكتشاف (غير معتمد وغير مفعّل)
      expect(record.isApproved, isFalse);
      expect(record.isEnabled, isFalse);
      expect(ToolRegistry.isToolRegistered('get_mock_weather'), isFalse);
      expect(SidecarProcessManager.instance.isRunning('get_mock_weather'), isFalse);

      final pendingList = await skillService.getPendingApprovalSkills();
      expect(pendingList.any((s) => s.manifest.name == 'get_mock_weather'), isTrue);

      // 3. محاكاة موافقة المستخدم الصريحة (تفعيل الأداة)
      final approved = await skillService.approveAndEnableSkill('get_mock_weather');
      expect(approved, isTrue);

      // التحقق من أن خوارزمي شغّل العملية الفرعية تلقائياً عبر Process.start
      expect(SidecarProcessManager.instance.isRunning('get_mock_weather'), isTrue);
      expect(ToolRegistry.isToolRegistered('get_mock_weather'), isTrue);

      // 4. استدعاء الأداة فعلياً عبر شبكة HTTP المحلية من ToolRegistry مع انتظار جاهزية الخادم
      String executionResult = '';
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        try {
          executionResult = await ToolRegistry.executeTool(
            'get_mock_weather',
            {'city': 'دبي'},
          );
          if (!executionResult.contains('غير متاح حاليًا')) {
            break;
          }
        } catch (_) {}
      }

      // ignore: avoid_print
      print('=== REAL SIDECAR RESPONSE ===\n$executionResult\n=============================');

      final decoded = jsonDecode(executionResult);
      expect(decoded['status'], equals('success'));
      expect(decoded['city'], equals('دبي'));
      expect(decoded['temperature'], contains('29°C'));
      expect(decoded['sidecar'], contains('Khwarizmi Python Weather Sidecar'));

      // 5. التحقق من توفر الأداة للمهام المستقلة (Phase 7) بنفس مواصفات الأدوات
      final autoDefs = ToolRegistry.getAutonomousDefinitions();
      final autoTool = autoDefs.firstWhere((d) => d.name == 'get_mock_weather');
      expect(autoTool.isControlTool, isFalse);
      expect(autoTool.parameters['properties'], isNotNull);

      // 6. تعطيل الـ Skill يدوياً والتأكد من إيقاف العملية الفرعية وإلغاء تسجيلها
      await skillService.disableSkill('get_mock_weather');
      expect(SidecarProcessManager.instance.isRunning('get_mock_weather'), isFalse);
      expect(ToolRegistry.isToolRegistered('get_mock_weather'), isFalse);

      // محاولة استدعاء بعد التعطيل -> يجب أن يُرجع خطأ عدم وجود الأداة
      final postDisableResult = await ToolRegistry.executeTool(
        'get_mock_weather',
        {'city': 'دبي'},
      );
      expect(postDisableResult, contains('not found in registry'));
    });
  });
}
