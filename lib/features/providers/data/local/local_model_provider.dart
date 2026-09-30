import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/data/retry_utils.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';

/// Base class for local model providers (Ollama, LM Studio, vLLM)
/// These providers run locally and don't require external API keys
abstract class LocalModelProvider implements AiProvider {
  @override
  final String id;

  @override
  final String displayName;

  final String baseUrl;

  @override
  final String defaultModel;

  @override
  final List<String> availableModels;

  final http.Client? client;

  LocalModelProvider({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.defaultModel,
    this.availableModels = const [],
    this.client,
  });

  /// Normalizes the base URL to ensure it ends correctly
  String get normalizedBaseUrl {
    var url = baseUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    // Remove trailing /v1 if present (we'll add it back)
    if (url.endsWith('/v1')) {
      url = url.substring(0, url.length - 3);
    }
    return url;
  }

  /// The chat completions endpoint
  String get chatEndpoint => '$normalizedBaseUrl/v1/chat/completions';

  /// The models listing endpoint
  String get modelsEndpoint => '$normalizedBaseUrl/v1/models';

  /// Health check endpoint
  String get healthEndpoint => '$normalizedBaseUrl/health';

  /// Checks if the local server is running and healthy
  Future<bool> checkHealth() async {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(Uri.parse(healthEndpoint))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[$displayName] Health check failed: $e');
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Fetches available models from the local server
  @override
  Future<List<String>> fetchModels(String apiKey) async {
    // For local models, apiKey is optional/ignored
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(
            Uri.parse(modelsEndpoint),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        // OpenAI-compatible format: { "data": [ { "id": "..." } ] }
        final data = json['data'] as List<dynamic>?;
        if (data != null && data.isNotEmpty) {
          final ids = data
              .map((item) => (item as Map<String, dynamic>)['id']?.toString())
              .whereType<String>()
              .toList();
          if (ids.isNotEmpty) {
            ids.sort();
            return ids;
          }
        }

        // Ollama format: { "models": [ { "name": "..." } ] }
        final models = json['models'] as List<dynamic>?;
        if (models != null && models.isNotEmpty) {
          final ids = models
              .map((item) {
                final m = item as Map<String, dynamic>;
                return (m['id'] ?? m['name'])?.toString();
              })
              .whereType<String>()
              .toList();
          if (ids.isNotEmpty) {
            ids.sort();
            return ids;
          }
        }
      }
    } catch (e) {
      debugPrint('[$displayName] fetchModels error: $e');
    } finally {
      if (client == null) httpClient.close();
    }

    return availableModels;
  }

