import 'chat_message.dart';

abstract class AgentEvent {
  const AgentEvent();
}

class AgentTextChunk extends AgentEvent {
  final String text;
  const AgentTextChunk(this.text);
}

class AgentToolCallEvent extends AgentEvent {
  final ToolCallInfo toolCall;
  const AgentToolCallEvent(this.toolCall);
}

class AgentStatusEvent extends AgentEvent {
  final String status;
  const AgentStatusEvent(this.status);
}

class AgentErrorEvent extends AgentEvent {
  final String message;
  final String? code;
  const AgentErrorEvent(this.message, {this.code});
}

class AgentDoneEvent extends AgentEvent {
  const AgentDoneEvent();
}

/// حدث يحمل مقطعًا من نص التفكير الداخلي للنموذج (Extended Thinking).
/// يُبعَث من مزوّدين يدعمون التفكير الموسَّع (Gemini, Claude).
/// يُعرض للمستخدم في قسم "عملية التفكير" القابل للطي.
class AgentThinkingChunkEvent extends AgentEvent {
  final String text;
  const AgentThinkingChunkEvent(this.text);
}

/// حدث يُصدَر عند انقطاع الاتصال بالـ API وبدء إعادة المحاولة التلقائية.
/// يُعرض للمستخدم في واجهة الشات ليعرف أن خوارزمي يعيد الاتصال.
class AgentRetryEvent extends AgentEvent {
  /// رقم المحاولة الحالية (يبدأ من 1)
  final int attempt;

  /// الحد الأقصى لعدد المحاولات
  final int maxAttempts;

  /// مدة الانتظار قبل إعادة المحاولة
  final Duration delay;

  /// سبب الانقطاع (مختصر وإنساني)
  final String reason;

  const AgentRetryEvent({
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
    required this.reason,
  });
}
