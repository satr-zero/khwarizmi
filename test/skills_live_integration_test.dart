import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/skills/data/skill_database.dart';
import 'package:khwarizmi/features/skills/services/sidecar_process_manager.dart';
import 'package:khwarizmi/features/skills/services/skill_service.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  group('Phase 8: Real Sidecar Process & Skill Live Lifecycle Integration Test', () {
    late Directory tempSkillsDir;

    setUpAll(() async {
      await MemoryDatabase.initialize(customPath: ':memory:');
      await SkillDatabase.initialize();
      ToolRegistry.clear();
      ToolRegistry.initialize();

      // ── Fixture ذاتي الاحتواء ─────────────────────────────────────────────
      // الاختبار القديم كان يعتمد على مهارة مخلّفة يدوياً في %APPDATA%، فكان
      // يفشل على أي جهاز لا يحتويها. الآن ننشئ المهارة الكاملة (manifest +
      // خادم Python sidecar حقيقي) في مجلد مؤقت ونوجّه الخدمة إليه.
      tempSkillsDir = await Directory.systemTemp.createTemp(
        'khwarizmi_skills_live_',
      );
      final skillFolder = Directory(
        '${tempSkillsDir.path}\\get_mock_weather',
      );
      await skillFolder.create(recursive: true);

      await File('${skillFolder.path}\\manifest.json').writeAsString('''
{
  "name": "get_mock_weather",
  "display_name": "طقس تجريبي",
  "description": "أداة طقس وهمية لاختبار التكامل الحي مع العملية الفرعية",
  "endpoint": "http://localhost:5055/execute",
  "input_schema": {
    "type": "object",
    "properties": { "city": { "type": "string" } },
    "required": ["city"]
  },
  "permissions": ["network"],
  "version": "1.0.0",
  "start_command": "python sidecar.py"
}
''');

      await File('${skillFolder.path}\\sidecar.py').writeAsString('''
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode('utf-8'))
        except Exception:
            data = {}
        arguments = data.get('arguments') or {}
        city = arguments.get('city', '')
        response = {
            'status': 'success',
            'city': city,
            'temperature': '29°C',
            'sidecar': 'Khwarizmi Python Weather Sidecar v1.0',
        }
        payload = json.dumps(response).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass

HTTPServer(('127.0.0.1', 5055), Handler).serve_forever()
''');

      SkillService.instance.setCustomSkillsDirectory(tempSkillsDir.path);
    });

    tearDownAll(() async {
      await SidecarProcessManager.instance.stopAll();
      SkillService.instance.setCustomSkillsDirectory(null);
      try {
        if (await tempSkillsDir.exists()) {
          await tempSkillsDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Full End-to-End Test: Real Discovery, Automatic Sidecar Process Start, Live Execution, and Clean Disable', () async {
      final skillService = SkillService.instance;

      // 1. اكتشاف الـ Skill من مجلد الـ Fixture
      final discovered = await skillService.scanAndDiscoverSkills();
      expect(discovered.any((s) => s.manifest.name == 'get_mock_weather'), isTrue,
          reason: 'Must discover get_mock_weather from the fixture directory');

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
