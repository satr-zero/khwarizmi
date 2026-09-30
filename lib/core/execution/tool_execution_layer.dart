import 'dart:async';
import 'dart:convert';

import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

// ─────────────────────────────────────────────────────────────────────────────
// طبقة تنفيذ الأدوات الموحّدة — المسار الوحيد لتنفيذ أي أداة في التطبيق.
//
// يستبدل التنفيذ المكرر في ChatController._runAgentLoop و
// TaskExecutionEngine._executeSubTask/_runClassicLoop بمسار واحد:
// - مهلة ديناميكية لكل أداة من تعريفها (timeoutFor) مع إلغاء فعلي.
// - اعتراض حاجز الأمان (بانتظار تأكيد) في مكان واحد.
// - نتيجة مُهيكلة [ToolExecutionResult] — لا JSON نصي خام يُفحص بالتخمين.
// ─────────────────────────────────────────────────────────────────────────────

/// نتيجة تنفيذ أداة واحدة — مُهيكلة لا نصية
class ToolExecutionResult {
  /// اسم الأداة
  final String toolName;

  /// نتيجة JSON الخام (تُحقن في تاريخ المحادثة لرسالة tool)
  final String resultJson;

  /// حالة الأداة النهائية للعرض
  final ToolCallStatus status;

  /// رسالة خطأ إنسانية إن فشلت
  final String? errorMessage;

  /// هل انتهت المهلة؟
  final bool timedOut;

  /// هل الأداة محجوبة بانتظار تأكيد المستخدم؟
  final bool awaitingConfirmation;

  const ToolExecutionResult({
    required this.toolName,
    required this.resultJson,
    required this.status,
    this.errorMessage,
    this.timedOut = false,
    this.awaitingConfirmation = false,
  });

  bool get isSuccess => status == ToolCallStatus.success;
  bool get isError => status == ToolCallStatus.error;
}

/// طبقة تنفيذ الأدوات — نقطة العبور الوحيدة لأي استدعاء أداة.
class ToolExecutionLayer {
  ToolExecutionLayer({this.context = 'ToolExecutionLayer'});

  final String context;
  final _log = Logger.instance;

  /// ينفّذ أداة واحدة بمهلتها الديناميكية وإلغائها الفعلي.
  ///
  /// - يفحص حاجز الأمان أولاً: إن كان هناك تأكيد معلق → [awaitingConfirmation].
  /// - عند انتهاء المهلة: يُلغي التنفيذ الداخلي فعلياً (قتل العملية)
  ///   ويعيد نتيجة خطأ مُهيكلة — لا يُترك التنفيذ يتيمًا في الخلفية.
  /// - لا يرمي استثناءات أبداً — كل فشل يُعاد في [ToolExecutionResult].
  Future<ToolExecutionResult> execute(ToolCallInfo toolCall) async {
    final cid = _log.newCorrelationId();

    // ── حاجز الأمان: تأكيد معلق → حجب فوري ────────────────────────────────
    // (يُدار عبر BrowserSecurityInterceptor في المستدعي الأعلى — هنا نكتفي
    // بالفحص البنيوي عبر ToolRegistry لأن الحاجز عالمي)
    final toolTimeout = ToolRegistry.timeoutFor(toolCall.toolName);

    _log.debug(
      context,
      'Executing tool',
      correlationId: cid,
      meta: {
        'tool': toolCall.toolName,
        'timeoutSeconds': toolTimeout.inSeconds,
      },
    );

    try {
      final raw =
          await ToolRegistry.executeTool(
            toolCall.toolName,
            toolCall.arguments,
          ).timeout(
            toolTimeout,
            onTimeout: () {
              // إلغاء فعلي للتنفيذ الداخلي — لا نترك العملية تعمل يتيمة
              ToolRegistry.cancelToolExecution(
                toolCall.toolName,
                'انتهت مهلة الأداة',
              );
              return jsonEncode({
                'error':
                    'انتهت مهلة الأداة (${toolTimeout.inSeconds} ثانية) — '
                    'تجمّد محتمل أو تأخر في الشبكة.',
                'timed_out': true,
                'tool': toolCall.toolName,
              });
            },
          );

      return _classifyRawResult(toolCall.toolName, raw);
    } catch (e) {
      _log.error(
        context,
        'Tool threw exception',
        correlationId: cid,
        meta: {'tool': toolCall.toolName, 'error': e.toString()},
      );
      return ToolExecutionResult(
        toolName: toolCall.toolName,
        resultJson: jsonEncode({'error': e.toString()}),
        status: ToolCallStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// يصنّف نتيجة JSON الخام إلى حالة عرض مُهيكلة.
  ToolExecutionResult _classifyRawResult(String toolName, String raw) {
    bool hasError = false;
    bool isBlocked = false;
    String? errorMessage;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        hasError = decoded.containsKey('error');
        isBlocked = decoded['isBlocked'] == true;
        errorMessage = decoded['error']?.toString();
      }
    } catch (_) {
      // JSON غير صالح — نعتبرها نتيجة نصية ناجحة (بعض الأدوات تعيد نصاً)
    }

    if (isBlocked) {
      return ToolExecutionResult(
        toolName: toolName,
        resultJson: raw,
        status: ToolCallStatus.awaitingConfirmation,
        awaitingConfirmation: true,
      );
    }
    if (hasError) {
      return ToolExecutionResult(
        toolName: toolName,
        resultJson: raw,
        status: ToolCallStatus.error,
        errorMessage: errorMessage,
      );
    }
    return ToolExecutionResult(
      toolName: toolName,
      resultJson: raw,
      status: ToolCallStatus.success,
    );
  }

  /// يبني رسالة tool جاهزة للحقن في تاريخ المحادثة.
  ChatMessage buildToolResultMessage(
    ToolCallInfo toolCall,
    ToolExecutionResult result,
  ) {
    return ChatMessage(
      id: '${toolCall.callId}_result',
      role: MessageRole.tool,
      content: result.resultJson,
      timestamp: DateTime.now(),
      toolCallId: toolCall.callId,
      // اسم الأداة صراحةً — لا يُستخرج من toolCallId لاحقاً
      toolName: toolCall.toolName,
    );
  }
}
