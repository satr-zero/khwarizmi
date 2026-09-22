import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/core/services/agent_identity_service.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/data/gemini/gemini_provider.dart';
import 'package:khwarizmi/features/tools/built_in/system_info_tool.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 0 Core Engine Tests', () {
    test('AgentIdentityService loads system prompt containing Khwarizmi identity', () async {
      final prompt = await AgentIdentityService.loadSystemPrompt();
      expect(prompt.isNotEmpty, isTrue);
      expect(prompt.contains('Khwarizmi') || prompt.contains('خوارزمي'), isTrue);
    });

    test('AGENT.md is bundled and loadable directly via rootBundle asset', () async {
      final assetContent = await rootBundle.loadString('AGENT.md');
      expect(assetContent.isNotEmpty, isTrue);
      expect(assetContent.contains('خوارزمي') || assetContent.contains('Khwarizmi'), isTrue);
    });

    test('SystemTimeTool returns valid JSON with current_time', () async {
      final tool = SystemTimeTool();
      final resultStr = await tool.execute({});
      final data = jsonDecode(resultStr) as Map<String, dynamic>;

      expect(data.containsKey('current_time'), isTrue);
      expect(data.containsKey('day'), isTrue);
      expect(data.containsKey('timezone'), isTrue);
    });

    test('ToolRegistry initializes and executes registered tools', () async {
      ToolRegistry.initialize();
      final definitions = ToolRegistry.getAvailableDefinitions();
      expect(definitions.any((d) => d.name == 'get_system_time'), isTrue);

      final output = await ToolRegistry.executeTool('get_system_time', {});
      expect(output.contains('current_time'), isTrue);

      final unknownOutput = await ToolRegistry.executeTool('unknown_tool', {});
      expect(unknownOutput.contains('not found'), isTrue);
    });

    test('ToolDefinition converts to Gemini schema format accurately', () {
      const toolDef = ToolDefinition(
        name: 'test_tool',
        description: 'A test tool for verification',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'query': {'type': 'STRING', 'description': 'search query'}
          },
          'required': ['query']
        },
      );

      final schema = toolDef.toGeminiSchema();
      expect(schema['name'], equals('test_tool'));
      expect(schema['description'], equals('A test tool for verification'));
      expect(schema['parameters']['type'], equals('OBJECT'));
    });

    test('GeminiProvider yields error if API key is empty', () async {
      final provider = GeminiProvider();
      expect(provider.id, equals('gemini'));
      expect(provider.availableModels.contains('gemini-3.8-flash'), isTrue);

      final stream = provider.sendMessage(
        history: [
          ChatMessage(
            id: '1',
            role: MessageRole.user,
            content: 'Hello',
            timestamp: DateTime.now(),
          ),
        ],
        availableTools: [],
        systemPrompt: 'You are Khwarizmi',
        apiKey: '',
      );

      final events = await stream.toList();
      expect(events.isNotEmpty, isTrue);
      expect(events.first.runtimeType.toString(), equals('AgentErrorEvent'));
    });
  });
}
