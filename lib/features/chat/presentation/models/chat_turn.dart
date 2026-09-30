import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/models/file_attachment_info.dart';
import 'package:khwarizmi/features/chat/presentation/utils/tool_presentation_formatter.dart';

/// Represents a single execution step within an assistant turn.
/// Each step corresponds to a cycle of thinking, generating text, and executing tools.
class AssistantStep {
  final String? id;
  final String? thinkingContent;
  final String? content;
  final List<ToolCallInfo> toolCalls;
  final List<FileAttachmentInfo> files;
  final bool isStreaming;
  final String? activeStatus;

  const AssistantStep({
    this.id,
    this.thinkingContent,
    this.content,
    this.toolCalls = const [],
    this.files = const [],
    this.isStreaming = false,
    this.activeStatus,
  });

  bool get hasVisibleContent =>
      (thinkingContent != null && thinkingContent!.trim().isNotEmpty) ||
      (content != null && content!.trim().isNotEmpty) ||
      toolCalls.isNotEmpty ||
      files.isNotEmpty ||
      isStreaming;

  AssistantStep copyWith({
    String? id,
    String? thinkingContent,
    String? content,
    List<ToolCallInfo>? toolCalls,
    List<FileAttachmentInfo>? files,
    bool? isStreaming,
    String? activeStatus,
  }) {
    return AssistantStep(
      id: id ?? this.id,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      files: files ?? this.files,
      isStreaming: isStreaming ?? this.isStreaming,
      activeStatus: activeStatus ?? this.activeStatus,
    );
  }
}

class _AssistantStepBuilder {
  final String? id;
  String? thinkingContent;
  String? content;
  Map<String, ToolCallInfo> toolCalls = {};
  bool isStreaming;
  String? activeStatus;

  _AssistantStepBuilder({
    this.id,
    this.thinkingContent,
    this.content,
    this.isStreaming = false,
    this.activeStatus,
  });

  AssistantStep build() {
    // استخراج أي ملفات تم إنشاؤها أو تسليمها في هذه الخطوة
    final extractedFiles = <FileAttachmentInfo>[];
    final seenPaths = <String>{};

    for (final call in toolCalls.values) {
      final info = FileAttachmentInfo.fromToolCall(call);
      if (info != null && !seenPaths.contains(info.path)) {
        seenPaths.add(info.path);
        extractedFiles.add(info);
      }
    }

    return AssistantStep(
      id: id,
      thinkingContent: thinkingContent,
      content: content,
      toolCalls: toolCalls.values.toList(),
      files: extractedFiles,
      isStreaming: isStreaming,
      activeStatus: activeStatus,
    );
  }
}

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

    List<_AssistantStepBuilder> currentStepBuilders = [];
    String? turnId;
    DateTime? turnTimestamp;
    bool turnIsStreaming = false;

    void flushAssistant() {
      if (turnId != null || currentStepBuilders.isNotEmpty || turnIsStreaming) {
        final steps = currentStepBuilders
            .map((b) => b.build())
            .where((s) => s.hasVisibleContent)
            .toList();

        if (steps.isNotEmpty || turnIsStreaming) {
          turns.add(AssistantTurn(
            id: turnId ?? 'turn_${DateTime.now().millisecondsSinceEpoch}',
            steps: steps.isNotEmpty
                ? steps
                : [
                    AssistantStep(
                      isStreaming: turnIsStreaming,
                      activeStatus: activeStatus,
                    ),
                  ],
            isStreaming: turnIsStreaming,
            activeStatus: turnIsStreaming ? activeStatus : null,
            timestamp: turnTimestamp ?? DateTime.now(),
          ));
        }
        currentStepBuilders = [];
        turnId = null;
        turnTimestamp = null;
        turnIsStreaming = false;
      }
    }

    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];

      if (msg.role == MessageRole.user) {
        flushAssistant();
        turns.add(UserTurn(msg));
      } else if (msg.role == MessageRole.system) {
        flushAssistant();
        turns.add(SystemTurn(msg));
      } else if (msg.role == MessageRole.assistant) {
        turnId ??= msg.id;
        turnTimestamp ??= msg.timestamp;
        if (msg.isStreaming) {
          turnIsStreaming = true;
        }

        final builder = _AssistantStepBuilder(
          id: msg.id,
          thinkingContent: msg.thinkingContent,
          content: msg.content.trim(),
          isStreaming: msg.isStreaming,
          activeStatus: msg.statusBadge,
        );

        if (msg.toolCalls != null) {
          for (final call in msg.toolCalls!) {
            builder.toolCalls[call.callId] = call;
          }
        }
        currentStepBuilders.add(builder);
      } else if (msg.role == MessageRole.tool) {
        final callId = msg.toolCallId;
        if (callId != null) {
          for (final builder in currentStepBuilders.reversed) {
            if (builder.toolCalls.containsKey(callId)) {
              final existing = builder.toolCalls[callId]!;
              final isBlocked = msg.content.contains('"isBlocked":true');
              final isError = msg.content.contains('"error"');

              final status = isBlocked
                  ? ToolCallStatus.awaitingConfirmation
                  : (isError ? ToolCallStatus.error : ToolCallStatus.success);

              builder.toolCalls[callId] = existing.copyWith(
                result: msg.content,
                status: status,
                summary: ToolPresentationFormatter.getFriendlySummary(
                  existing.toolName,
                  msg.content,
                  arguments: existing.arguments,
                ),
              );
              break;
            }
          }
        }
      }
    }

    if (isStreaming) {
      turnIsStreaming = true;
      if (currentStepBuilders.isNotEmpty) {
        currentStepBuilders.last.isStreaming = true;
        currentStepBuilders.last.activeStatus ??= activeStatus;
      }
    }

    flushAssistant();

    return turns;
  }
}

class UserTurn extends ChatTurn {
  final ChatMessage message;
  const UserTurn(this.message);
}

class SystemTurn extends ChatTurn {
  final ChatMessage message;
  const SystemTurn(this.message);
}

class AssistantTurn extends ChatTurn {
  final String id;
  final List<AssistantStep> steps;
  final bool isStreaming;
  final String? activeStatus;
  final DateTime timestamp;

  const AssistantTurn({
    required this.id,
    required this.steps,
    required this.isStreaming,
    this.activeStatus,
    required this.timestamp,
  });

  /// Backward-compatible getters
  List<String> get textSegments => steps
      .map((s) => s.content)
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toList();

  List<ToolCallInfo> get toolCalls =>
      steps.expand((s) => s.toolCalls).toList();

  List<FileAttachmentInfo> get files =>
      steps.expand((s) => s.files).toList();

  String? get thinkingContent => steps
      .map((s) => s.thinkingContent)
      .whereType<String>()
      .lastWhere((s) => s.isNotEmpty, orElse: () => '');
}
