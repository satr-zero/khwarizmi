import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_detector.dart';

/// نتيجة فحص حارس «وعد بلا تنفيذ» بعد اكتمال دور المساعد.
enum ExecutionPromiseGuardAction {
  /// لا اعتراض — متابعة المسار العادي.
  none,

  /// اعتراض مع إعادة توجيه تلقائية للنموذج (حقن رسالة استرداد + SystemTurn).
  interceptAndRecover,

  /// اعتراض فقط (تنبيه للمستخدم) بعد استنفاد محاولات الاسترداد.
  interceptNoticeOnly,
}

/// خط الاعتراض الموحّد — يُستخدم من المحادثة الحية ومحرك المهام.
abstract final class ExecutionPromiseGuard {
  static const int consecutiveThreshold = 2;
  static const int maxAutoRecoveriesPerUserTurn = 1;

  static const String interceptedAssistantStub =
      '*(اعترض نظام خوارزمي هذا الرد: وعد متكرر بالتنفيذ دون استدعاء أداة — جارٍ إعادة التوجيه للتنفيذ العملي)*';

  /// نص الاستبدال عند الاعتراض التنبيهي فقط (استُنفدت محاولات الاسترداد
  /// التلقائي) — لا يعد المستخدم بإعادة توجيه لن تحدث.
  static const String interceptedAssistantNoticeOnlyStub =
      '*(اعترض نظام خوارزمي هذا الرد: وعد متكرر بالتنفيذ دون استدعاء أداة — '
      'استُنفدت محاولات الاسترداد التلقائي. قد يحتاج الأمر توضيحاً إضافياً '
      'منك، أو تبديل الموديل المستخدم.)*';

  static const String recoveryUserInjection =
      '[توجيه نظام — تنفيذ فوري إلزامي]: '
      'توقف عن الوعود والخطط اللفظية. '
      'نفّذ الآن عبر استدعاء أداة واحدة على الأقل (deliver_file أو propose_file_change أو propose_file_patch أو start_autonomous_task للمهام الكبيرة). '
      'لا تكتب أي جملة تبدأ بـ «سأقوم/سأنشئ/سأكتب» قبل أن تُرسل استدعاء الأداة في نفس الرد.';

  /// يحسب سلسلة الوعود بعد إضافة رد مساعد محتمل (قبل حفظه نهائياً).
  static int consecutiveAfterAssistantTurn({
    required List<ChatMessage> messages,
    required String assistantMsgId,
    required String assistantContent,
    required List<ToolCallInfo> toolCalls,
  }) {
    if (toolCalls.isNotEmpty) return 0;

    final base = messages.where((m) => m.id != assistantMsgId).toList();
    final synthetic = ChatMessage(
      id: assistantMsgId,
      role: MessageRole.assistant,
      content: assistantContent,
      timestamp: DateTime.now(),
    );

    return ExecutionPromiseDetector.countConsecutivePromises([
      ...base,
      synthetic,
    ]);
  }

  static ExecutionPromiseGuardAction evaluate({
    required List<ChatMessage> messages,
    required String assistantMsgId,
    required String assistantContent,
    required List<ToolCallInfo> toolCalls,
    required int promiseRecoveryAttempt,
  }) {
    if (toolCalls.isNotEmpty) return ExecutionPromiseGuardAction.none;

    final consecutive = consecutiveAfterAssistantTurn(
      messages: messages,
      assistantMsgId: assistantMsgId,
      assistantContent: assistantContent,
      toolCalls: toolCalls,
    );

    debugPrint(
      '[ExecutionPromiseGuard] consecutive=$consecutive '
      'recoveryAttempt=$promiseRecoveryAttempt '
      'historyLen=${messages.length}',
    );

    if (consecutive < consecutiveThreshold) {
      return ExecutionPromiseGuardAction.none;
    }

    if (promiseRecoveryAttempt < maxAutoRecoveriesPerUserTurn) {
      return ExecutionPromiseGuardAction.interceptAndRecover;
    }
    return ExecutionPromiseGuardAction.interceptNoticeOnly;
  }

  static ChatMessage buildSystemAlertMessage(String id) {
    return ChatMessage(
      id: id,
      role: MessageRole.system,
      content: ExecutionPromiseDetector.systemAlertNotice,
      timestamp: DateTime.now(),
    );
  }

  static ChatMessage buildRecoveryUserMessage(String id) {
    return ChatMessage(
      id: id,
      role: MessageRole.user,
      content: recoveryUserInjection,
      timestamp: DateTime.now(),
    );
  }
}
