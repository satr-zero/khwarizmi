import 'dart:convert';

/// حالة المهمة المستقلة
enum TaskStatus {
  /// تعمل الحلقة المستقلة حالياً
  running,

  /// توقفت بانتظار رد المستخدم (ask_user)
  waitingForUser,

  /// اكتملت بنجاح (complete_task)
  completed,

  /// فشلت بخطأ غير قابل للتعافي
  failed,

  /// ألغاها المستخدم يدوياً
  cancelled,

  /// وصلت للحد الأقصى من الخطوات وتنتظر موافقة المستخدم للاستمرار
  pausedAtLimit,
}

/// سجل خطوة واحدة من خطوات التنفيذ المستقل
class TaskStepLog {
  final int stepIndex;
  final String action;        // وصف ما فعله النموذج في هذه الخطوة
  final String? toolName;    // اسم الأداة إن استُدعيت
  final String? toolResult;  // نتيجة الأداة (مختصرة)
  final String? thinking;    // ملخص تفكير النموذج (اختياري)
  final DateTime timestamp;

  const TaskStepLog({
    required this.stepIndex,
    required this.action,
    this.toolName,
    this.toolResult,
    this.thinking,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'stepIndex': stepIndex,
    'action': action,
    if (toolName != null) 'toolName': toolName,
    if (toolResult != null) 'toolResult': toolResult,
    if (thinking != null) 'thinking': thinking,
    'timestamp': timestamp.toIso8601String(),
  };

  factory TaskStepLog.fromJson(Map<String, dynamic> json) => TaskStepLog(
    stepIndex: (json['stepIndex'] as num?)?.toInt() ?? 0,
    action: json['action'] as String? ?? '',
    toolName: json['toolName'] as String?,
    toolResult: json['toolResult'] as String?,
    thinking: json['thinking'] as String?,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}

/// كيان المهمة المستقلة الكاملة
class Task {
  final String id;

  /// وصف الهدف كما طلبه المستخدم بالضبط
  final String goal;

  /// حالة المهمة الحالية
  final TaskStatus status;

  /// سجل كل خطوة: الإجراء، نتيجة الأداة، ملخص التفكير
  final List<TaskStepLog> stepsLog;

  /// عدد الخطوات المستقلة المنفذة حتى الآن
  final int stepCount;

  /// الحد الأقصى للخطوات (افتراضي: 25)
  final int stepCap;

  /// تاريخ إنشاء المهمة
  final DateTime createdAt;

  /// تاريخ الإتمام أو الفشل
  final DateTime? completedAt;

  /// السؤال المعلق إن كانت الحالة waitingForUser
  final String? pendingQuestion;

  /// ملخص الإتمام إن كانت الحالة completed
  final String? completionSummary;

  /// رسالة الخطأ إن كانت الحالة failed
  final String? errorMessage;

  /// معرف المزوّد المستخدم لهذه المهمة
  final String providerId;

  /// النموذج المستخدم لهذه المهمة
  final String modelName;

  const Task({
    required this.id,
    required this.goal,
    required this.status,
    this.stepsLog = const [],
    this.stepCount = 0,
    this.stepCap = 25,
    required this.createdAt,
    this.completedAt,
    this.pendingQuestion,
    this.completionSummary,
    this.errorMessage,
    required this.providerId,
    required this.modelName,
  });

  /// نسبة الإتمام (0.0 → 1.0) بناءً على الخطوات
  double get progressRatio => stepCap > 0 ? (stepCount / stepCap).clamp(0.0, 1.0) : 0.0;

  /// هل وصلت للحد الأقصى؟
  bool get isAtStepLimit => stepCount >= stepCap;

  /// هل لا تزال قيد التنفيذ؟
  bool get isActive => status == TaskStatus.running || status == TaskStatus.waitingForUser;

  Task copyWith({
    String? id,
    String? goal,
    TaskStatus? status,
    List<TaskStepLog>? stepsLog,
    int? stepCount,
    int? stepCap,
    DateTime? createdAt,
    DateTime? completedAt,
    String? pendingQuestion,
    String? completionSummary,
    String? errorMessage,
    String? providerId,
    String? modelName,
    bool clearPendingQuestion = false,
    bool clearCompletedAt = false,
  }) {
    return Task(
      id: id ?? this.id,
      goal: goal ?? this.goal,
      status: status ?? this.status,
      stepsLog: stepsLog ?? this.stepsLog,
      stepCount: stepCount ?? this.stepCount,
      stepCap: stepCap ?? this.stepCap,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      pendingQuestion: clearPendingQuestion ? null : (pendingQuestion ?? this.pendingQuestion),
      completionSummary: completionSummary ?? this.completionSummary,
      errorMessage: errorMessage ?? this.errorMessage,
      providerId: providerId ?? this.providerId,
      modelName: modelName ?? this.modelName,
    );
  }

  // ── JSON (de)serialization for SQLite storage ────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'goal': goal,
    'status': status.name,
    'stepsLog': jsonEncode(stepsLog.map((s) => s.toJson()).toList()),
    'stepCount': stepCount,
    'stepCap': stepCap,
    'createdAt': createdAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (pendingQuestion != null) 'pendingQuestion': pendingQuestion,
    if (completionSummary != null) 'completionSummary': completionSummary,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'providerId': providerId,
    'modelName': modelName,
  };

  factory Task.fromJson(Map<String, dynamic> json) {
    List<TaskStepLog> steps = [];
    try {
      final raw = json['stepsLog'];
      if (raw != null && raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        steps = decoded
            .map((e) => TaskStepLog.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return Task(
      id: json['id'] as String,
      goal: json['goal'] as String? ?? '',
      status: TaskStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String?),
        orElse: () => TaskStatus.failed,
      ),
      stepsLog: steps,
      stepCount: (json['stepCount'] as num?)?.toInt() ?? 0,
      stepCap: (json['stepCap'] as num?)?.toInt() ?? 25,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      pendingQuestion: json['pendingQuestion'] as String?,
      completionSummary: json['completionSummary'] as String?,
      errorMessage: json['errorMessage'] as String?,
      providerId: json['providerId'] as String? ?? 'gemini',
      modelName: json['modelName'] as String? ?? '',
    );
  }
}
