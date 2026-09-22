enum MessageRole {
  user,
  assistant,
  system,
  tool,
}

enum ToolCallStatus {
  running,
  success,
  error,
  awaitingConfirmation,
}

class ToolCallInfo {
  final String callId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? thoughtSignature;
  final Map<String, dynamic>? rawPart;
  final ToolCallStatus status;
  final String? result;
  final String? summary;
  final String? errorMessage;

  const ToolCallInfo({
    required this.callId,
    required this.toolName,
    required this.arguments,
    this.thoughtSignature,
    this.rawPart,
    this.status = ToolCallStatus.running,
    this.result,
    this.summary,
    this.errorMessage,
  });

  ToolCallInfo copyWith({
    String? callId,
    String? toolName,
    Map<String, dynamic>? arguments,
    String? thoughtSignature,
    Map<String, dynamic>? rawPart,
    ToolCallStatus? status,
    String? result,
    String? summary,
    String? errorMessage,
  }) {
    return ToolCallInfo(
      callId: callId ?? this.callId,
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      thoughtSignature: thoughtSignature ?? this.thoughtSignature,
      rawPart: rawPart ?? this.rawPart,
      status: status ?? this.status,
      result: result ?? this.result,
      summary: summary ?? this.summary,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
    'callId': callId,
    'toolName': toolName,
    'arguments': arguments,
    'status': status.name,
    if (thoughtSignature != null) 'thoughtSignature': thoughtSignature,
    if (rawPart != null) 'rawPart': rawPart,
    if (result != null) 'result': result,
    if (summary != null) 'summary': summary,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };

  factory ToolCallInfo.fromJson(Map<String, dynamic> json) => ToolCallInfo(
    callId: json['callId'] as String? ?? '',
    toolName: json['toolName'] as String? ?? '',
    arguments: (json['arguments'] as Map<String, dynamic>?) ?? {},
    status: ToolCallStatus.values.firstWhere(
      (s) => s.name == (json['status'] as String?),
      orElse: () => ToolCallStatus.running,
    ),
    thoughtSignature: json['thoughtSignature'] as String?,
    rawPart: json['rawPart'] as Map<String, dynamic>?,
    result: json['result'] as String?,
    summary: json['summary'] as String?,
    errorMessage: json['errorMessage'] as String?,
  );
}

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ToolCallInfo>? toolCalls;
  final String? toolCallId; // Used when role == MessageRole.tool
  final bool isStreaming;
  final String? statusBadge; // e.g. "🔍 يبحث في الويب...", "⏰ يجدول..."
  final String? thinkingContent; // محتوى التفكير الموسَّع (Extended Thinking) إن وُجد

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCalls,
    this.toolCallId,
    this.isStreaming = false,
    this.statusBadge,
    this.thinkingContent,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    List<ToolCallInfo>? toolCalls,
    String? toolCallId,
    bool? isStreaming,
    String? statusBadge,
    String? thinkingContent,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      isStreaming: isStreaming ?? this.isStreaming,
      statusBadge: statusBadge ?? this.statusBadge,
      thinkingContent: thinkingContent ?? this.thinkingContent,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'timestamp': timestamp.millisecondsSinceEpoch,
    if (toolCalls != null)
      'toolCalls': toolCalls!.map((t) => t.toJson()).toList(),
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (statusBadge != null) 'statusBadge': statusBadge,
    if (thinkingContent != null) 'thinkingContent': thinkingContent,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    List<ToolCallInfo>? parsedToolCalls;
    if (json['toolCalls'] != null && json['toolCalls'] is List) {
      parsedToolCalls = (json['toolCalls'] as List)
          .map((e) => ToolCallInfo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    final ts = json['timestamp'];
    DateTime parsedTimestamp = DateTime.now();
    if (ts is int) {
      parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      parsedTimestamp = DateTime.tryParse(ts) ?? DateTime.now();
    }

    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: MessageRole.values.firstWhere(
        (r) => r.name == (json['role'] as String?),
        orElse: () => MessageRole.assistant,
      ),
      content: json['content'] as String? ?? '',
      timestamp: parsedTimestamp,
      toolCalls: parsedToolCalls,
      toolCallId: json['toolCallId'] as String?,
      isStreaming: false,
      statusBadge: json['statusBadge'] as String?,
      thinkingContent: json['thinkingContent'] as String?,
    );
  }
}
