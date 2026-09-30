import 'dart:convert';

/// حالة المهمة الفرعية الواحدة (Atomic Sub-task)
enum SubTaskStatus {
  /// بانتظار التنفيذ
  pending,

  /// قيد التنفيذ الآن
  inProgress,

  /// اكتملت بنجاح
  completed,

  /// فشلت بعد استنفاد محاولات إعادة المحاولة
  failed,

  /// تم تخطيها (مثلاً إذا أُلغيت المهمة الرئيسية)
  skipped,
}

/// مهمة فرعية ذرية (Atomic Sub-task) — الوحدة الأصغر قابلة للتنفيذ
class SubTask {
  final String id;
  final int index;
  final String description;
  final SubTaskStatus status;
  final int retryCount;
  final int maxRetries;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? result;

  const SubTask({
    required this.id,
    required this.index,
    required this.description,
    this.status = SubTaskStatus.pending,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
    this.result,
  });

  bool get canExecute =>
      status == SubTaskStatus.pending || status == SubTaskStatus.inProgress;

  bool get isExhausted => retryCount >= maxRetries;

  SubTask copyWith({
    String? id,
    int? index,
    String? description,
    SubTaskStatus? status,
    int? retryCount,
    int? maxRetries,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
    String? result,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return SubTask(
      id: id ?? this.id,
      index: index ?? this.index,
      description: description ?? this.description,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      result: clearResult ? null : (result ?? this.result),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'index': index,
    'description': description,
    'status': status.name,
    'retryCount': retryCount,
    'maxRetries': maxRetries,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (result != null) 'result': result,
  };

  factory SubTask.fromJson(Map<String, dynamic> json) => SubTask(
    id: json['id'] as String? ?? '',
    index: (json['index'] as num?)?.toInt() ?? 0,
    description: json['description'] as String? ?? '',
    status: SubTaskStatus.values.firstWhere(
      (s) => s.name == (json['status'] as String?),
      orElse: () => SubTaskStatus.pending,
    ),
    retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
    maxRetries: (json['maxRetries'] as num?)?.toInt() ?? 3,
    errorMessage: json['errorMessage'] as String?,
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'] as String)
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'] as String)
        : null,
    result: json['result'] as String?,
  );
}

/// خطة التنفيذ الكاملة للمهمة المستقلة.
///
/// تُنشأ من [TaskPlannerService] قبل بدء التنفيذ الفعلي،
/// وتُحفظ في SQLite مع thread_id = taskId للاستئناف عند الانقطاع.
class TaskPlan {
  /// معرف الخطة (= thread_id = معرف المهمة الرئيسية)
  final String taskId;

  final String goal;

  /// قائمة المهام الفرعية الذرية المرتبة (task_list في الـ State)
  final List<SubTask> taskList;

  final DateTime createdAt;

  /// ملخص الخطة كما وضعه الوكيل
  final String? planSummary;

  const TaskPlan({
    required this.taskId,
    required this.goal,
    required this.taskList,
    required this.createdAt,
    this.planSummary,
  });

  // ── Computed Properties ───────────────────────────────────────────────────

  SubTask? get nextPendingTask {
    try {
      return taskList.firstWhere((t) => t.canExecute);
    } catch (_) {
      return null;
    }
  }

  bool get isFullyCompleted =>
      taskList.isNotEmpty &&
      taskList.every(
        (t) =>
            t.status == SubTaskStatus.completed ||
            t.status == SubTaskStatus.skipped,
      );

  bool get hasFailedTask =>
      taskList.any((t) => t.status == SubTaskStatus.failed);

  double get completionRatio {
    if (taskList.isEmpty) return 0.0;
    final done = taskList
        .where(
          (t) =>
              t.status == SubTaskStatus.completed ||
              t.status == SubTaskStatus.skipped,
        )
        .length;
    return (done / taskList.length).clamp(0.0, 1.0);
  }

  int get completedCount =>
      taskList.where((t) => t.status == SubTaskStatus.completed).length;

  int get failedCount =>
      taskList.where((t) => t.status == SubTaskStatus.failed).length;

  TaskPlan copyWith({
    String? taskId,
    String? goal,
    List<SubTask>? taskList,
    DateTime? createdAt,
    String? planSummary,
  }) {
    return TaskPlan(
      taskId: taskId ?? this.taskId,
      goal: goal ?? this.goal,
      taskList: taskList ?? this.taskList,
      createdAt: createdAt ?? this.createdAt,
      planSummary: planSummary ?? this.planSummary,
    );
  }

  /// تحديث مهمة فرعية بعينها في القائمة
  TaskPlan updateSubTask(int index, SubTask updated) {
    final newList = List<SubTask>.from(taskList);
    if (index >= 0 && index < newList.length) {
      newList[index] = updated;
    }
    return copyWith(taskList: newList);
  }

  // ── JSON Serialization ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'goal': goal,
    'taskList': jsonEncode(taskList.map((t) => t.toJson()).toList()),
    'createdAt': createdAt.toIso8601String(),
    if (planSummary != null) 'planSummary': planSummary,
  };

  factory TaskPlan.fromJson(Map<String, dynamic> json) {
    List<SubTask> tasks = [];
    try {
      final raw = json['taskList'];
      if (raw != null && raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        tasks = decoded
            .map((e) => SubTask.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return TaskPlan(
      taskId: json['taskId'] as String? ?? '',
      goal: json['goal'] as String? ?? '',
      taskList: tasks,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      planSummary: json['planSummary'] as String?,
    );
  }
}
