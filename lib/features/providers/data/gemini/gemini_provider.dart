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

class GeminiProvider implements AiProvider {
  @override
  String get id => 'gemini';

  @override
  String get displayName => 'Google Gemini';

  // Fallback static list — used if API listing fails
  @override
  List<String> get availableModels => const [
    'gemini-3.8-flash',
    'gemini-3.7-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-pro-preview',
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-2.5-flash-lite',
  ];

  @override
  String get defaultModel => 'gemini-3.8-flash';

  /// Queries the Gemini API dynamically and returns the real list of model IDs
  /// that support generateContent, sorted with the newest first.
  static Future<List<String>> fetchAvailableModels(String apiKey) async {
    if (apiKey.trim().isEmpty) return const ['gemini-3.8-flash'];

    final result = await RetryUtils.executeWithRetry(
      operation: () async {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey.trim()}&pageSize=50',
        );
        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw Exception('HTTP_${response.statusCode}');
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final models = (json['models'] as List<dynamic>? ?? []);

        final ids = <String>[];
        for (final m in models) {
          final name = m['name'] as String? ?? '';
          final methods =
              (m['supportedGenerationMethods'] as List<dynamic>? ?? []);
          if (methods.contains('generateContent')) {
            // name format: "models/gemini-3.8-flash" → extract the ID
            ids.add(name.replaceFirst('models/', ''));
          }
        }

        // Sort: gemini-3.x first, then 2.5, then others
        ids.sort((a, b) {
          final av = _modelSortKey(a);
          final bv = _modelSortKey(b);
          return bv.compareTo(av); // descending (newest first)
        });

        return ids.isEmpty ? _fallbackModels : ids;
      },
      config: RetryConfig.modelFetch,
      onRetry: (attempt, error) {
        debugPrint(
          '[GeminiProvider] fetchModels retry attempt $attempt: $error',
        );
      },
    );

    if (result.succeeded) {
      return result.data!;
    } else {
      debugPrint(
        'fetchAvailableModels failed after ${result.attempts} attempts: ${result.error}',
      );
      return _fallbackModels;
    }
  }

  static double _modelSortKey(String id) {
    final match = RegExp(r'gemini-(\d+)\.(\d+)').firstMatch(id);
    if (match != null) {
      return double.tryParse('${match.group(1)}.${match.group(2)}') ?? 0;
    }
    return 0;
  }

  static const List<String> _fallbackModels = [
    'gemini-3.8-flash',
    'gemini-3.7-flash',
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-2.5-flash-lite',
  ];

  @override
  Future<List<String>> fetchModels(String apiKey) {
    return fetchAvailableModels(apiKey);
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
        'GeminiProvider.sendMessage',
        'Missing API key',
        correlationId: correlationId,
        provider: 'gemini',
        model: defaultModel,
      );
      yield const AgentErrorEvent(
        'مفتاح Gemini API غير محدد. يرجى إدخال مفتاح API من شاشة الإعدادات.',
        code: 'MISSING_API_KEY',
      );
      return;
    }

    final model = (modelName != null && modelName.isNotEmpty)
        ? modelName
        : defaultModel;
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse&key=${apiKey.trim()}',
    );

    // Build Gemini contents payload
    final contents = _buildGeminiContents(history);

    final requestBody = <String, dynamic>{'contents': contents};

    // Add thinking configuration if enabled
    var thinkingMode = 'none';
    var thinkingBudget = 0;
    if (thinking != null && thinking.enabled) {
      thinkingMode = thinking.mode == ThinkingMode.adaptive
          ? 'adaptive'
          : 'fixed';
      thinkingBudget = thinking.mode == ThinkingMode.adaptive
          ? -1
          : (thinking.budgetTokens ?? 0);
      final thinkingConfig = <String, dynamic>{};
      if (thinking.mode == ThinkingMode.adaptive) {
        thinkingConfig['thinkingBudget'] = -1;
      } else {
        thinkingConfig['thinkingBudget'] = thinking.budgetTokens ?? 0;
      }
      requestBody['generationConfig'] = {'thinkingConfig': thinkingConfig};
    }

    // Add system instruction
    if (systemPrompt.trim().isNotEmpty) {
      requestBody['system_instruction'] = {
        'parts': [
          {'text': systemPrompt},
        ],
      };
    }

    // Add tools if present
    var toolsCount = 0;
    if (availableTools.isNotEmpty) {
      toolsCount = availableTools.length;
      requestBody['tools'] = [
        {
          'function_declarations': availableTools
              .map((t) => t.toGeminiSchema())
              .toList(),
        },
      ];
    }

    // Log request start
    log.info(
      'GeminiProvider.sendMessage',
      'Request started',
      correlationId: correlationId,
      provider: 'gemini',
      model: model,
      meta: {
        'historyLength': history.length,
        'toolsCount': toolsCount,
        'thinkingMode': thinkingMode,
        'thinkingBudget': thinkingBudget,
        'systemPromptLength': systemPrompt.length,
        'url': url.toString(),
      },
    );

    log.debug(
      'GeminiProvider.sendMessage',
      'Request body',
      correlationId: correlationId,
      provider: 'gemini',
      model: model,
      meta: {'requestBody': requestBody},
    );

    // Use retry logic for the stream connection — yields AgentRetryEvent on transient failures
    await for (final event in RetryUtils.executeStreamWithRetry(
      streamFactory: () async* {
        final client = http.Client();
        http.StreamedResponse? streamedResponse;

        try {
          final request = http.Request('POST', url)
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode(requestBody);

          log.debug(
            'GeminiProvider.sendMessage',
            'HTTP request sent',
            correlationId: correlationId,
            provider: 'gemini',
            model: model,
            meta: {'url': url.toString()},
          );

          streamedResponse = await client.send(request);

          if (streamedResponse.statusCode != 200) {
            final errorBytes = await streamedResponse.stream.toBytes();
            final errorString = utf8.decode(errorBytes);
            String errorMessage = 'حدث خطأ في الاتصال بمزوّد Gemini ($model)';
            try {
              final errorJson = jsonDecode(errorString);
              if (errorJson['error']?['message'] != null) {
                errorMessage = errorJson['error']['message'];
              }
            } catch (_) {}

            log.error(
              'GeminiProvider.sendMessage',
              'HTTP error ${streamedResponse.statusCode}',
              correlationId: correlationId,
              provider: 'gemini',
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
            'GeminiProvider.sendMessage',
            'Stream connected, reading SSE',
            correlationId: correlationId,
            provider: 'gemini',
            model: model,
          );

          // Stream lines from SSE
          String buffer = '';
          int eventCount = 0;
          await for (final chunk in streamedResponse.stream.transform(
            utf8.decoder,
          )) {
            buffer += chunk;
            final lines = buffer.split('\n');
            buffer = lines.removeLast(); // Keep incomplete line

            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || trimmed.startsWith(':')) continue;

              if (trimmed.startsWith('data:')) {
                final dataJsonStr = trimmed.substring(5).trim();
                if (dataJsonStr == '[DONE]') {
                  log.debug(
                    'GeminiProvider.sendMessage',
                    'Received [DONE]',
                    correlationId: correlationId,
                    provider: 'gemini',
                    model: model,
                  );
                  continue;
                }

                try {
                  final data = jsonDecode(dataJsonStr) as Map<String, dynamic>;
                  final candidates = data['candidates'] as List<dynamic>?;
                  if (candidates != null && candidates.isNotEmpty) {
                    final candidate = candidates.first as Map<String, dynamic>;
                    final content =
                        candidate['content'] as Map<String, dynamic>?;
                    final parts = content?['parts'] as List<dynamic>?;

                    if (parts != null) {
                      for (final part in parts) {
                        if (part is Map<String, dynamic>) {
                          // Check for thought/reasoning part
                          final isThought =
                              part['thought'] == true ||
                              (part.containsKey('thought') &&
                                  part['thought'] is String);
                          if (isThought) {
                            final thoughtText = part['thought'] is String
                                ? part['thought'] as String
                                : (part['text'] as String? ?? '');
                            if (thoughtText.isNotEmpty) {
                              eventCount++;
                              log.trace(
                                'GeminiProvider.sendMessage',
                                'Yield ThinkingChunk',
                                correlationId: correlationId,
                                provider: 'gemini',
                                model: model,
                                meta: {
                                  'eventNumber': eventCount,
                                  'length': thoughtText.length,
                                },
                              );
                              yield AgentThinkingChunkEvent(thoughtText);
                            }
                          } else if (part.containsKey('text')) {
                            // Regular text piece
                            final text = part['text'] as String?;
                            if (text != null && text.isNotEmpty) {
                              eventCount++;
                              log.trace(
                                'GeminiProvider.sendMessage',
                                'Yield TextChunk',
                                correlationId: correlationId,
                                provider: 'gemini',
                                model: model,
                                meta: {
                                  'eventNumber': eventCount,
                                  'length': text.length,
                                },
                              );
                              yield AgentTextChunk(text);
                            }
                          }

                          // Function call
                          if (part.containsKey('functionCall')) {
                            final fnCall =
                                part['functionCall'] as Map<String, dynamic>;
                            final fnName = fnCall['name'] as String? ?? '';
                            final fnArgs =
                                (fnCall['args'] as Map<String, dynamic>?) ?? {};
                            final callId =
                                'call_${DateTime.now().microsecondsSinceEpoch}_$fnName';

                            final signature =
                                (part['thought_signature'] ??
                                        part['thoughtSignature'] ??
                                        fnCall['thought_signature'] ??
                                        fnCall['thoughtSignature'])
                                    as String?;

                            eventCount++;
                            log.info(
                              'GeminiProvider.sendMessage',
                              'Yield ToolCall',
                              correlationId: correlationId,
                              provider: 'gemini',
                              model: model,
                              meta: {
                                'eventNumber': eventCount,
                                'toolName': fnName,
                                'callId': callId,
                                'arguments': fnArgs,
                                'hasThoughtSignature': signature != null,
                              },
                            );

                            yield AgentToolCallEvent(
                              ToolCallInfo(
                                callId: callId,
                                toolName: fnName,
                                arguments: fnArgs,
                                thoughtSignature: signature,
                                rawPart: Map<String, dynamic>.from(part),
                              ),
                            );
                          }
                        }
                      }
                    }
                  }
                } catch (e) {
                  log.error(
                    'GeminiProvider.sendMessage',
                    'SSE parse error: $e',
                    correlationId: correlationId,
                    provider: 'gemini',
                    model: model,
                    meta: {'rawData': dataJsonStr},
                  );
                }
              }
            }
          }

          log.info(
            'GeminiProvider.sendMessage',
            'Stream ended, yielding DoneEvent',
            correlationId: correlationId,
            provider: 'gemini',
            model: model,
            meta: {'totalEventsYielded': eventCount},
          );
          yield const AgentDoneEvent();
        } catch (e, stack) {
          log.error(
            'GeminiProvider.sendMessage',
            'Stream factory error: $e',
            correlationId: correlationId,
            provider: 'gemini',
            model: model,
            stackTrace: stack,
          );
          rethrow;
        } finally {
          client.close();
        }
      },
      config: RetryConfig.apiStream,
      onRetry: (attempt, error) {
        log.warn(
          'GeminiProvider.sendMessage',
          'Retry attempt $attempt: $error',
          correlationId: correlationId,
          provider: 'gemini',
          model: model,
          meta: {'attempt': attempt},
        );
        debugPrint(
          '[GeminiProvider] sendMessage retry attempt $attempt: $error',
        );
      },
    )) {
      // Log every event yielded to the caller
      if (event is AgentTextChunk) {
        log.trace(
          'GeminiProvider.sendMessage',
          'Forward TextChunk',
          correlationId: correlationId,
          provider: 'gemini',
          model: model,
          meta: {'length': event.text.length},
        );
      } else if (event is AgentThinkingChunkEvent) {
        log.trace(
          'GeminiProvider.sendMessage',
          'Forward ThinkingChunk',
          correlationId: correlationId,
          provider: 'gemini',
          model: model,
          meta: {'length': event.text.length},
        );
      } else if (event is AgentToolCallEvent) {
        log.info(
          'GeminiProvider.sendMessage',
          'Forward ToolCall',
          correlationId: correlationId,
          provider: 'gemini',
          model: model,
          meta: {
            'toolName': event.toolCall.toolName,
            'callId': event.toolCall.callId,
            'arguments': event.toolCall.arguments,
          },
        );
      } else if (event is AgentRetryEvent) {
        log.warn(
          'GeminiProvider.sendMessage',
          'Forward RetryEvent',
          correlationId: correlationId,
          provider: 'gemini',
          model: model,
          meta: {'attempt': event.attempt, 'reason': event.reason},
        );
      } else if (event is AgentErrorEvent) {
        log.error(
          'GeminiProvider.sendMessage',
          'Forward ErrorEvent',
          correlationId: correlationId,
          provider: 'gemini',
          model: model,
          meta: {'message': event.message, 'code': event.code},
        );
      } else if (event is AgentDoneEvent) {
        log.info(
          'GeminiProvider.sendMessage',
          'Forward DoneEvent',
          correlationId: correlationId,
          provider: 'gemini',
          model: model,
        );
      }
      yield event;
    }
  }

  List<Map<String, dynamic>> _buildGeminiContents(List<ChatMessage> history) {
    final contents = <Map<String, dynamic>>[];

    for (final msg in history) {
      if (msg.role == MessageRole.system) {
        continue; // Handled separately in system_instruction
      }

      if (msg.role == MessageRole.user) {
        contents.add({
          'role': 'user',
          'parts': [
            {'text': msg.content},
          ],
        });
      } else if (msg.role == MessageRole.assistant) {
        final parts = <Map<String, dynamic>>[];
        if (msg.content.isNotEmpty) {
          parts.add({'text': msg.content});
        }
        if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
          for (final call in msg.toolCalls!) {
            if (call.rawPart != null) {
              parts.add(call.rawPart!);
            } else {
              final partMap = <String, dynamic>{
                'functionCall': {'name': call.toolName, 'args': call.arguments},
              };
              if (call.thoughtSignature != null) {
                partMap['thought_signature'] = call.thoughtSignature;
              }
              parts.add(partMap);
            }
          }
        }
        if (parts.isNotEmpty) {
          contents.add({'role': 'model', 'parts': parts});
        }
      } else if (msg.role == MessageRole.tool) {
        // Tool execution result
        // Gemini expects role: "user" with "functionResponse" part
        // إصلاح 01: اسم الأداة يُؤخذ صراحةً من حقل toolName المعبأ عند
        // الإنشاء. كان الاسم يُستخرج من toolCallId عبر split('_').last
        // فيتقطّع كل اسم أداة يحوي شرطة سفلية (web_search → search)،
        // وGemini يرفض functionResponse لا يطابق اسم الاستدعاء الأصلي.
        // الاحتياطات للرسائل القديمة المخزنة قبل الحقل: البحث في التاريخ
        // عن callId مطابق، ثم أقل الضرر 'tool_result'.
        String? toolName = msg.toolName?.isNotEmpty == true
            ? msg.toolName
            : null;
        if (toolName == null && msg.toolCallId != null) {
          for (final m in history) {
            if (m.role != MessageRole.assistant) continue;
            final calls = m.toolCalls;
            if (calls == null) continue;
            for (final call in calls) {
              if (call.callId == msg.toolCallId) {
                toolName = call.toolName;
                break;
              }
            }
            if (toolName != null) break;
          }
        }
        toolName ??= 'tool_result';

        Map<String, dynamic> responseData;
        try {
          responseData = jsonDecode(msg.content) as Map<String, dynamic>;
        } catch (_) {
          responseData = {'output': msg.content};
        }

        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {'name': toolName, 'response': responseData},
            },
          ],
        });
      }
    }

    return contents;
  }
}
