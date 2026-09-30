import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/providers/domain/ai_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// أنواع خط التنفيذ الموحّد (Unified Execution Pipeline) — المرحلة الأساسية.
//
// هذا الملف هو العقد (Contract) الوحيد بين الواجهة والمحرك:
// - طلب واحد: [ExecutionRequest] — سواء كان سؤالاً بسيطاً أو مهمة ضخمة.
// - نتيجة واحدة مُغلّفة: [ExecutionOutcome] — لا مسار خروج صامت إطلاقاً.
// - أحداث واحدة: [ExecutionEvent] — ما تراه الواجهة أثناء التنفيذ.
// ─────────────────────────────────────────────────────────────────────────────

/// تصنيف تعقيد الطلب — يؤثر على **عمق التخطيط فقط**، لا على المسار التنفيذي.
///
/// كل الطلبات تمر عبر نفس المحرك ونفس الحلقة؛ الفرق الوحيد هو:
/// - [simple]: حلقة وكيل مباشرة بلا مرحلة تخطيط.
/// - [complex]: مرحلة تخطيط (Plan) ثم حلقة الوكيل نفسها لكل مهمة فرعية.
enum ExecutionComplexity { simple, complex }

/// طلب تنفيذ موحّد — نقطة الدخول الوحيدة لخط التنفيذ.
class ExecutionRequest {
  /// معرف فريد للطلب (يُستخدم للتتبع في السجلات والواجهة)
  final String id;

  /// نص الطلب الكامل (سؤال المستخدم أو هدف المهمة)
  final String input;

  /// سياق المحادثة المتراكم (للطلبات داخل محادثة)
  final List<ChatMessage> conversationHistory;

  /// معرف المزوّد والنموذج المستخدمين
  final String providerId;
  final String modelName;
  final String apiKey;

  /// الـ System Prompt المُجهَّز من المستدعي (هوية + ذكريات + سياق مشروع...)
  final String systemPrompt;

  /// الأدوات المتاحة لهذا الطلب (مُصفّاة حسب النمط النشط في المستدعي)
  final List<ToolDefinition> availableTools;

  /// إعداد التفكير الموسَّع إن كان النموذج يدعمه
  final ThinkingConfig? thinking;

  /// هل هذا طلب مهمة مستقلة صريح (start_autonomous_task)؟
  /// إن كان true → تخطيط إلزامي بغض النظر عن التصنيف.
  final bool isExplicitTask;

  /// هل تتطلب الخطة اعتماد المستخدم قبل التنفيذ؟
  final bool requirePlanApproval;

  /// رد المستخدم المعلق إن كان هذا استئنافاً لمهمة متوقفة
  final String? pendingUserReply;

  /// معرف المهمة المستقلة إن كان هذا استئنافاً (resume)
  final String? resumeTaskId;

  /// سقف الخطوات للمهام المستقلة
  final int stepCap;

  const ExecutionRequest({
    required this.id,
    required this.input,
    required this.conversationHistory,
    required this.providerId,
    required this.modelName,
    required this.apiKey,
    required this.systemPrompt,
    this.availableTools = const [],
    this.thinking,
    this.isExplicitTask = false,
    this.requirePlanApproval = false,
    this.pendingUserReply,
    this.resumeTaskId,
    this.stepCap = TaskExecutionEngineDefaults.stepCap,
  });
}

/// ثوابت المحرك الموحّد
abstract final class TaskExecutionEngineDefaults {
  /// الحد الأقصى الافتراضي لخطوات الحلقة المستقلة
  static const int stepCap = 25;

  /// عتبة السكوت قبل أول نبض إحاطة ("الخادم يعالج منذ X ثانية") —
  /// **لا تُلغي البث**: النماذج الضخمة تصمت دقائق وهي تعمل بشرعية
  static const Duration idleTimeout = Duration(seconds: 90);

  /// السقف المطلق لانتظار بث واحد مهما حدث — الحماية الوحيدة من
  /// التعليق الحقيقي (اتصال ميت فعلاً)
  static const Duration absoluteStreamCap = Duration(minutes: 10);
}

/// رموز الفشل المُصنَّفة — كل فشل له سبب محدد ورسالة عربية واضحة للمستخدم.
enum ExecutionFailureCode {
  /// تجاوز البث السقف المطلق (10 دقائق) دون اكتمال — الاتصال ميت فعلاً
  streamIdleTimeout,

  /// خطأ HTTP من المزوّد (4xx/5xx)
  providerHttpError,

  /// خطأ شبكة (انقطاع اتصال، DNS، socket)
  networkError,

