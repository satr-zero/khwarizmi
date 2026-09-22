import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';

/// Generic provider for any OpenAI-compatible API
/// (OpenAI, Groq, DeepSeek, Mistral, Together AI, OpenRouter, Cerebras, Ollama, LM Studio, etc.)
class OpenAiCompatibleProvider implements AiProvider {
  @override
  final String id;

  @override
  final String displayName;

  final String baseUrl;

  @override
  final String defaultModel;

  @override
  final List<String> availableModels;

  /// معاملات إضافية تُدمَج في جسم كل طلب (اختيارية).
  /// مثال: {'reasoning_effort': 'max'} لبعض نماذج NVIDIA
  final Map<String, dynamic> extraBodyParams;

  final http.Client? client;

  OpenAiCompatibleProvider({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.defaultModel,
    this.availableModels = const [],
    this.extraBodyParams = const {},
    this.client,
  });

  /// Fetches the live list of models from the provider's /models endpoint.
  /// Falls back to [availableModels] if the request fails or the provider
  /// doesn't support model listing.
  @override
  Future<List<String>> fetchModels(String apiKey) async {
    if (baseUrl.trim().isEmpty) return availableModels;

    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // Remove trailing /chat/completions if present to get the base
    final apiBase = normalizedBase.endsWith('/chat/completions')
        ? normalizedBase.substring(0, normalizedBase.length - '/chat/completions'.length)
        : normalizedBase;

    final modelsUrl = Uri.tryParse('$apiBase/models');
    if (modelsUrl == null) return availableModels;

    final httpClient = client ?? http.Client();
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      }

      final response = await httpClient
          .get(modelsUrl, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        // Standard OpenAI format: { "data": [ { "id": "...", ... } ] }
        final data = json['data'] as List<dynamic>?;
        if (data != null && data.isNotEmpty) {
          final ids = data
              .map((item) =>
                  (item as Map<String, dynamic>)['id']?.toString())
              .whereType<String>()
              .toList();
          if (ids.isNotEmpty) {
            ids.sort(); // alphabetical for stability
            return ids;
          }
        }

        // Some providers (e.g. Ollama) return { "models": [ { "name": "...", ... } ] }
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

    // Fallback: return static list
    return availableModels;
  }

  @override
  Stream<AgentEvent> sendMessage({
    required List<ChatMessage> history,
    required List<ToolDefinition> availableTools,
    required String systemPrompt,
    required String apiKey,
    String? modelName,
    ThinkingConfig? thinking,
  }) async* {
    if (apiKey.trim().isEmpty) {
      yield AgentErrorEvent(
        'مفتاح API الخاص بـ $displayName غير محدد. يرجى إدخال مفتاح API من شاشة الإعدادات.',
        code: 'MISSING_API_KEY',
      );
      return;
    }

    final model = (modelName != null && modelName.trim().isNotEmpty)
        ? modelName.trim()
        : defaultModel;

    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final endpoint = normalizedBase.endsWith('/chat/completions')
        ? normalizedBase
        : '$normalizedBase/chat/completions';

    final Uri url;
    try {
      url = Uri.parse(endpoint);
    } catch (e) {
      yield AgentErrorEvent(
        'تعذر الاتصال بـ $displayName — عنوان الرابط (Base URL) غير صالح: $endpoint',
        code: 'INVALID_BASE_URL',
      );
      return;
    }

    // Build messages payload
    final messages = <Map<String, dynamic>>[];

    // 1. System prompt
    if (systemPrompt.trim().isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': systemPrompt,
      });
    }

    // 2. Chat history
    for (final msg in history) {
      if (msg.role == MessageRole.user) {
        messages.add({
          'role': 'user',
          'content': msg.content,
        });
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
          messages.add({
            'role': 'assistant',
            'content': msg.content,
          });
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
      'model': model,
      'messages': messages,
      'stream': true,
      // دمج المعاملات الإضافية المخصصة للمزوّد (إن وجدت)
      ...extraBodyParams,
    };

    if (thinking != null && thinking.enabled) {
      if (model.toLowerCase().startsWith('o1') || model.toLowerCase().startsWith('o3')) {
        requestBody['reasoning_effort'] = 'high';
      }
    }

    if (availableTools.isNotEmpty) {
      requestBody['tools'] =
          availableTools.map((t) => t.toOpenAiSchema()).toList();
    }

    final httpClient = client ?? http.Client();
    http.StreamedResponse? streamedResponse;

    try {
      final request = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
        ..body = jsonEncode(requestBody);

      streamedResponse = await httpClient.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBytes = await streamedResponse.stream.toBytes();
        final errorString = utf8.decode(errorBytes);
        String detail = '';
        try {
          final errorJson = jsonDecode(errorString);
          detail = errorJson['error']?['message']?.toString() ?? errorString;
        } catch (_) {
          detail = errorString;
        }

        if (detail.toLowerCase().contains('function') ||
            detail.toLowerCase().contains('tool')) {
          yield AgentErrorEvent(
            'تعذر تنفيذ الطلب بـ $displayName — هذا المزوّد أو النموذج ($model) لا يدعم استدعاء الأدوات (Tools). التفاصيل: $detail',
            code: 'TOOLS_NOT_SUPPORTED',
          );
        } else {
          yield AgentErrorEvent(
            'تعذر الاتصال بـ $displayName — $detail (رمز الاستجابة: ${streamedResponse.statusCode})',
            code: 'HTTP_${streamedResponse.statusCode}',
          );
        }
        return;
      }

      final accumulatedToolCalls = <int, Map<String, dynamic>>{};
      String buffer = '';

      await for (final chunk
          in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // Retain incomplete line

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
              if (delta.containsKey('content') && delta['content'] != null) {
                final text = delta['content'] as String;
                if (text.isNotEmpty) {
                  yield AgentTextChunk(text);
                }
              }

              // 1b. Reasoning / Thinking delta (DeepSeek R1, etc.)
              if (delta.containsKey('reasoning_content') && delta['reasoning_content'] != null) {
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
                      'id': tc['id'] as String? ??
                          'call_${DateTime.now().millisecondsSinceEpoch}_$index',
                      'name': tc['function']?['name'] as String? ?? '',
                      'arguments':
                          tc['function']?['arguments'] as String? ?? '',
                    };
                  } else {
                    if (tc['id'] != null && (tc['id'] as String).isNotEmpty) {
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
              debugPrint('[$displayName] Parse chunk error: $e for $dataStr');
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
    } catch (e) {
      if (e is http.ClientException || e.toString().contains('SocketException')) {
        yield AgentErrorEvent(
          'تعذر الاتصال بـ $displayName — تحقق من اتصال الإنترنت أو صحة الرابط ($baseUrl).',
          code: 'NETWORK_ERROR',
        );
      } else {
        yield AgentErrorEvent(
          'حدث خطأ غير متوقع أثناء الاتصال بـ $displayName: $e',
          code: 'CLIENT_ERROR',
        );
      }
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
