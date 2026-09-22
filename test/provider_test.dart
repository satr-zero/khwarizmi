import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/data/claude/claude_provider.dart';
import 'package:khwarizmi/features/providers/data/openai/openai_compatible_provider.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/providers/domain/provider_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 4: Tool Schema Converters Tests', () {
    const sampleTool = ToolDefinition(
      name: 'get_weather',
      description: 'Gets current weather for a city',
      parameters: {
        'type': 'object',
        'properties': {
          'city': {'type': 'string', 'description': 'City name'},
        },
        'required': ['city'],
      },
    );

    test('ToolDefinition converts accurately to OpenAI function schema', () {
      final openAiSchema = sampleTool.toOpenAiSchema();
      expect(openAiSchema['type'], equals('function'));
      expect(openAiSchema['function']['name'], equals('get_weather'));
      expect(openAiSchema['function']['description'], equals('Gets current weather for a city'));
      expect(openAiSchema['function']['parameters']['required'], contains('city'));
    });

    test('ToolDefinition converts accurately to Anthropic Claude schema', () {
      final claudeSchema = sampleTool.toClaudeSchema();
      expect(claudeSchema['name'], equals('get_weather'));
      expect(claudeSchema['description'], equals('Gets current weather for a city'));
      expect(claudeSchema.containsKey('input_schema'), isTrue);
      expect(claudeSchema['input_schema']['properties']['city']['type'], equals('string'));
    });
  });

  group('Phase 4: OpenAiCompatibleProvider Tests', () {
    test('Returns clear Arabic error when API key is empty', () async {
      final provider = OpenAiCompatibleProvider(
        id: 'groq',
        displayName: 'Groq',
        baseUrl: 'https://api.groq.com/openai/v1',
        defaultModel: 'llama-3.3-70b-versatile',
      );

      final events = await provider.sendMessage(
        history: [],
        availableTools: [],
        systemPrompt: 'System',
        apiKey: '   ',
      ).toList();

      expect(events.length, equals(1));
      expect(events.first, isA<AgentErrorEvent>());
      final error = events.first as AgentErrorEvent;
      expect(error.code, equals('MISSING_API_KEY'));
      expect(error.message, contains('Groq'));
    });

    test('Constructs request properly for different base URLs and handles text streaming', () async {
      late Uri capturedUrl;
      late Map<String, String> capturedHeaders;
      late Map<String, dynamic> capturedBody;

      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        capturedHeaders = request.headers;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;

        const sseStream = 'data: {"choices":[{"delta":{"content":"مرحبًا "}}]}\n\n'
            'data: {"choices":[{"delta":{"content":"بك!"}}]}\n\n'
            'data: [DONE]\n\n';

        return http.Response.bytes(
          utf8.encode(sseStream),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final provider = OpenAiCompatibleProvider(
        id: 'deepseek',
        displayName: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        defaultModel: 'deepseek-chat',
        client: mockClient,
      );

      final events = await provider.sendMessage(
        history: [
          ChatMessage(
            id: 'm1',
            role: MessageRole.user,
            content: 'مرحبا',
            timestamp: DateTime.now(),
          ),
        ],
        availableTools: [],
        systemPrompt: 'أنت خوارزمي',
        apiKey: 'sk-deepseek-test-key',
        modelName: 'deepseek-reasoner',
      ).toList();

      expect(capturedUrl.toString(), equals('https://api.deepseek.com/v1/chat/completions'));
      expect(capturedHeaders['Authorization'], equals('Bearer sk-deepseek-test-key'));
      expect(capturedBody['model'], equals('deepseek-reasoner'));
      expect(capturedBody['messages'][0]['role'], equals('system'));
      expect(capturedBody['messages'][1]['role'], equals('user'));

      // Check text events
      final textEvents = events.whereType<AgentTextChunk>().toList();
      expect(textEvents.length, equals(2));
      expect(textEvents[0].text, equals('مرحبًا '));
      expect(textEvents[1].text, equals('بك!'));
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('Accumulates streaming tool call chunks correctly', () async {
      final mockClient = MockClient((request) async {
        const sseToolStream =
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_123","function":{"name":"search_memory","arguments":""}}]}}]}\n\n'
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\": "}}]}}]}\n\n'
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"عقد العمل\\"}"}}]}}]}\n\n'
            'data: [DONE]\n\n';

        return http.Response.bytes(
          utf8.encode(sseToolStream),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final provider = OpenAiCompatibleProvider(
        id: 'openai',
        displayName: 'OpenAI GPT',
        baseUrl: 'https://api.openai.com/v1',
        defaultModel: 'gpt-4o',
        client: mockClient,
      );

      final events = await provider.sendMessage(
        history: [],
        availableTools: [
          const ToolDefinition(
            name: 'search_memory',
            description: 'Searches memory',
            parameters: {'type': 'object'},
          ),
        ],
        systemPrompt: '',
        apiKey: 'sk-test',
      ).toList();

      final toolEvents = events.whereType<AgentToolCallEvent>().toList();
      expect(toolEvents.length, equals(1));
      expect(toolEvents.first.toolCall.callId, equals('call_123'));
      expect(toolEvents.first.toolCall.toolName, equals('search_memory'));
      expect(toolEvents.first.toolCall.arguments['query'], equals('عقد العمل'));
    });
  });

  group('Phase 4: ClaudeProvider Tests', () {
    test('Returns clear Arabic error when API key is empty', () async {
      final provider = ClaudeProvider();
      final events = await provider.sendMessage(
        history: [],
        availableTools: [],
        systemPrompt: '',
        apiKey: '',
      ).toList();

      expect(events.length, equals(1));
      expect(events.first, isA<AgentErrorEvent>());
      final error = events.first as AgentErrorEvent;
      expect(error.code, equals('MISSING_API_KEY'));
      expect(error.message, contains('Claude'));
    });

    test('Builds request with Anthropic headers and parses SSE text streaming', () async {
      late Uri capturedUrl;
      late Map<String, String> capturedHeaders;
      late Map<String, dynamic> capturedBody;

      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        capturedHeaders = request.headers;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;

        const sseStream =
            'event: message_start\ndata: {"type":"message_start","message":{"id":"msg_1"}}\n\n'
            'event: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
            'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"سلام "}}\n\n'
            'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"عليكم"}}\n\n'
            'event: message_stop\ndata: {"type":"message_stop"}\n\n';

        return http.Response.bytes(
          utf8.encode(sseStream),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final provider = ClaudeProvider(client: mockClient);

      final events = await provider.sendMessage(
        history: [
          ChatMessage(
            id: 'm1',
            role: MessageRole.user,
            content: 'مرحبا',
            timestamp: DateTime.now(),
          ),
        ],
        availableTools: [],
        systemPrompt: 'نظام خوارزمي',
        apiKey: 'sk-ant-test-key',
      ).toList();

      expect(capturedUrl.toString(), equals('https://api.anthropic.com/v1/messages'));
      expect(capturedHeaders['x-api-key'], equals('sk-ant-test-key'));
      expect(capturedHeaders['anthropic-version'], equals('2023-06-01'));
      expect(capturedBody['system'], equals('نظام خوارزمي'));
      expect(capturedBody['max_tokens'], equals(4096));

      final textEvents = events.whereType<AgentTextChunk>().toList();
      expect(textEvents.length, equals(2));
      expect(textEvents[0].text, equals('سلام '));
      expect(textEvents[1].text, equals('عليكم'));
    });

    test('Parses Anthropic tool_use SSE events properly', () async {
      final mockClient = MockClient((request) async {
        const sseToolStream =
            'event: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_999","name":"store_memory","input":{}}}\n\n'
            'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"content\\": \\"معلومة"}}'
            '\n\n'
            'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":" مهمة\\"}"}}\n\n'
            'event: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\n'
            'event: message_stop\ndata: {"type":"message_stop"}\n\n';

        return http.Response.bytes(
          utf8.encode(sseToolStream),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });

      final provider = ClaudeProvider(client: mockClient);

      final events = await provider.sendMessage(
        history: [],
        availableTools: [
          const ToolDefinition(
            name: 'store_memory',
            description: 'Stores memory',
            parameters: {'type': 'object'},
          ),
        ],
        systemPrompt: '',
        apiKey: 'sk-ant-key',
      ).toList();

      final toolEvents = events.whereType<AgentToolCallEvent>().toList();
      expect(toolEvents.length, equals(1));
      expect(toolEvents.first.toolCall.callId, equals('toolu_999'));
      expect(toolEvents.first.toolCall.toolName, equals('store_memory'));
      expect(toolEvents.first.toolCall.arguments['content'], equals('معلومة مهمة'));
    });
  });

  group('Phase 4: ProviderRegistry & Custom Providers Tests', () {
    test('Initializes with all mandatory presets', () async {
      await ProviderRegistry.initialize();

      final presets = ProviderRegistry.getAllConfigs();
      final ids = presets.map((p) => p.id).toList();

      expect(ids, contains('gemini'));
      expect(ids, contains('claude'));
      expect(ids, contains('openai'));
      expect(ids, contains('groq'));
      expect(ids, contains('deepseek'));
      expect(ids, contains('openrouter'));
    });

    test('Can register, persist, and delete a custom provider', () async {
      const customConfig = ProviderConfig(
        id: 'custom_ollama',
        displayName: 'Ollama Llama 3',
        type: 'openai_compatible',
        baseUrl: 'http://localhost:11434/v1',
        defaultModel: 'llama3:8b',
        availableModels: ['llama3:8b'],
        isCustom: true,
      );

      await ProviderRegistry.addCustomProvider(customConfig);

      final retrievedProvider = ProviderRegistry.getProvider('custom_ollama');
      expect(retrievedProvider.displayName, equals('Ollama Llama 3'));
      expect(retrievedProvider.defaultModel, equals('llama3:8b'));

      // Check config
      final config = ProviderRegistry.getConfig('custom_ollama');
      expect(config, isNotNull);
      expect(config!.isCustom, isTrue);

      // Delete custom provider
      await ProviderRegistry.deleteCustomProvider('custom_ollama');
      final afterDelete = ProviderRegistry.getConfig('custom_ollama');
      expect(afterDelete, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NVIDIA Build preset — extraBodyParams tests
  // ─────────────────────────────────────────────────────────────────────────
  group('NVIDIA Build Preset & extraBodyParams', () {
    /// يتحقق من أن extraBodyParams تُدمَج في جسم الطلب المُرسَل
    test('extraBodyParams are merged into request body', () async {
      const extraParams = {
        'reasoning_effort': 'max',
        'temperature': 0.6,
      };

      // نبني طلباً وهمياً ونتحقق من دمج المعاملات
      late Map<String, dynamic> capturedBody;

      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        // نعيد streaming response فارغة بشكل صحيح
        return http.Response(
          'data: {"choices":[{"delta":{"content":"test"},"finish_reason":null}]}\ndata: [DONE]\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final provider = OpenAiCompatibleProvider(
        id: 'nvidia_test',
        displayName: 'NVIDIA Test',
        baseUrl: 'https://integrate.api.nvidia.com/v1',
        defaultModel: 'moonshotai/kimi-k2.5',
        extraBodyParams: extraParams,
        client: mockClient,
      );

      final events = provider.sendMessage(
        history: [
          ChatMessage(
            id: 'msg1',
            role: MessageRole.user,
            content: 'مرحباً',
            timestamp: DateTime.now(),
          ),
        ],
        availableTools: [],
        systemPrompt: 'أنت خوارزمي',
        apiKey: 'test-key',
        modelName: 'moonshotai/kimi-k2.5',
      );

      // استنزف الـ stream
      await events.toList();

      // تحقق من دمج extraBodyParams
      expect(capturedBody['reasoning_effort'], equals('max'));
      expect(capturedBody['temperature'], equals(0.6));
      expect(capturedBody['model'], equals('moonshotai/kimi-k2.5'));
      expect(capturedBody['stream'], isTrue);
    });

    /// يتحقق من أن المزوّدين الآخرين لا تتأثر طلباتهم
    test('other providers without extraBodyParams are not affected', () async {
      late Map<String, dynamic> capturedBody;

      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}\ndata: [DONE]\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final provider = OpenAiCompatibleProvider(
        id: 'openai_test',
        displayName: 'OpenAI Test',
        baseUrl: 'https://api.openai.com/v1',
        defaultModel: 'gpt-4o',
        // بدون extraBodyParams
        client: mockClient,
      );

      final events = provider.sendMessage(
        history: [
          ChatMessage(
            id: 'msg1',
            role: MessageRole.user,
            content: 'Hello',
            timestamp: DateTime.now(),
          ),
        ],
        availableTools: [],
        systemPrompt: 'You are helpful',
        apiKey: 'sk-test',
        modelName: 'gpt-4o',
      );

      await events.toList();

      // لا يجب أن يكون هناك reasoning_effort أو حقول NVIDIA
      expect(capturedBody.containsKey('reasoning_effort'), isFalse);
      expect(capturedBody['model'], equals('gpt-4o'));
    });

    /// يتحقق من وجود NVIDIA كـ preset مسجّل في Registry
    test('NVIDIA preset is registered in ProviderRegistry', () {
      final config = ProviderRegistry.getConfig('nvidia');
      expect(config, isNotNull);
      expect(config!.id, equals('nvidia'));
      expect(config.displayName, contains('NVIDIA'));
      expect(config.baseUrl, equals('https://integrate.api.nvidia.com/v1'));
      expect(config.defaultModel, equals('moonshotai/kimi-k2.5'));
      expect(config.isCustom, isFalse);
    });

    /// يتحقق من أن القائمة الاحتياطية تتضمن النماذج المطلوبة
    test('NVIDIA fallback models include required models', () {
      final config = ProviderRegistry.getConfig('nvidia');
      expect(config, isNotNull);
      final models = config!.availableModels;
      expect(models, contains('moonshotai/kimi-k2.5'));
      expect(models, contains('nvidia/nemotron-3-super-120b-a12b'));
      expect(models, contains('meta/llama-3.3-70b-instruct'));
    });

    /// يتحقق من أن fetchModels تعود بالقائمة الاحتياطية عند فشل الطلب
    test('fetchModels falls back to preset list on network error', () async {
      final mockClient = MockClient(
        (_) async => throw Exception('Network error'),
      );

      final provider = OpenAiCompatibleProvider(
        id: 'nvidia',
        displayName: 'NVIDIA Build',
        baseUrl: 'https://integrate.api.nvidia.com/v1',
        defaultModel: 'moonshotai/kimi-k2.5',
        availableModels: const [
          'moonshotai/kimi-k2.5',
          'nvidia/nemotron-3-super-120b-a12b',
          'meta/llama-3.3-70b-instruct',
        ],
        client: mockClient,
      );

      final models = await provider.fetchModels('test-key');
      expect(models, contains('moonshotai/kimi-k2.5'));
      expect(models.length, greaterThanOrEqualTo(3));
    });

    /// يتحقق من أن fetchModels تعود بالقائمة الحية عند نجاح الطلب
    test('fetchModels returns live list from /v1/models on success', () async {
      final liveModels = ['moonshotai/kimi-k2.5', 'nvidia/llama-3.1-nemotron-ultra-253b-v1'];

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': liveModels.map((m) => {'id': m}).toList(),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = OpenAiCompatibleProvider(
        id: 'nvidia',
        displayName: 'NVIDIA Build',
        baseUrl: 'https://integrate.api.nvidia.com/v1',
        defaultModel: 'moonshotai/kimi-k2.5',
        availableModels: const ['moonshotai/kimi-k2.5'],
        client: mockClient,
      );

      final models = await provider.fetchModels('nvapi-test-key');
      expect(models, containsAll(liveModels));
    });
  });
}
