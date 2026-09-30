import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_detector.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_guard.dart';

/// توقيت الاعتراض الموحد
enum InterceptionTiming {
  /// الاعتراض أثناء البث (للأدوات التي تُنفذ تدريجياً)
  duringStream,

  /// الاعتراض بعد اكتمال دور المساعد كاملاً (الوضع الافتراضي)
  postAssistantTurn,
}

/// نتيجة عملية الاعتراض الموحد
class InterceptionResult {
  final ExecutionPromiseGuardAction action;
  final int consecutiveCount;
  final bool shouldInjectSystemTurn;
  final bool shouldInjectRecoveryUserMessage;
  final String? debugInfo;

  const InterceptionResult({
    required this.action,
    required this.consecutiveCount,
    required this.shouldInjectSystemTurn,
    required this.shouldInjectRecoveryUserMessage,
    this.debugInfo,
  });

  bool get isIntercepted => action != ExecutionPromiseGuardAction.none;
}

/// نقطة الاعتراض الموحدة — تُستدعى فور انتهاء دور مساعد (نص + أدوات)
/// بغض النظر عن المسار: محادثة حية، مهام مستقلة، استئناف مهام
abstract final class UnifiedInterceptor {
  static const String _debugPrefix = '[UnifiedInterceptor]';
  static const _uuid = Uuid();

  /// نقطة الاعتراض الرئيسية الموحدة
  static InterceptionResult intercept({
    required List<ChatMessage> conversationHistory,
    required ChatMessage assistantMessage,
    required List<ToolCallInfo> toolCalls,
    required int promiseRecoveryAttempt,
    InterceptionTiming timing = InterceptionTiming.postAssistantTurn,
  }) {
    // 1. فحص العداد الحقيقي من التاريخ الكامل (بما في ذلك رسالة المساعد الحالية)
    final messagesWithCurrent = [...conversationHistory, assistantMessage];
    final consecutive = ExecutionPromiseDetector.countConsecutivePromises(
      messagesWithCurrent,
    );

    // 2. تقييم الحارس باستخدام المنطق المركزي
    final action = ExecutionPromiseGuard.evaluate(
      messages: conversationHistory,
      assistantMsgId: assistantMessage.id,
      assistantContent: assistantMessage.content,
      toolCalls: toolCalls,
      promiseRecoveryAttempt: promiseRecoveryAttempt,
    );

    final result = InterceptionResult(
      action: action,
      consecutiveCount: consecutive,
      shouldInjectSystemTurn: action != ExecutionPromiseGuardAction.none,
      shouldInjectRecoveryUserMessage:
          action == ExecutionPromiseGuardAction.interceptAndRecover,
      debugInfo:
          '$_debugPrefix consecutive=$consecutive '
          'action=$action recoveryAttempt=$promiseRecoveryAttempt '
          'hasTools=${toolCalls.isNotEmpty} timing=$timing',
    );

    // Log للتشخيص الحي
    if (result.isIntercepted) {
      debugPrint(result.debugInfo);
    }

    return result;
  }

  /// يبني رسالة SystemTurn للتنبيه
  static ChatMessage buildSystemAlertMessage(String id) {
    return ExecutionPromiseGuard.buildSystemAlertMessage(id);
  }

  /// يبني رسالة مستخدم استرداد لإعادة التوجيه للتنفيذ العملي
  static ChatMessage buildRecoveryUserMessage(String id) {
    return ExecutionPromiseGuard.buildRecoveryUserMessage(id);
  }

  /// يطبق الاعتراض على حالة المحادثة (يحقن SystemTurn + Recovery message اختيارياً)
  /// يرجع القائمة المحدثة من الرسائل
  static List<ChatMessage> applyInterception({
    required List<ChatMessage> currentMessages,
    required InterceptionResult result,
    required String assistantMsgId,
    required String interceptedAssistantStub,
  }) {
    final messages = List<ChatMessage>.from(currentMessages);

    // استبدال رسالة المساعد بالرسالة الاعتراضية
    final assistantIdx = messages.indexWhere((m) => m.id == assistantMsgId);
    if (assistantIdx != -1) {
      messages[assistantIdx] = messages[assistantIdx].copyWith(
        content: interceptedAssistantStub,
        isStreaming: false,
        toolCalls: null,
      );
    }

    // حقن SystemTurn
    if (result.shouldInjectSystemTurn) {
      final systemMsg = buildSystemAlertMessage(_uuid.v4());
      messages.add(systemMsg);
    }

    // حقن رسالة استرداد للمستخدم (ت إعادة تشغيل الحلقة)
    if (result.shouldInjectRecoveryUserMessage) {
      final recoveryMsg = buildRecoveryUserMessage(_uuid.v4());
      messages.add(recoveryMsg);
    }

    return messages;
  }
}
