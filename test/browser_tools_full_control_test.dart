import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/tools/built_in/browser_tools.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    ToolRegistry.initialize();
  });

  group('Full Autonomous Browser Control Suite Tests', () {
    test('ToolRegistry includes all full browser control tools in chat and autonomous mode', () {
      final chatDefs = ToolRegistry.getChatDefinitions().map((d) => d.name).toList();
      final autoDefs = ToolRegistry.getAutonomousDefinitions().map((d) => d.name).toList();

      const expectedBrowserTools = [
        'browse_url',
        'scroll_page',
        'inspect_visual_page',
        'click_element',
        'fill_input',
        'download_file',
      ];

      for (final tool in expectedBrowserTools) {
        expect(chatDefs, contains(tool), reason: 'Chat definitions must include $tool');
        expect(autoDefs, contains(tool), reason: 'Autonomous definitions must include $tool');
      }
    });

    test('ScrollPageTool definition specifies direction, amount, and selector parameters', () {
      final tool = ScrollPageTool();
      final def = tool.definition;

      expect(def.name, equals('scroll_page'));
      expect(def.description, contains('scroll'));
      expect(def.parameters['properties'].containsKey('direction'), isTrue);
      expect(def.parameters['properties'].containsKey('amount'), isTrue);
      expect(def.parameters['properties'].containsKey('selector'), isTrue);
    });

    test('InspectVisualPageTool definition is valid and describes visual perception', () {
      final tool = InspectVisualPageTool();
      final def = tool.definition;

      expect(def.name, equals('inspect_visual_page'));
      expect(def.description, contains('color'));
    });

    test('ClickElementTool supports clicking by selector or by visible text', () {
      final tool = ClickElementTool();
      final def = tool.definition;

      expect(def.name, equals('click_element'));
      expect(def.parameters['properties'].containsKey('selector'), isTrue);
      expect(def.parameters['properties'].containsKey('text'), isTrue);
      expect(def.parameters['properties'].containsKey('confirmation_token'), isTrue);
    });

    test('ClickElementTool returns clear error when both selector and text are omitted', () async {
      final tool = ClickElementTool();
      final res = await tool.execute({});
      final decoded = jsonDecode(res) as Map<String, dynamic>;

      expect(decoded.containsKey('error'), isTrue);
      expect(decoded['error'], contains('يجب تحديد'));
    });

    test('FillInputTool definition specifies required selector and text parameters', () {
      final tool = FillInputTool();
      final def = tool.definition;

      expect(def.name, equals('fill_input'));
      expect(def.parameters['properties'].containsKey('selector'), isTrue);
      expect(def.parameters['properties'].containsKey('text'), isTrue);
      expect(def.parameters['required'], contains('selector'));
      expect(def.parameters['required'], contains('text'));
    });

    test('FillInputTool returns clear error when selector or text is missing', () async {
      final tool = FillInputTool();

      final res1 = await tool.execute({'text': 'Hello'});
      expect(jsonDecode(res1)['error'], contains('selector'));

      final res2 = await tool.execute({'selector': '#query'});
      expect(jsonDecode(res2)['error'], contains('text'));
    });
  });
}
