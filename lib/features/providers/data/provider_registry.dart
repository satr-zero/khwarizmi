import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';
import 'package:khwarizmi/features/providers/domain/provider_config.dart';
import 'claude/claude_provider.dart';
import 'gemini/gemini_provider.dart';
import 'openai/openai_compatible_provider.dart';

class ProviderRegistry {
  static final Map<String, AiProvider> _providers = {};
  static final List<ProviderConfig> _presetConfigs = [
    const ProviderConfig(
      id: 'gemini',
      displayName: 'Google Gemini',
      type: 'gemini',
      baseUrl: 'https://generativelanguage.googleapis.com',
      defaultModel: 'gemini-3.8-flash',
      availableModels: [
        'gemini-3.8-flash',
        'gemini-3.7-flash',
        'gemini-3.6-flash',
        'gemini-3.5-flash',
        'gemini-2.5-flash',
        'gemini-2.5-pro',
      ],
      isCustom: false,
      supportsThinking: true,
      thinkingModelIds: [
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'gemini-3.5-flash',
        'gemini-3.6-flash',
        'gemini-3.7-flash',
        'gemini-3.8-flash',
      ],
    ),
    const ProviderConfig(
      id: 'claude',
      displayName: 'Anthropic Claude',
      type: 'claude',
      baseUrl: 'https://api.anthropic.com/v1',
      defaultModel: 'claude-3-7-sonnet-20250219',
      availableModels: [
        'claude-3-7-sonnet-20250219',
        'claude-3-5-sonnet-20241022',
        'claude-3-5-haiku-20241022',
        'claude-3-opus-20240229',
      ],
      isCustom: false,
      supportsThinking: true,
      thinkingModelIds: [
        'claude-3-7-sonnet-20250219',
      ],
    ),
    const ProviderConfig(
      id: 'openai',
      displayName: 'OpenAI GPT',
      type: 'openai_compatible',
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o',
      availableModels: [
        'gpt-4o',
        'gpt-4o-mini',
        'o3-mini',
        'o1',
      ],
      isCustom: false,
      supportsThinking: true,
      thinkingModelIds: [
        'o1',
        'o3-mini',
      ],
    ),
    const ProviderConfig(
      id: 'groq',
      displayName: 'Groq',
      type: 'openai_compatible',
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'llama-3.3-70b-versatile',
      availableModels: [
        'llama-3.3-70b-versatile',
        'llama-3.1-8b-instant',
        'mixtral-8x7b-32768',
        'deepseek-r1-distill-llama-70b',
      ],
      isCustom: false,
      supportsThinking: true,
      thinkingModelIds: [
        'deepseek-r1-distill-llama-70b',
      ],
    ),
    const ProviderConfig(
      id: 'deepseek',
      displayName: 'DeepSeek',
      type: 'openai_compatible',
      baseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'deepseek-chat',
      availableModels: [
        'deepseek-chat',
        'deepseek-reasoner',
      ],
      isCustom: false,
      supportsThinking: true,
      thinkingModelIds: [
        'deepseek-reasoner',
      ],
    ),
    const ProviderConfig(
      id: 'openrouter',
      displayName: 'OpenRouter',
      type: 'openai_compatible',
      baseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'anthropic/claude-3.7-sonnet',
      availableModels: [
        'anthropic/claude-3.7-sonnet',
        'openai/gpt-4o',
        'deepseek/deepseek-r1',
        'meta-llama/llama-3.3-70b-instruct',
      ],
      isCustom: false,
      supportsThinking: true,
      thinkingModelIds: [
        'anthropic/claude-3.7-sonnet',
        'deepseek/deepseek-r1',
      ],
    ),
    ProviderConfig(
      id: 'nvidia',
      displayName: 'NVIDIA Build (نماذج مجانية)',
      type: 'openai_compatible',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      defaultModel: 'moonshotai/kimi-k2.5',
      availableModels: [
        'moonshotai/kimi-k2.5',
        'nvidia/nemotron-3-super-120b-a12b',
        'meta/llama-3.3-70b-instruct',
      ],
      isCustom: false,
      extraBodyParams: {},
    ),
  ];

  static List<ProviderConfig> _customConfigs = [];
  static bool _isInitialized = false;

  /// Initializes preset providers and loads saved custom providers
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. Register presets
    _providers['gemini'] = GeminiProvider();
    _providers['claude'] = ClaudeProvider();

    for (final preset in _presetConfigs) {
      if (preset.type == 'openai_compatible') {
        _providers[preset.id] = OpenAiCompatibleProvider(
          id: preset.id,
          displayName: preset.displayName,
          baseUrl: preset.baseUrl,
          defaultModel: preset.defaultModel,
          availableModels: preset.availableModels,
          extraBodyParams: preset.extraBodyParams,
        );
      }
    }

