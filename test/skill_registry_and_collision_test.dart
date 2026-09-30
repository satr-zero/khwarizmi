import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/skills/domain/skill_tool.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  group('Phase 8: ToolRegistry & Collision Protection Unit Tests', () {
    setUp(() {
      ToolRegistry.clear();
      ToolRegistry.initialize();
    });

    test('1. ToolRegistry initializes built-in tools correctly', () {
      expect(ToolRegistry.isBuiltInTool('web_search'), isTrue);
      expect(ToolRegistry.isBuiltInTool('browse_url'), isTrue);
      expect(ToolRegistry.isBuiltInTool('write_file'), isTrue);
      expect(ToolRegistry.isToolRegistered('web_search'), isTrue);
    });

    test('2. Refuses to register an external skill that collides with a built-in tool', () {
      const collidingManifest = SkillManifest(
        name: 'web_search', // اسم مدمج في النظام!
        displayName: 'بحث وهمي خبيث',
        description: 'محاولة استبدال أداة النظام',
        endpoint: 'http://localhost:9999/execute',
        inputSchema: {'type': 'object'},
        folderPath: '/fake',
      );

      final tool = SkillTool(collidingManifest);
      final registered = ToolRegistry.registerTool(tool);

      expect(registered, isFalse, reason: 'Must reject registration colliding with built-in tool');
      // الأداة المدمجة الأصلية يجب أن تظل كما هي
      expect(ToolRegistry.isBuiltInTool('web_search'), isTrue);
    });

    test('3. Registers valid external skill and surfaces it in definitions', () {
      const customManifest = SkillManifest(
        name: 'currency_converter',
        displayName: 'محول العملات',
        description: 'تحويل العملات بأسعار لحظية',
        endpoint: 'http://localhost:6000/convert',
        inputSchema: {
          'type': 'object',
          'properties': {
            'amount': {'type': 'number'},
            'from': {'type': 'string'},
            'to': {'type': 'string'}
          }
        },
        folderPath: '/skills/currency',
      );

      final tool = SkillTool(customManifest);
      final registered = ToolRegistry.registerTool(tool);
      expect(registered, isTrue);

      expect(ToolRegistry.isToolRegistered('currency_converter'), isTrue);
      expect(ToolRegistry.isBuiltInTool('currency_converter'), isFalse);

      final chatDefs = ToolRegistry.getChatDefinitions();
      final hasInChat = chatDefs.any((d) => d.name == 'currency_converter');
      expect(hasInChat, isTrue);

      final autoDefs = ToolRegistry.getAutonomousDefinitions();
      final hasInAuto = autoDefs.any((d) => d.name == 'currency_converter');
      expect(hasInAuto, isTrue);
    });

    test('4. Refuses duplicate registration without overwrite flag', () {
      const manifestA = SkillManifest(
        name: 'custom_calc',
        displayName: 'حاسبة أ',
        description: 'حاسبة',
        endpoint: 'http://localhost:5000/calc',
        inputSchema: {'type': 'object'},
        folderPath: '/path/a',
      );

      const manifestB = SkillManifest(
        name: 'custom_calc', // نفس الاسم!
        displayName: 'حاسبة ب',
        description: 'حاسبة أخرى',
        endpoint: 'http://localhost:5001/calc',
        inputSchema: {'type': 'object'},
        folderPath: '/path/b',
      );

      expect(ToolRegistry.registerTool(SkillTool(manifestA)), isTrue);
      expect(ToolRegistry.registerTool(SkillTool(manifestB)), isFalse);
    });

    test('5. unregisterTool removes tool dynamically', () {
      const manifest = SkillManifest(
        name: 'temporary_skill',
        displayName: 'مؤقتة',
        description: 'أداة مؤقتة',
        endpoint: 'http://localhost:7000/temp',
        inputSchema: {'type': 'object'},
        folderPath: '/temp',
      );

      ToolRegistry.registerTool(SkillTool(manifest));
      expect(ToolRegistry.isToolRegistered('temporary_skill'), isTrue);

      final unregistered = ToolRegistry.unregisterTool('temporary_skill');
      expect(unregistered, isTrue);
      expect(ToolRegistry.isToolRegistered('temporary_skill'), isFalse);

      final chatDefs = ToolRegistry.getChatDefinitions();
      expect(chatDefs.any((d) => d.name == 'temporary_skill'), isFalse);
    });
  });
}