  /// المزوّد أعاد رداً فارغاً تماماً (لا نص ولا أدوات)
  emptyResponse,

  /// ألغى المستخدم التنفيذ يدوياً
  cancelledByUser,

  /// فشلت مهمة فرعية بعد استنفاد كل محاولات إعادة المحاولة
  subTaskFailed,

  /// فشل التخطيط نفسه (تعذّر توليد خطة صالحة)
  planningFailed,

  /// خطأ غير متوقع غير مصنّف
  unexpectedError;

  /// رسالة عربية محددة لكل رمز — تظهر للمستخدم دائماً، لا فشل صامت
  String get userMessage {
    switch (this) {
      case ExecutionFailureCode.streamIdleTimeout:
        return 'تجاوز البث الحد الأقصى المطلق للانتظار (10 دقائق) دون '
            'اكتمال — على الأغلب انقطع الاتصال فعلاً. '
            'تحقق من الشبكة وأعد المحاولة، أو جرّب موديلاً أخف.';
      case ExecutionFailureCode.providerHttpError:
        return 'رفض مزوّد النموذج الطلب بخطأ HTTP. '
            'قد يكون مفتاح API غير صالح أو حد الاستخدام (Rate Limit) قد استُنفد.';
      case ExecutionFailureCode.networkError:
        return 'تعذّر الوصول إلى مزوّد النموذج عبر الشبكة. '
            'تحقق من اتصالك بالإنترنت ثم أعد المحاولة.';
      case ExecutionFailureCode.emptyResponse:
        return 'أعاد النموذج رداً فارغاً تماماً (لا نص ولا استدعاء أدوات) '
            'بعد عدة محاولات. قد لا يدعم النموذج الحالي هذا النوع من الطلبات.';
      case ExecutionFailureCode.cancelledByUser:
        return 'تم إيقاف التنفيذ بناءً على طلبك.';
      case ExecutionFailureCode.subTaskFailed:
        return 'فشلت إحدى خطوات الخطة نهائياً بعد كل محاولات إعادة المحاولة. '
            'راجع تفاصيل الخطأ في الخطوة المعنية.';
      case ExecutionFailureCode.planningFailed:
        return 'تعذّر توليد خطة عمل صالحة لهذه المهمة. '
            'أعد صياغة الطلب بمزيد من التفاصيل وحاول مجدداً.';
      case ExecutionFailureCode.unexpectedError:
        return 'حدث خطأ غير متوقع أثناء التنفيذ. التفاصيل الفنية أدناه.';
    }
  }
}

/// فشل تنفيذ مُصنَّف — يحمل الرمز + التفاصيل الفنية + المحتوى الجزئي المُنجز.
class ExecutionFailure {
  final ExecutionFailureCode code;

  /// التفاصيل الفنية الخام (رسالة الاستثناء الأصلية)
  final String detail;

  /// المحتوى الجزئي الذي أُنجز قبل الفشل — **لا يُهدر أبداً**.
  /// إن وُجد، يُعرض للمستخدم مع الفشل بدل إخفائه.
  final String? partialContent;

  /// هل هذا الفشل قابل لإعادة المحاولة؟
  final bool isRetryable;

  const ExecutionFailure({
    required this.code,
    required this.detail,
    this.partialContent,
    this.isRetryable = false,
  });

  /// الرسالة النهائية للمستخدم: الرسالة المعيارية + المحتوى الجزئي إن وجد
  String get displayMessage {
    final base = code.userMessage;
    if (partialContent != null && partialContent!.trim().isNotEmpty) {
      return '$base\n\n'
          '── ما أُنجز قبل التوقف (محفوظ ولم يُهدر) ──\n'
          '${partialContent!.trim()}';
    }
    return base;
  }

  @override
  String toString() => 'ExecutionFailure(${code.name}): $detail';
}

/// النتيجة النهائية لأي تنفيذ — مُغلّفة (sealed) فلا مسار خروج غير مُعرَّف.
///
/// كل تنفيذ ينتهي بواحدة من هذه الحالات حصراً — لا "توقف صامت" إطلاقاً.
sealed class ExecutionOutcome {
  const ExecutionOutcome();
}

/// ✅ اكتمل التنفيذ بنجاح — [text] هو الرد النهائي للمستخدم.
class ExecutionSuccess extends ExecutionOutcome {
  final String text;
  const ExecutionSuccess(this.text);
}

/// ❌ فشل التنفيذ — [failure] يحدد السبب والرسالة والمحتوى الجزئي المحفوظ.
class ExecutionFailed extends ExecutionOutcome {
  final ExecutionFailure failure;
  const ExecutionFailed(this.failure);
}