  /// Builds the request body for chat completions
  Map<String, dynamic> buildRequestBody({
    required List<ChatMessage> history,
    required List<ToolDefinition> availableTools,
    required String systemPrompt,
    required String modelName,
    ThinkingConfig? thinking,
  }) {
    final messages = <Map<String, dynamic>>[];

    // 1. System prompt
    if (systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    // 2. Chat history
    for (final msg in history) {
      if (msg.role == MessageRole.user) {
        messages.add({'role': 'user', 'content': msg.content});
      } else if (msg.role == MessageRole.assistant) {
        if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'content': msg.content.isEmpty ? null : msg.content,
            'tool_calls': msg.toolCalls!.map((tc) {
              return {
                'id': tc.callId,
                'type': 'function',
                'function': {
                  'name': tc.toolName,
                  'arguments': jsonEncode(tc.arguments),
                },
              };
            }).toList(),
          });
        } else {
          messages.add({'role': 'assistant', 'content': msg.content});
        }
      } else if (msg.role == MessageRole.tool) {
        messages.add({
          'role': 'tool',
          'tool_call_id': msg.toolCallId ?? 'call_default',
          'content': msg.content,
        });
      }
    }

    final requestBody = <String, dynamic>{
      'model': modelName,
      'messages': messages,
      'stream': true,
    };

    // Add thinking/reasoning support if enabled
    if (thinking != null && thinking.enabled) {
      // Local models may support reasoning via different parameters
      // This can be overridden by subclasses
      addThinkingConfig(requestBody, thinking);
    }

    if (availableTools.isNotEmpty) {
      requestBody['tools'] = availableTools
          .map((t) => t.toOpenAiSchema())
          .toList();
    }

    return requestBody;
  }

  /// Override this to add provider-specific thinking configuration
  void addThinkingConfig(
    Map<String, dynamic> requestBody,
    ThinkingConfig thinking,
  ) {
    // Default: no special thinking config for local models
    // Subclasses can override
  }

  /// Sends a message with retry logic optimized for local models
  @override
  Stream<AgentEvent> sendMessage({
    required List<ChatMessage> history,
    required List<ToolDefinition> availableTools,
    required String systemPrompt,
    required String apiKey, // Ignored for local models
    String? modelName,
    ThinkingConfig? thinking,
  }) async* {
    final model = (modelName != null && modelName.trim().isNotEmpty)
        ? modelName.trim()
        : defaultModel;

    final url = Uri.parse(chatEndpoint);

    final requestBody = buildRequestBody(
      history: history,
      availableTools: availableTools,
      systemPrompt: systemPrompt,
      modelName: model,
      thinking: thinking,
    );

    // Use local models retry config (more aggressive)
    await for (final event in RetryUtils.executeStreamWithRetry(
      streamFactory: () async* {
        final httpClient = client ?? http.Client();
        http.StreamedResponse? streamedResponse;

        try {
          final request = http.Request('POST', url)
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode(requestBody);

          // Local models may not need auth, but include if provided
          if (apiKey.trim().isNotEmpty) {
            request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
          }

          streamedResponse = await httpClient.send(request);

          if (streamedResponse.statusCode != 200) {
            final errorBytes = await streamedResponse.stream.toBytes();
            final errorString = utf8.decode(errorBytes);
            String detail = '';
            try {
              final errorJson = jsonDecode(errorString);
              detail =
                  errorJson['error']?['message']?.toString() ?? errorString;
            } catch (_) {
              detail = errorString;
            }

            if (detail.toLowerCase().contains('function') ||
                detail.toLowerCase().contains('tool')) {
              throw Exception('TOOLS_NOT_SUPPORTED: $detail');
            } else {
              throw Exception('HTTP_${streamedResponse.statusCode}: $detail');
            }
          }

          final accumulatedToolCalls = <int, Map<String, dynamic>>{};
          String buffer = '';

          await for (final chunk in streamedResponse.stream.transform(
            utf8.decoder,
          )) {
            buffer += chunk;
            final lines = buffer.split('\n');
            buffer = lines.removeLast();

            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || trimmed.startsWith(':')) continue;

              if (trimmed.startsWith('data:')) {
                final dataStr = trimmed.substring(5).trim();
                if (dataStr == '[DONE]') {
                  continue;
                }

                try {
                  final data = jsonDecode(dataStr) as Map<String, dynamic>;
                  final choices = data['choices'] as List<dynamic>?;
                  if (choices == null || choices.isEmpty) continue;

                  final delta = choices.first['delta'] as Map<String, dynamic>?;
                  if (delta == null) continue;

                  // 1. Text delta
                  if (delta.containsKey('content') &&
                      delta['content'] != null) {
                    final text = delta['content'] as String;
                    if (text.isNotEmpty) {
                      yield AgentTextChunk(text);
                    }
                  }

                  // 1b. Reasoning / Thinking delta
                  if (delta.containsKey('reasoning_content') &&
                      delta['reasoning_content'] != null) {
                    final reasoning = delta['reasoning_content'] as String;
                    if (reasoning.isNotEmpty) {
                      yield AgentThinkingChunkEvent(reasoning);
                    }
                  }

                  // 2. Tool calls delta
                  if (delta.containsKey('tool_calls') &&
                      delta['tool_calls'] != null) {
                    final toolCallsList = delta['tool_calls'] as List<dynamic>;
                    for (final tc in toolCallsList) {
                      final index = tc['index'] as int? ?? 0;
                      if (!accumulatedToolCalls.containsKey(index)) {
                        accumulatedToolCalls[index] = {
                          'id':
                              tc['id'] as String? ??
                              'call_${DateTime.now().millisecondsSinceEpoch}_$index',
                          'name': tc['function']?['name'] as String? ?? '',
                          'arguments':
                              tc['function']?['arguments'] as String? ?? '',
                        };
                      } else {
                        if (tc['id'] != null &&
                            (tc['id'] as String).isNotEmpty) {
                          accumulatedToolCalls[index]!['id'] = tc['id'];
                        }
                        if (tc['function']?['name'] != null) {
                          accumulatedToolCalls[index]!['name'] =
                              (accumulatedToolCalls[index]!['name'] as String) +
                              (tc['function']['name'] as String);
                        }
                        if (tc['function']?['arguments'] != null) {
                          accumulatedToolCalls[index]!['arguments'] =
                              (accumulatedToolCalls[index]!['arguments']
                                  as String) +
                              (tc['function']['arguments'] as String);
                        }
                      }
                    }
                  }
                } catch (e) {
                  debugPrint(
                    '[$displayName] Parse chunk error: $e for $dataStr',
                  );
                }
              }
            }
          }

          // If any tool calls accumulated, yield them
          if (accumulatedToolCalls.isNotEmpty) {
            final sortedIndices = accumulatedToolCalls.keys.toList()..sort();
            for (final idx in sortedIndices) {
              final item = accumulatedToolCalls[idx]!;
              final fnName = item['name'] as String;
              final rawArgs = item['arguments'] as String;
              Map<String, dynamic> parsedArgs = {};
              if (rawArgs.trim().isNotEmpty) {
                try {
                  parsedArgs = jsonDecode(rawArgs) as Map<String, dynamic>;
                } catch (_) {
                  parsedArgs = {'raw_argument': rawArgs};
                }
              }

              yield AgentToolCallEvent(
                ToolCallInfo(
                  callId: item['id'] as String,
                  toolName: fnName,
                  arguments: parsedArgs,
                ),
              );
            }
          }

          yield const AgentDoneEvent();
        } finally {
          if (client == null) {
            httpClient.close();
          }
        }
      },
      config: RetryConfig.localModels,
      onRetry: (attempt, error) {
        debugPrint('[$displayName] sendMessage retry attempt $attempt: $error');
      },
    )) {
      yield event;
    }
  }
}
