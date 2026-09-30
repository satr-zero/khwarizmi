import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/providers/data/local/local_model_provider.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';
import 'package:khwarizmi/features/providers/domain/provider_config.dart';

/// Ollama provider for running local models via Ollama server
/// Ollama exposes an OpenAI-compatible API at /v1/chat/completions and /v1/models
/// Default URL: http://localhost:11434
class OllamaProvider extends LocalModelProvider {
  static const String defaultBaseUrl = 'http://localhost:11434';
  static const String providerId = 'ollama';
  static const String displayNameValue = 'Ollama';
  static const String defaultModelValue = 'llama3.2';

  /// Creates an Ollama provider with default settings
  OllamaProvider({
    String? baseUrl,
    String? defaultModel,
    List<String>? availableModels,
    http.Client? client,
  }) : super(
         id: providerId,
         displayName: displayNameValue,
         baseUrl: baseUrl ?? defaultBaseUrl,
         defaultModel: defaultModel ?? defaultModelValue,
         availableModels: availableModels ?? const [],
         client: client,
       );

  /// Creates an Ollama provider from a ProviderConfig
  factory OllamaProvider.fromConfig(ProviderConfig config) {
    return OllamaProvider(
      baseUrl: config.baseUrl,
      defaultModel: config.defaultModel,
      availableModels: config.availableModels.isNotEmpty
          ? config.availableModels
          : null,
    );
  }

  @override
  String get chatEndpoint {
    // Ollama uses the same /v1/chat/completions endpoint as OpenAI
    return super.chatEndpoint;
  }

  @override
  String get modelsEndpoint {
    // Ollama also supports /api/tags for model listing
    // We'll use the standard /v1/models but can override if needed
    return super.modelsEndpoint;
  }

  /// Ollama-specific health check endpoint
  @override
  String get healthEndpoint => '$normalizedBaseUrl/api/version';

  @override
  Future<bool> checkHealth() async {
    final httpClient = client ?? http.Client();
    try {
      // Try Ollama's native API first
      final response = await httpClient
          .get(Uri.parse(healthEndpoint))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint(
        '[$displayName] Native health check failed, trying OpenAI-compatible: $e',
      );
    } finally {
      if (client == null) httpClient.close();
    }

    // Fallback to OpenAI-compatible health check
    return super.checkHealth();
  }

  @override
  Future<List<String>> fetchModels(String apiKey) async {
    final httpClient = client ?? http.Client();
    try {
      // First try Ollama's native /api/tags endpoint
      final nativeUrl = Uri.parse('$normalizedBaseUrl/api/tags');
      final response = await httpClient
          .get(nativeUrl, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final models = json['models'] as List<dynamic>?;
        if (models != null && models.isNotEmpty) {
          final ids = models
              .map((item) => (item as Map<String, dynamic>)['name']?.toString())
              .whereType<String>()
              .toList();
          if (ids.isNotEmpty) {
            ids.sort();
            return ids;
          }
        }
      }
    } catch (e) {
      debugPrint(
        '[$displayName] Native fetchModels failed, trying OpenAI-compatible: $e',
      );
    } finally {
      if (client == null) httpClient.close();
    }

    // Fallback to OpenAI-compatible endpoint
    return super.fetchModels(apiKey);
  }

  @override
  void addThinkingConfig(
    Map<String, dynamic> requestBody,
    ThinkingConfig thinking,
  ) {
    // Ollama supports thinking/reasoning via the 'think' parameter
    // Some models support: "think": true or "think": { "enabled": true, "budget_tokens": 1000 }
    if (thinking.enabled) {
      if (thinking.budgetTokens != null && thinking.budgetTokens! > 0) {
        requestBody['think'] = {
          'enabled': true,
          'budget_tokens': thinking.budgetTokens,
        };
      } else {
        requestBody['think'] = true;
      }
    }
  }

  /// Creates a provider configuration for Ollama
  static ProviderConfig createConfig({
    String? baseUrl,
    String? defaultModel,
    List<String>? availableModels,
    bool isCustom = false,
  }) {
    return ProviderConfig(
      id: providerId,
      displayName: displayNameValue,
      type: 'ollama',
      baseUrl: baseUrl ?? defaultBaseUrl,
      defaultModel: defaultModel ?? defaultModelValue,
      availableModels: availableModels ?? const [],
      isCustom: isCustom,
      supportsThinking: true,
      supportsAdaptiveThinking: false,
    );
  }
}

