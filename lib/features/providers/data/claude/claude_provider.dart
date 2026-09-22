import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';

/// Anthropic Claude Provider (Messages API)
class ClaudeProvider implements AiProvider {
  @override
  String get id => 'claude';

  @override
  String get displayName => 'Anthropic Claude';

  @override
  String get defaultModel => 'claude-3-7-sonnet-20250219';

  @override
  List<String> get availableModels => const [
        'claude-3-7-sonnet-20250219',
        'claude-3-5-sonnet-20241022',
        'claude-3-5-haiku-20241022',
        'claude-3-opus-20240229',
      ];

  final http.Client? client;

  ClaudeProvider({this.client});

  @override
  Future<List<String>> fetchModels(String apiKey) async {
    if (apiKey.trim().isEmpty) return availableModels;

    final httpClient = client ?? http.Client();
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/models');
      final response = await httpClient.get(
        url,
        headers: {
          'x-api-key': apiKey.trim(),
          'anthropic-version': '2023-06-01',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>?;
        if (data != null && data.isNotEmpty) {
          final modelIds = data
              .map((item) => (item as Map<String, dynamic>)['id'] as String?)
              .whereType<String>()
              .toList();

          if (modelIds.isNotEmpty) {
            return modelIds;
          }
        }
      }
    } catch (e) {
      debugPrint('[ClaudeProvider] Error fetching live models: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }

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
      yield const AgentErrorEvent(
        'مفتاح Claude API غير محدد. يرجى إدخال مفتاح Anthropic API من شاشة الإعدادات.',
        code: 'MISSING_API_KEY',
      );
      return;
    }

    final model = (modelName != null && modelName.trim().isNotEmpty)
        ? modelName.trim()
        : defaultModel;

    final url = Uri.parse('https://api.anthropic.com/v1/messages');

    // Build Anthropic messages payload
    final messages = <Map<String, dynamic>>[];

    for (final msg in history) {
      if (msg.role == MessageRole.user) {
        messages.add({
          'role': 'user',
          'content': msg.content,
        });
      } else if (msg.role == MessageRole.assistant) {
        final contentBlocks = <Map<String, dynamic>>[];
        if (msg.content.isNotEmpty) {
          contentBlocks.add({
            'type': 'text',
            'text': msg.content,
          });
        }
        if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
          for (final tc in msg.toolCalls!) {
            contentBlocks.add({
              'type': 'tool_use',
              'id': tc.callId,
              'name': tc.toolName,
              'input': tc.arguments,
            });
          }
        }

        messages.add({
          'role': 'assistant',
          'content': contentBlocks.isNotEmpty ? contentBlocks : msg.content,
        });
      } else if (msg.role == MessageRole.tool) {
        // In Anthropic Messages API, tool results are passed as role 'user' with 'tool_result' block
        messages.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': msg.toolCallId ?? 'toolu_default',
              'content': msg.content,
            }
          ],
        });
      }
    }

    final isThinkingEnabled = thinking != null && thinking.enabled;
    final maxTokens = isThinkingEnabled
        ? (thinking.budgetTokens + 4096).clamp(16000, 64000)
        : 4096;

    final requestBody = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': messages,
      'stream': true,
    };

    if (isThinkingEnabled) {
      requestBody['thinking'] = {
        'type': 'enabled',
        'budget_tokens': thinking.budgetTokens,
      };
    }

    if (systemPrompt.trim().isNotEmpty) {
      requestBody['system'] = systemPrompt;
    }

    if (availableTools.isNotEmpty) {
      requestBody['tools'] =
          availableTools.map((t) => t.toClaudeSchema()).toList();
    }

    final httpClient = client ?? http.Client();
    http.StreamedResponse? streamedResponse;

    try {
      final request = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..headers['x-api-key'] = apiKey.trim()
        ..headers['anthropic-version'] = '2023-06-01'
        ..body = jsonEncode(requestBody);

      streamedResponse = await httpClient.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBytes = await streamedResponse.stream.toBytes();
        final errorString = utf8.decode(errorBytes);
        String errorMessage = 'تعذر الاتصال بـ Anthropic Claude ($model)';
        try {
          final errorJson = jsonDecode(errorString);
          if (errorJson['error']?['message'] != null) {
            errorMessage =
                'تعذر الاتصال بـ Anthropic Claude — ${errorJson['error']['message']}';
          }
        } catch (_) {}

        yield AgentErrorEvent(errorMessage,
            code: 'HTTP_${streamedResponse.statusCode}');
        return;
      }

      String buffer = '';
      String currentEventType = '';
      Map<int, Map<String, dynamic>> activeToolCalls = {};

      await for (final chunk
          in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          if (trimmed.startsWith('event:')) {
            currentEventType = trimmed.substring(6).trim();
            continue;
          }

          if (trimmed.startsWith('data:')) {
            final dataJsonStr = trimmed.substring(5).trim();
            if (dataJsonStr.isEmpty) continue;

            try {
              final data = jsonDecode(dataJsonStr) as Map<String, dynamic>;

              if (currentEventType == 'content_block_start') {
                final index = data['index'] as int? ?? 0;
                final block = data['content_block'] as Map<String, dynamic>?;
                if (block != null && block['type'] == 'tool_use') {
                  activeToolCalls[index] = {
                    'id': block['id'] as String? ??
                        'toolu_${DateTime.now().millisecondsSinceEpoch}',
                    'name': block['name'] as String? ?? '',
                    'partial_json': '',
                  };
                }
              } else if (currentEventType == 'content_block_delta') {
                final index = data['index'] as int? ?? 0;
                final delta = data['delta'] as Map<String, dynamic>?;

                if (delta != null) {
                  if (delta['type'] == 'text_delta') {
                    final text = delta['text'] as String? ?? '';
                    if (text.isNotEmpty) {
                      yield AgentTextChunk(text);
                    }
                  } else if (delta['type'] == 'thinking_delta') {
                    final text = delta['thinking'] as String? ?? '';
                    if (text.isNotEmpty) {
                      yield AgentThinkingChunkEvent(text);
                    }
                  } else if (delta['type'] == 'input_json_delta') {
                    final partial = delta['partial_json'] as String? ?? '';
                    if (activeToolCalls.containsKey(index)) {
                      activeToolCalls[index]!['partial_json'] =
                          (activeToolCalls[index]!['partial_json'] as String) +
                              partial;
                    }
                  }
                }
              } else if (currentEventType == 'content_block_stop') {
                final index = data['index'] as int? ?? 0;
                if (activeToolCalls.containsKey(index)) {
                  final callInfo = activeToolCalls[index]!;
                  final toolName = callInfo['name'] as String;
                  final rawJson = callInfo['partial_json'] as String;

                  Map<String, dynamic> parsedArgs = {};
                  if (rawJson.trim().isNotEmpty) {
                    try {
                      parsedArgs = jsonDecode(rawJson) as Map<String, dynamic>;
                    } catch (_) {
                      parsedArgs = {'raw': rawJson};
                    }
                  }

                  yield AgentToolCallEvent(
                    ToolCallInfo(
                      callId: callInfo['id'] as String,
                      toolName: toolName,
                      arguments: parsedArgs,
                    ),
                  );
                }
              } else if (currentEventType == 'message_stop') {
                yield const AgentDoneEvent();
              } else if (currentEventType == 'error') {
                final errorMsg = data['error']?['message'] as String? ??
                    'خطأ من مزوّد Claude';
                yield AgentErrorEvent('تعذر الاتصال بـ Claude: $errorMsg');
              }
            } catch (e) {
              debugPrint('[ClaudeProvider] SSE parse error: $e');
            }
          }
        }
      }

      yield const AgentDoneEvent();
    } catch (e) {
      if (e is http.ClientException || e.toString().contains('SocketException')) {
        yield const AgentErrorEvent(
          'تعذر الاتصال بـ Anthropic Claude — تحقق من اتصال الإنترنت.',
          code: 'NETWORK_ERROR',
        );
      } else {
        yield AgentErrorEvent(
          'حدث خطأ غير متوقع أثناء الاتصال بـ Anthropic Claude: $e',
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
