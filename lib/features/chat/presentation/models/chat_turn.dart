import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/utils/tool_presentation_formatter.dart';

/// Represents a high-level conversation turn for presentation purposes.
/// Unifies fragmented assistant and tool responses into a single, cohesive visual unit.
sealed class ChatTurn {
  const ChatTurn();

  /// Groups raw database/provider messages into coherent visual turns.
  static List<ChatTurn> groupMessages(
    List<ChatMessage> messages, {
    bool isStreaming = false,
    String? activeStatus,
  }) {
    final turns = <ChatTurn>[];

    List<String> currentTexts = [];
    Map<String, ToolCallInfo> currentCalls = {};
    String? turnId;
    DateTime? turnTimestamp;
    bool turnIsStreaming = false;
    String? turnThinkingContent;

    void flushAssistant() {
      if (turnId != null || currentTexts.isNotEmpty || currentCalls.isNotEmpty || turnIsStreaming || turnThinkingContent != null) {
        turns.add(AssistantTurn(
          id: turnId ?? 'turn_${DateTime.now().millisecondsSinceEpoch}',
          textSegments: List.from(currentTexts),
          toolCalls: currentCalls.values.toList(),
          isStreaming: turnIsStreaming,
          activeStatus: turnIsStreaming ? activeStatus : null,
          timestamp: turnTimestamp ?? DateTime.now(),
          thinkingContent: turnThinkingContent,
        ));
        currentTexts = [];
        currentCalls = {};
        turnId = null;
        turnTimestamp = null;
        turnIsStreaming = false;
        turnThinkingContent = null;
      }
    }

    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];

      if (msg.role == MessageRole.user) {
        flushAssistant();
        turns.add(UserTurn(msg));
      } else if (msg.role == MessageRole.assistant) {
        turnId ??= msg.id;
        turnTimestamp ??= msg.timestamp;
        if (msg.thinkingContent != null && msg.thinkingContent!.isNotEmpty) {
          turnThinkingContent = msg.thinkingContent;
        }
        if (msg.isStreaming) {
          turnIsStreaming = true;
        }

        final trimmed = msg.content.trim();
        if (trimmed.isNotEmpty) {
          currentTexts.add(trimmed);
        }

        if (msg.toolCalls != null) {
          for (final call in msg.toolCalls!) {
            final existing = currentCalls[call.callId];
            if (existing == null) {
              currentCalls[call.callId] = call;
            } else {
              currentCalls[call.callId] = existing.copyWith(
                status: call.status != ToolCallStatus.running ? call.status : existing.status,
                result: call.result ?? existing.result,
                summary: call.summary ?? existing.summary,
                errorMessage: call.errorMessage ?? existing.errorMessage,
              );
            }
          }
        }
      } else if (msg.role == MessageRole.tool) {
        final callId = msg.toolCallId;
        if (callId != null && currentCalls.containsKey(callId)) {
          final existing = currentCalls[callId]!;
          final isBlocked = msg.content.contains('"isBlocked":true');
          final isError = msg.content.contains('"error"');

          final status = isBlocked
              ? ToolCallStatus.awaitingConfirmation
              : (isError ? ToolCallStatus.error : ToolCallStatus.success);

          currentCalls[callId] = existing.copyWith(
            result: msg.content,
            status: status,
            summary: ToolPresentationFormatter.getFriendlySummary(
              existing.toolName,
              msg.content,
            ),
          );
        }
      }
    }

    if (isStreaming) {
      turnIsStreaming = true;
    }

    flushAssistant();

    return turns;
  }
}

class UserTurn extends ChatTurn {
  final ChatMessage message;
  const UserTurn(this.message);
}

class AssistantTurn extends ChatTurn {
  final String id;
  final List<String> textSegments;
  final List<ToolCallInfo> toolCalls;
  final bool isStreaming;
  final String? activeStatus;
  final DateTime timestamp;
  final String? thinkingContent;

  const AssistantTurn({
    required this.id,
    required this.textSegments,
    required this.toolCalls,
    required this.isStreaming,
    this.activeStatus,
    required this.timestamp,
    this.thinkingContent,
  });
}
