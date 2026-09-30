import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/data/retry_utils.dart';
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

    final result = await RetryUtils.executeWithRetry(
      operation: () async {
        final httpClient = client ?? http.Client();
        try {
          final url = Uri.parse('https://api.anthropic.com/v1/models');
          final response = await httpClient
              .get(
                url,
                headers: {
                  'x-api-key': apiKey.trim(),
                  'anthropic-version': '2023-06-01',
                },
              )
              .timeout(const Duration(seconds: 8));

          if (response.statusCode != 200) {
            throw Exception('HTTP_${response.statusCode}');
          }

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

          return availableModels;
        } finally {
          if (client == null) {
            httpClient.close();
          }
        }
      },
      config: RetryConfig.modelFetch,
      onRetry: (attempt, error) {
        debugPrint(
          '[ClaudeProvider] fetchModels retry attempt $attempt: $error',
        );
      },
    );

    if (result.succeeded) {
      return result.data!;
    } else {
      debugPrint(
        '[ClaudeProvider] fetchModels failed after ${result.attempts} attempts: ${result.error}',
      );
      return availableModels;
    }
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
    final correlationId = DateTime.now().microsecondsSinceEpoch.toString();
    final log = Logger.instance;

    if (apiKey.trim().isEmpty) {
      log.warn(
        'ClaudeProvider.sendMessage',
        'Missing API key',
        correlationId: correlationId,
        provider: 'claude',
        model: defaultModel,
      );
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
        messages.add({'role': 'user', 'content': msg.content});
      } else if (msg.role == MessageRole.assistant) {
        final contentBlocks = <Map<String, dynamic>>[];
        if (msg.content.isNotEmpty) {
          contentBlocks.add({'type': 'text', 'text': msg.content});
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

        // تخطي رسائل المساعد الفارغة تمامًا — Claude يرفض إرسال محتوى فارغ
        // ويسبب خطأ "model output must contain either output text or tool calls"
        if (contentBlocks.isEmpty) continue;

        messages.add({'role': 'assistant', 'content': contentBlocks});
      } else if (msg.role == MessageRole.tool) {
        // In Anthropic Messages API, tool results are passed as role 'user' with 'tool_result' block
        messages.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': msg.toolCallId ?? 'toolu_default',
              'content': msg.content,
            },
          ],
        });
      }
    }

    final isThinkingEnabled = thinking != null && thinking.enabled;

    // Calculate maxTokens for both fixed and adaptive modes
    int maxTokens = 4096;
    var thinkingMode = 'none';
    var thinkingBudget = 0;
    if (isThinkingEnabled) {
      if (thinking.mode == ThinkingMode.fixedBudget) {
        maxTokens = (thinking.budgetTokens! + 4096).clamp(16000, 64000);
        thinkingMode = 'fixed';
        thinkingBudget = thinking.budgetTokens ?? 0;
      } else {
        // Adaptive mode: use a generous max tokens budget
        maxTokens = 64000;
        thinkingMode = 'adaptive';
        thinkingBudget = -1;
      }
    }

    final requestBody = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': messages,
      'stream': true,
    };

    if (isThinkingEnabled) {
      if (thinking.mode == ThinkingMode.adaptive) {
        requestBody['thinking'] = {'type': 'adaptive'};
        // Add output_config with effort level for adaptive thinking
        if (thinking.effortLevel != null) {
          requestBody['output_config'] = {'effort': thinking.effortLevel};
        }
      } else {
        requestBody['thinking'] = {
          'type': 'enabled',
          'budget_tokens': thinking.budgetTokens,
        };
      }
    }

    if (systemPrompt.trim().isNotEmpty) {
      requestBody['system'] = systemPrompt;
    }

    var toolsCount = 0;
    if (availableTools.isNotEmpty) {
      toolsCount = availableTools.length;
      requestBody['tools'] = availableTools
          .map((t) => t.toClaudeSchema())
          .toList();
    }

    // Log request start
    log.info(
      'ClaudeProvider.sendMessage',
      'Request started',
      correlationId: correlationId,
      provider: 'claude',
      model: model,
      meta: {
        'historyLength': history.length,
        'toolsCount': toolsCount,
        'thinkingMode': thinkingMode,
        'thinkingBudget': thinkingBudget,
        'maxTokens': maxTokens,
        'systemPromptLength': systemPrompt.length,
        'url': url.toString(),
      },
    );

    log.debug(
      'ClaudeProvider.sendMessage',
      'Request body',
      correlationId: correlationId,
      provider: 'claude',
      model: model,
      meta: {'requestBody': requestBody},
    );

    // Use retry logic for the stream connection
    await for (final event in RetryUtils.executeStreamWithRetry(
      streamFactory: () async* {
        final httpClient = client ?? http.Client();
        http.StreamedResponse? streamedResponse;

        try {
          final request = http.Request('POST', url)
            ..headers['Content-Type'] = 'application/json'
            ..headers['x-api-key'] = apiKey.trim()
            ..headers['anthropic-version'] = '2023-06-01'
            ..body = jsonEncode(requestBody);

          log.debug(
            'ClaudeProvider.sendMessage',
            'HTTP request sent',
            correlationId: correlationId,
            provider: 'claude',
            model: model,
            meta: {'url': url.toString()},
          );

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

            log.error(
              'ClaudeProvider.sendMessage',
              'HTTP error ${streamedResponse.statusCode}',
              correlationId: correlationId,
              provider: 'claude',
              model: model,
              meta: {
                'statusCode': streamedResponse.statusCode,
                'error': errorString,
              },
            );

            throw Exception(
              'HTTP_${streamedResponse.statusCode}: $errorMessage',
            );
          }

          log.info(
            'ClaudeProvider.sendMessage',
            'Stream connected, reading SSE',
            correlationId: correlationId,
            provider: 'claude',
            model: model,
          );

          String buffer = '';
          String currentEventType = '';
          Map<int, Map<String, dynamic>> activeToolCalls = {};
          int eventCount = 0;

          await for (final chunk in streamedResponse.stream.transform(
            utf8.decoder,
          )) {
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
                    final block =
                        data['content_block'] as Map<String, dynamic>?;
                    if (block != null && block['type'] == 'tool_use') {
                      activeToolCalls[index] = {
                        'id':
                            block['id'] as String? ??
                            'toolu_${DateTime.now().millisecondsSinceEpoch}',
                        'name': block['name'] as String? ?? '',
                        'partial_json': '',
                      };
                      log.trace(
                        'ClaudeProvider.sendMessage',
                        'Tool use block started',
                        correlationId: correlationId,
                        provider: 'claude',
                        model: model,
                        meta: {
                          'index': index,
                          'toolName': block['name'],
                          'toolId': block['id'],
                        },
                      );
                    }
                  } else if (currentEventType == 'content_block_delta') {
                    final index = data['index'] as int? ?? 0;
                    final delta = data['delta'] as Map<String, dynamic>?;

                    if (delta != null) {
                      if (delta['type'] == 'text_delta') {
                        final text = delta['text'] as String? ?? '';
                        if (text.isNotEmpty) {
                          eventCount++;
                          log.trace(
                            'ClaudeProvider.sendMessage',
                            'Yield TextChunk',
                            correlationId: correlationId,
                            provider: 'claude',
                            model: model,
                            meta: {
                              'eventNumber': eventCount,
                              'length': text.length,
                            },
                          );
                          yield AgentTextChunk(text);
                        }
                      } else if (delta['type'] == 'thinking_delta') {
                        final text = delta['thinking'] as String? ?? '';
                        if (text.isNotEmpty) {
                          eventCount++;
                          log.trace(
                            'ClaudeProvider.sendMessage',
                            'Yield ThinkingChunk',
                            correlationId: correlationId,
                            provider: 'claude',
                            model: model,
                            meta: {
                              'eventNumber': eventCount,
                              'length': text.length,
                            },
                          );
                          yield AgentThinkingChunkEvent(text);
                        }
                      } else if (delta['type'] == 'input_json_delta') {
                        final partial = delta['partial_json'] as String? ?? '';
                        if (activeToolCalls.containsKey(index)) {
                          activeToolCalls[index]!['partial_json'] =
                              (activeToolCalls[index]!['partial_json']
                                  as String) +
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
                          parsedArgs =
                              jsonDecode(rawJson) as Map<String, dynamic>;
                        } catch (_) {
                          parsedArgs = {'raw': rawJson};
                        }
                      }

                      eventCount++;
                      log.info(
                        'ClaudeProvider.sendMessage',
                        'Yield ToolCall',
                        correlationId: correlationId,
                        provider: 'claude',
                        model: model,
                        meta: {
                          'eventNumber': eventCount,
                          'toolName': toolName,
                          'callId': callInfo['id'],
                          'arguments': parsedArgs,
                        },
                      );

                      yield AgentToolCallEvent(
                        ToolCallInfo(
                          callId: callInfo['id'] as String,
                          toolName: toolName,
                          arguments: parsedArgs,
                        ),
                      );
                    }
                  } else if (currentEventType == 'message_stop') {
                    log.info(
                      'ClaudeProvider.sendMessage',
                      'Message stop, yielding DoneEvent',
                      correlationId: correlationId,
                      provider: 'claude',
                      model: model,
                      meta: {'totalEventsYielded': eventCount},
                    );
                    yield const AgentDoneEvent();
                  } else if (currentEventType == 'error') {
                    final errorMsg =
                        data['error']?['message'] as String? ??
                        'خطأ من مزوّد Claude';
                    log.error(
                      'ClaudeProvider.sendMessage',
                      'API error: $errorMsg',
                      correlationId: correlationId,
                      provider: 'claude',
                      model: model,
                    );
                    yield AgentErrorEvent('تعذر الاتصال بـ Claude: $errorMsg');
                  }
                } catch (e) {
                  log.error(
                    'ClaudeProvider.sendMessage',
                    'SSE parse error: $e',
                    correlationId: correlationId,
                    provider: 'claude',
                    model: model,
                    meta: {'rawData': dataJsonStr},
                  );
                }
              }
            }
          }

          yield const AgentDoneEvent();
        } catch (e, stack) {
          log.error(
            'ClaudeProvider.sendMessage',
            'Stream factory error: $e',
            correlationId: correlationId,
            provider: 'claude',
            model: model,
            stackTrace: stack,
          );
          rethrow;
        } finally {
          if (client == null) {
            httpClient.close();
          }
        }
      },
      config: RetryConfig.apiStream,
      onRetry: (attempt, error) {
        log.warn(
          'ClaudeProvider.sendMessage',
          'Retry attempt $attempt: $error',
          correlationId: correlationId,
          provider: 'claude',
          model: model,
          meta: {'attempt': attempt},
        );
        debugPrint(
          '[ClaudeProvider] sendMessage retry attempt $attempt: $error',
        );
      },
    )) {
      // Log every event yielded to the caller
      if (event is AgentTextChunk) {
        log.trace(
          'ClaudeProvider.sendMessage',
          'Forward TextChunk',
          correlationId: correlationId,
          provider: 'claude',
          model: model,
          meta: {'length': event.text.length},
        );
      } else if (event is AgentThinkingChunkEvent) {
        log.trace(
          'ClaudeProvider.sendMessage',
          'Forward ThinkingChunk',
          correlationId: correlationId,
          provider: 'claude',
          model: model,
          meta: {'length': event.text.length},
        );
      } else if (event is AgentToolCallEvent) {
        log.info(
          'ClaudeProvider.sendMessage',
          'Forward ToolCall',
          correlationId: correlationId,
          provider: 'claude',
          model: model,
          meta: {
            'toolName': event.toolCall.toolName,
            'callId': event.toolCall.callId,
            'arguments': event.toolCall.arguments,
          },
        );
      } else if (event is AgentRetryEvent) {
        log.warn(
          'ClaudeProvider.sendMessage',
          'Forward RetryEvent',
          correlationId: correlationId,
          provider: 'claude',
          model: model,
          meta: {'attempt': event.attempt, 'reason': event.reason},
        );
      } else if (event is AgentErrorEvent) {
        log.error(
          'ClaudeProvider.sendMessage',
          'Forward ErrorEvent',
          correlationId: correlationId,
          provider: 'claude',
          model: model,
          meta: {'message': event.message, 'code': event.code},
        );
      } else if (event is AgentDoneEvent) {
        log.info(
          'ClaudeProvider.sendMessage',
          'Forward DoneEvent',
          correlationId: correlationId,
          provider: 'claude',
          model: model,
        );
      }
      yield event;
    }
  }
}