/// LM Studio provider for running local models via LM Studio server
/// LM Studio exposes an OpenAI-compatible API
/// Default URL: http://localhost:1234
class LMStudioProvider extends LocalModelProvider {
  static const String defaultBaseUrl = 'http://localhost:1234';
  static const String providerId = 'lm_studio';
  static const String displayNameValue = 'LM Studio';
  static const String defaultModelValue = 'local-model';

  LMStudioProvider({
    String? baseUrl,
    String? defaultModel,
    List<String>? availableModels,
    http.Client? client,
  }) : super(
         id: providerId,
         displayName: displayNameValue,
         baseUrl: baseUrl ?? defaultBaseUrl,
         defaultModel: defaultModel ?? defaultModelValue,
         availableModels: availableModels ?? const [],
         client: client,
       );

  factory LMStudioProvider.fromConfig(ProviderConfig config) {
    return LMStudioProvider(
      baseUrl: config.baseUrl,
      defaultModel: config.defaultModel,
      availableModels: config.availableModels.isNotEmpty
          ? config.availableModels
          : null,
    );
  }

  @override
  String get healthEndpoint => '$normalizedBaseUrl/v1/models';

  @override
  void addThinkingConfig(
    Map<String, dynamic> requestBody,
    ThinkingConfig thinking,
  ) {
    // LM Studio may support reasoning via provider-specific extensions
    // For now, use standard OpenAI-compatible reasoning parameters
    if (thinking.enabled) {
      requestBody['reasoning'] = {
        'enabled': true,
        if (thinking.budgetTokens != null)
          'budget_tokens': thinking.budgetTokens,
      };
    }
  }

  static ProviderConfig createConfig({
    String? baseUrl,
    String? defaultModel,
    List<String>? availableModels,
    bool isCustom = false,
  }) {
    return ProviderConfig(
      id: providerId,
      displayName: displayNameValue,
      type: 'lm_studio',
      baseUrl: baseUrl ?? defaultBaseUrl,
      defaultModel: defaultModel ?? defaultModelValue,
      availableModels: availableModels ?? const [],
      isCustom: isCustom,
      supportsThinking: true,
      supportsAdaptiveThinking: false,
    );
  }
}

/// vLLM provider for running local models via vLLM server
/// vLLM exposes an OpenAI-compatible API
/// Default URL: http://localhost:8000
class VLLMProvider extends LocalModelProvider {
  static const String defaultBaseUrl = 'http://localhost:8000';
  static const String providerId = 'vllm';
  static const String displayNameValue = 'vLLM';
  static const String defaultModelValue = 'local-model';

  VLLMProvider({
    String? baseUrl,
    String? defaultModel,
    List<String>? availableModels,
    http.Client? client,
  }) : super(
         id: providerId,
         displayName: displayNameValue,
         baseUrl: baseUrl ?? defaultBaseUrl,
         defaultModel: defaultModel ?? defaultModelValue,
         availableModels: availableModels ?? const [],
         client: client,
       );

  factory VLLMProvider.fromConfig(ProviderConfig config) {
    return VLLMProvider(
      baseUrl: config.baseUrl,
      defaultModel: config.defaultModel,
      availableModels: config.availableModels.isNotEmpty
          ? config.availableModels
          : null,
    );
  }

  @override
  String get healthEndpoint => '$normalizedBaseUrl/health';

  @override
  void addThinkingConfig(
    Map<String, dynamic> requestBody,
    ThinkingConfig thinking,
  ) {
    // vLLM supports reasoning via OpenAI-compatible parameters
    if (thinking.enabled) {
      requestBody['reasoning'] = {
        'enabled': true,
        if (thinking.budgetTokens != null)
          'budget_tokens': thinking.budgetTokens,
      };
    }
  }

  static ProviderConfig createConfig({
    String? baseUrl,
    String? defaultModel,
    List<String>? availableModels,
    bool isCustom = false,
  }) {
    return ProviderConfig(
      id: providerId,
      displayName: displayNameValue,
      type: 'vllm',
      baseUrl: baseUrl ?? defaultBaseUrl,
      defaultModel: defaultModel ?? defaultModelValue,
      availableModels: availableModels ?? const [],
      isCustom: isCustom,
      supportsThinking: true,
      supportsAdaptiveThinking: false,
    );
  }
}
