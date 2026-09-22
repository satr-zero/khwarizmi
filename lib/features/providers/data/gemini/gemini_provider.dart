import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
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

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey.trim()}&pageSize=50',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return _fallbackModels;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (json['models'] as List<dynamic>? ?? []);

      final ids = <String>[];
      for (final m in models) {
        final name = m['name'] as String? ?? '';
        final methods = (m['supportedGenerationMethods'] as List<dynamic>? ?? []);
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
    } catch (e) {
      debugPrint('fetchAvailableModels error: $e');
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
    if (apiKey.trim().isEmpty) {
      yield const AgentErrorEvent(
        'مفتاح Gemini API غير محدد. يرجى إدخال مفتاح API من شاشة الإعدادات.',
        code: 'MISSING_API_KEY',
      );
      return;
    }

    final model = (modelName != null && modelName.isNotEmpty) ? modelName : defaultModel;
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse&key=${apiKey.trim()}',
    );

    // Build Gemini contents payload
    final contents = _buildGeminiContents(history);

    final requestBody = <String, dynamic>{
      'contents': contents,
    };

    // Add thinking configuration if enabled
    if (thinking != null && thinking.enabled) {
      requestBody['generationConfig'] = {
        'thinkingConfig': {
          'thinkingBudget': thinking.budgetTokens,
        },
      };
    }

    // Add system instruction
    if (systemPrompt.trim().isNotEmpty) {
      requestBody['system_instruction'] = {
        'parts': [
          {'text': systemPrompt}
        ]
      };
    }

    // Add tools if present
    if (availableTools.isNotEmpty) {
      requestBody['tools'] = [
        {
          'function_declarations': availableTools.map((t) => t.toGeminiSchema()).toList(),
        }
      ];
    }

    final client = http.Client();
    http.StreamedResponse? streamedResponse;

    try {
      final request = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(requestBody);

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

        yield AgentErrorEvent(errorMessage, code: 'HTTP_${streamedResponse.statusCode}');
        return;
      }

      // Stream lines from SSE
      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // Keep incomplete line

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith(':')) continue;

          if (trimmed.startsWith('data:')) {
            final dataJsonStr = trimmed.substring(5).trim();
            if (dataJsonStr == '[DONE]') {
              continue;
            }

            try {
              final data = jsonDecode(dataJsonStr) as Map<String, dynamic>;
              final candidates = data['candidates'] as List<dynamic>?;
              if (candidates != null && candidates.isNotEmpty) {
                final candidate = candidates.first as Map<String, dynamic>;
                final content = candidate['content'] as Map<String, dynamic>?;
                final parts = content?['parts'] as List<dynamic>?;

                if (parts != null) {
                  for (final part in parts) {
                    if (part is Map<String, dynamic>) {
                      // Check for thought/reasoning part
                      final isThought = part['thought'] == true ||
                          (part.containsKey('thought') && part['thought'] is String);
                      if (isThought) {
                        final thoughtText = part['thought'] is String
                            ? part['thought'] as String
                            : (part['text'] as String? ?? '');
                        if (thoughtText.isNotEmpty) {
                          yield AgentThinkingChunkEvent(thoughtText);
                        }
                      } else if (part.containsKey('text')) {
                        // Regular text piece
                        final text = part['text'] as String?;
                        if (text != null && text.isNotEmpty) {
                          yield AgentTextChunk(text);
                        }
                      }

                      // Function call
                      if (part.containsKey('functionCall')) {
                        final fnCall = part['functionCall'] as Map<String, dynamic>;
                        final fnName = fnCall['name'] as String? ?? '';
                        final fnArgs = (fnCall['args'] as Map<String, dynamic>?) ?? {};
                        final callId = 'call_${DateTime.now().millisecondsSinceEpoch}_$fnName';

                        final signature = (part['thought_signature'] ??
                                          part['thoughtSignature'] ??
                                          fnCall['thought_signature'] ??
                                          fnCall['thoughtSignature']) as String?;

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
              debugPrint('Error parsing Gemini SSE chunk: $e');
            }
          }
        }
      }

      yield const AgentDoneEvent();
    } catch (e) {
      yield AgentErrorEvent('تعذر الاتصال بـ Gemini: $e', code: 'NETWORK_ERROR');
    } finally {
      client.close();
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
            {'text': msg.content}
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
                'functionCall': {
                  'name': call.toolName,
                  'args': call.arguments,
                }
              };
              if (call.thoughtSignature != null) {
                partMap['thought_signature'] = call.thoughtSignature;
              }
              parts.add(partMap);
            }
          }
        }
        if (parts.isNotEmpty) {
          contents.add({
            'role': 'model',
            'parts': parts,
          });
        }
      } else if (msg.role == MessageRole.tool) {
        // Tool execution result
        // Gemini expects role: "user" with "functionResponse" part
        final toolName = msg.toolCallId != null && msg.toolCallId!.contains('_')
            ? msg.toolCallId!.split('_').last
            : 'tool_result';

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
              'functionResponse': {
                'name': toolName,
                'response': responseData,
              }
            }
          ],
        });
      }
    }

    return contents;
  }
}