/// ⏹️ أوقف المستخدم التنفيذ — [partialContent] ما أُنجز قبل الإيقاف.
class ExecutionCancelled extends ExecutionOutcome {
  final String? partialContent;
  const ExecutionCancelled([this.partialContent]);
}

/// ❓ توقف التنفيذ بانتظار رد المستخدم (ask_user) — [question] هو السؤال.
class ExecutionAwaitingUser extends ExecutionOutcome {
  final String question;
  final String? taskId;
  const ExecutionAwaitingUser(this.question, {this.taskId});
}

/// 📋 الخطة جاهزة وتنتظر اعتماد المستخدم — حالة إيقاف حتمية داخل المحرك.
class ExecutionAwaitingPlanApproval extends ExecutionOutcome {
  final TaskPlan plan;
  final String taskId;
  const ExecutionAwaitingPlanApproval(this.plan, this.taskId);
}

/// ⏸️ وصل التنفيذ لسقف الخطوات — ينتظر موافقة المستخدم على الاستمرار.
class ExecutionPausedAtLimit extends ExecutionOutcome {
  final String taskId;
  const ExecutionPausedAtLimit(this.taskId);
}

// ─────────────────────────────────────────────────────────────────────────────
// أحداث التنفيذ الحية — ما تستهلكه الواجهة أثناء عمل المحرك.
// ─────────────────────────────────────────────────────────────────────────────

/// أحداث خط التنفيذ الموحّد التي تبثها [UnifiedAgentExecutor] للواجهة.
sealed class ExecutionEvent {
  const ExecutionEvent();
}

/// مقطع نص من رد النموذج
class ExecutionTextChunk extends ExecutionEvent {
  final String text;
  const ExecutionTextChunk(this.text);
}

/// مقطع نص من تفكير النموذج الداخلي
class ExecutionThinkingChunk extends ExecutionEvent {
  final String text;
  const ExecutionThinkingChunk(this.text);
}

/// استدعاء أداة بدأ
class ExecutionToolCallStarted extends ExecutionEvent {
  final ToolCallInfo toolCall;
  const ExecutionToolCallStarted(this.toolCall);
}

/// استدعاء أداة انتهى (نجاح أو خطأ)
class ExecutionToolCallFinished extends ExecutionEvent {
  final ToolCallInfo toolCall;
  const ExecutionToolCallFinished(this.toolCall);
}

/// تحديث حالة نصي قصير (شريط الحالة)
class ExecutionStatusUpdate extends ExecutionEvent {
  final String status;
  const ExecutionStatusUpdate(this.status);
}

/// إعادة محاولة تلقائية جارية — بانر للمستخدم
class ExecutionRetryScheduled extends ExecutionEvent {
  final int attempt;
  final int maxAttempts;
  final Duration delay;
  final String reason;
  const ExecutionRetryScheduled({
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
    required this.reason,
  });
}

/// خُطِّطت خطة جديدة (أو استُعيدت خطة محفوظة)
class ExecutionPlanCreated extends ExecutionEvent {
  final TaskPlan plan;
  const ExecutionPlanCreated(this.plan);
}

/// بدأت مهمة فرعية
class ExecutionSubTaskStarted extends ExecutionEvent {
  final SubTask subTask;
  const ExecutionSubTaskStarted(this.subTask);
}

/// اكتملت مهمة فرعية
class ExecutionSubTaskCompleted extends ExecutionEvent {
  final SubTask subTask;
  const ExecutionSubTaskCompleted(this.subTask);
}

/// فشلت مهمة فرعية
class ExecutionSubTaskFailed extends ExecutionEvent {
  final SubTask subTask;
  final String error;
  const ExecutionSubTaskFailed(this.subTask, this.error);
}

/// إعادة محاولة مهمة فرعية
class ExecutionSubTaskRetry extends ExecutionEvent {
  final SubTask subTask;
  final int attempt;
  const ExecutionSubTaskRetry(this.subTask, this.attempt);
}

/// تحديث حالة المهمة المستقلة (للوحة المهام)
class ExecutionTaskUpdated extends ExecutionEvent {
  final Task task;
  const ExecutionTaskUpdated(this.task);
}

/// إعادة توجيه حدث خام من المزوّد (مثل AgentRetryEvent) — للتوافق الخلفي
class ExecutionRawEvent extends ExecutionEvent {
  final AgentEvent event;
  const ExecutionRawEvent(this.event);
}