    // 2. Load custom providers from secure storage
    try {
      final jsonStr = await SecureStorageService.getCustomProvidersJson();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        _customConfigs = list
            .map((item) => ProviderConfig.fromJson(item as Map<String, dynamic>))
            .toList();

        for (final custom in _customConfigs) {
          _providers[custom.id.toLowerCase()] = OpenAiCompatibleProvider(
            id: custom.id,
            displayName: custom.displayName,
            baseUrl: custom.baseUrl,
            defaultModel: custom.defaultModel,
            availableModels: custom.availableModels.isNotEmpty
                ? custom.availableModels
                : [custom.defaultModel],
            extraBodyParams: custom.extraBodyParams,
          );
        }
      }
    } catch (e) {
      debugPrint('[ProviderRegistry] Error loading custom providers: $e');
    }

    _isInitialized = true;
    debugPrint('[ProviderRegistry] Initialized with ${_providers.length} providers.');
  }

  static List<AiProvider> getAllProviders() {
    _ensurePresetsRegistered();
    return _providers.values.toList();
  }

  static List<ProviderConfig> getAllConfigs() {
    return [..._presetConfigs, ..._customConfigs];
  }

  static ProviderConfig? getConfig(String id) {
    final lower = id.toLowerCase();
    for (final c in getAllConfigs()) {
      if (c.id.toLowerCase() == lower) return c;
    }
    return null;
  }

  static AiProvider getProvider(String id) {
    _ensurePresetsRegistered();
    final lower = id.toLowerCase();
    if (_providers.containsKey(lower)) {
      return _providers[lower]!;
    }
    return _providers['gemini']!;
  }

  static void registerProvider(AiProvider provider) {
    _providers[provider.id.toLowerCase()] = provider;
  }

  /// Adds and saves a new custom provider
  static Future<void> addCustomProvider(ProviderConfig config) async {
    _customConfigs.removeWhere((c) => c.id.toLowerCase() == config.id.toLowerCase());
    _customConfigs.add(config);

    final provider = OpenAiCompatibleProvider(
      id: config.id,
      displayName: config.displayName,
      baseUrl: config.baseUrl,
      defaultModel: config.defaultModel,
      availableModels: config.availableModels.isNotEmpty
          ? config.availableModels
          : [config.defaultModel],
      extraBodyParams: config.extraBodyParams,
    );
    _providers[config.id.toLowerCase()] = provider;

    final jsonStr = jsonEncode(_customConfigs.map((c) => c.toJson()).toList());
    await SecureStorageService.saveCustomProvidersJson(jsonStr);
  }

  /// Deletes a custom provider and removes its saved API key
  static Future<void> deleteCustomProvider(String id) async {
    final lower = id.toLowerCase();
    _customConfigs.removeWhere((c) => c.id.toLowerCase() == lower);
    _providers.remove(lower);

    final jsonStr = jsonEncode(_customConfigs.map((c) => c.toJson()).toList());
    await SecureStorageService.saveCustomProvidersJson(jsonStr);
    await SecureStorageService.deleteApiKey(lower);
  }

  static void _ensurePresetsRegistered() {
    if (_providers.isEmpty) {
      _providers['gemini'] = GeminiProvider();
      _providers['claude'] = ClaudeProvider();
      for (final preset in _presetConfigs) {
        if (preset.type == 'openai_compatible') {
          _providers[preset.id] = OpenAiCompatibleProvider(
            id: preset.id,
            displayName: preset.displayName,
            baseUrl: preset.baseUrl,
            defaultModel: preset.defaultModel,
            availableModels: preset.availableModels,
            extraBodyParams: preset.extraBodyParams,
          );
        }
      }
    }
  }

  /// يختبر قدرة المزوّد/الموديل على التعامل مع استدعاء الأدوات (Tool Calling).
  /// يُستخدم خصيصًا للمزوّدين المخصصين (Custom Providers).
  static Future<bool> runModelCapabilityTest(String providerId, String apiKey) async {
    _ensurePresetsRegistered();
    final provider = getProvider(providerId);
    const testTool = ToolDefinition(
      name: 'test_capability_ping',
      description: 'Ping test tool to verify function calling capability.',
      parameters: {
        'type': 'OBJECT',
        'properties': {
          'message': {'type': 'STRING', 'description': 'Echo message'}
        },
        'required': ['message'],
      },
    );

    bool receivedToolCall = false;
    bool receivedText = false;
    bool receivedError = false;

    try {
      final stream = provider.sendMessage(
        history: [
          ChatMessage(
            id: 'test_cap_${DateTime.now().millisecondsSinceEpoch}',
            role: MessageRole.user,
            content: 'Please invoke the tool "test_capability_ping" with message="ping".',
            timestamp: DateTime.now(),
          ),
        ],
        availableTools: const [testTool],
        systemPrompt: 'You are a test assistant. If tools are available, invoke test_capability_ping.',
        apiKey: apiKey,
      );

      await for (final event in stream) {
        if (event is AgentToolCallEvent) {
          receivedToolCall = true;
        } else if (event is AgentTextChunk && event.text.isNotEmpty) {
          receivedText = true;
        } else if (event is AgentErrorEvent) {
          if (event.code == 'TOOLS_NOT_SUPPORTED' ||
              event.message.toLowerCase().contains('tool') ||
              event.message.toLowerCase().contains('function')) {
            receivedError = true;
          }
        }
      }

      final success = receivedToolCall || (receivedText && !receivedError);

      final lower = providerId.toLowerCase();
      final idx = _customConfigs.indexWhere((c) => c.id.toLowerCase() == lower);
      if (idx != -1) {
        _customConfigs[idx] = _customConfigs[idx].copyWith(toolCallCapable: success);
        final jsonStr = jsonEncode(_customConfigs.map((c) => c.toJson()).toList());
        await SecureStorageService.saveCustomProvidersJson(jsonStr);
      }

      return success;
    } catch (e) {
      debugPrint('[ProviderRegistry] Capability test error: $e');
      return false;
    }
  }
}
