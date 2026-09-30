import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/core/security/browser_security_interceptor.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/core/services/agent_identity_service.dart';
import 'package:khwarizmi/features/agent/data/task_database.dart';
import 'package:khwarizmi/features/agent/data/task_plan_database.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:khwarizmi/features/agent/services/task_planner_service.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/scheduler/services/notification_service.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
import 'package:khwarizmi/features/chat/presentation/utils/execution_promise_guard.dart';
import 'package:khwarizmi/features/chat/presentation/utils/unified_interceptor.dart';
import 'package:khwarizmi/core/execution/execution_types.dart';
import 'package:khwarizmi/core/execution/stream_collector.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';
import 'package:uuid/uuid.dart';

/// أحداث صادرة من [TaskExecutionEngine] للواجهة
abstract class TaskEngineEvent {
  const TaskEngineEvent();
}

class TaskUpdatedEvent extends TaskEngineEvent {
  final Task task;
  const TaskUpdatedEvent(this.task);
}

class TaskBrowserActionEvent extends TaskEngineEvent {
  final String action; // وصف الإجراء الحالي على المتصفح
  const TaskBrowserActionEvent(this.action);
}

/// أحداث ردود الفعل المباشرة للشات أثناء تنفيذ مهمة مستقلة
class TaskExecutionCallbacks {
  final void Function(ToolCallInfo toolCall)? onToolCall;
  final void Function(ToolCallInfo finishedCall)? onToolResult;
  final void Function(String chunk)? onTextChunk;
  final void Function(String question)? onAskUser;
  final void Function(String summary)? onComplete;
  final void Function(String progress)? onProgress;
  final void Function(Task task)? onTaskUpdated;

  /// يُستدعى عند إنشاء خطة المهمة الأولية (Planner Node)
  final void Function(TaskPlan plan)? onPlanCreated;

  /// يُستدعى عندما تكون الخطة جاهزة وتنتظر موافقة المستخدم الصريحة
  final void Function(TaskPlan plan)? onPlanAwaitingApproval;

  /// يُستدعى عند بدء تنفيذ مهمة فرعية
  final void Function(SubTask subTask)? onSubTaskStarted;

  /// يُستدعى بعد إتمام مهمة فرعية بنجاح
  final void Function(SubTask subTask)? onSubTaskCompleted;

  /// يُستدعى عند فشل مهمة فرعية بشكل نهائي
  final void Function(SubTask subTask, String error)? onSubTaskFailed;

  /// يُستدعى عند إعادة محاولة مهمة فرعية
  final void Function(SubTask subTask, int attempt)? onSubTaskRetry;

  const TaskExecutionCallbacks({
    this.onToolCall,
    this.onToolResult,
    this.onTextChunk,
    this.onAskUser,
    this.onComplete,
    this.onProgress,
    this.onTaskUpdated,
    this.onPlanCreated,
    this.onPlanAwaitingApproval,
    this.onSubTaskStarted,
    this.onSubTaskCompleted,
    this.onSubTaskFailed,
    this.onSubTaskRetry,
  });
}

/// محرّك التنفيذ المستقل — قلب المرحلة 7.
///
/// يُشغّل حلقة وكيل ذاتية: يستدعي النموذج، ينفذ الأدوات، ويكرر
/// **دون انتظار أي مدخل من المستخدم بين الخطوات** حتى واحدة من:
/// - `complete_task` → إتمام ناجح
/// - `ask_user` → توقف وانتظار رد
/// - خطأ غير قابل للتعافي → إخفاق
/// - `stepCount >= stepCap` → `pausedAtLimit` + انتظار موافقة
class TaskExecutionEngine with LoggingMixin {
  static final TaskExecutionEngine instance = TaskExecutionEngine._();
  TaskExecutionEngine._();

  static const _uuid = Uuid();

  @override
  String get loggingContext => 'TaskExecutionEngine';

  /// الحد الأقصى الافتراضي للخطوات المستقلة لكل مهمة
  static const int defaultStepCap = 25;

  /// الحد الأقصى لمحاولات إعادة التنفيذ عند خطأ الشبكة/API
  static const int _maxRetries = 3;

  /// القاعدة الأساسية للـ Exponential Backoff بالثواني
  static const double _backoffBase = 2.0;

  /// سقف تكرارات حلقة النموذج داخل المهمة الفرعية الواحدة — يمنع دوران
  /// الخطوة إلى ما لا نهاية (كل تكرار = استدعاء نموذج كامل).
  static const int subTaskIterationCap = 12;

  // ── Stream للواجهة ────────────────────────────────────────────────────────

  final _eventController = StreamController<TaskEngineEvent>.broadcast();
  Stream<TaskEngineEvent> get eventStream => _eventController.stream;

  // ── حالة داخلية ───────────────────────────────────────────────────────────

  final Map<String, Completer<void>> _cancellationCompleters = {};
  final Map<String, bool> _cancelledTasks = {};

  // ── Public API ────────────────────────────────────────────────────────────

  /// يستعيد أي مهام كانت بحالة [TaskStatus.running] عند إغلاق التطبيق غير المتوقع.
  /// يحولها إلى [TaskStatus.failed] مع توضيح سبب الانقطاع حتى لا تبقى عالقة.
  Future<void> recoverInterruptedTasks() async {
    try {
      final runningTasks = await TaskDatabase.getTasksByStatus(
        TaskStatus.running,
      );
      for (final task in runningTasks) {
        final now = DateTime.now();
        await TaskDatabase.updateTaskStatus(
          task.id,
          TaskStatus.failed,
          errorMessage: 'تمت مقاطعة تنفيذ المهمة لإغلاق أو إعادة تشغيل التطبيق غير المتوقع.',
          completedAt: now,
        );
        final updated = task.copyWith(
          status: TaskStatus.failed,
          errorMessage: 'تمت مقاطعة تنفيذ المهمة لإغلاق أو إعادة تشغيل التطبيق غير المتوقع.',
          completedAt: now,
        );
        _emitUpdate(updated);
      }
      if (runningTasks.isNotEmpty) {
        debugPrint(
          '[TaskExecutionEngine] Recovered ${runningTasks.length} interrupted task(s).',
        );
      }
    } catch (e) {
      debugPrint('[TaskExecutionEngine] recoverInterruptedTasks error: $e');
    }
  }

  /// يبدأ مهمة مستقلة جديدة.
  ///
  /// إذا كانت المهمة ضخمة، تمر أولاً بمرحلة [TaskPlannerService] لبناء خطة
  /// مرتبة من المهام الفرعية الذرية قبل بدء التنفيذ الفعلي.
  ///
  /// يرجع [Task] المنشأة فوراً — الحلقة تعمل بالخلفية.
  Future<Task> startTask({
    required String goal,
    int stepCap = defaultStepCap,
    TaskExecutionCallbacks? callbacks,
    bool requirePlanApproval = false,
  }) async {
    final apiKey = await SecureStorageService.getApiKey(
      await SecureStorageService.getActiveProvider(),
    );
    final providerId = await SecureStorageService.getActiveProvider();
    final provider = ProviderRegistry.getProvider(providerId);
    final modelName =
        await SecureStorageService.getProviderModel(providerId) ??
        provider.defaultModel;

    final task = Task(
      id: _uuid.v4(),
      goal: goal,
      status: TaskStatus.running,
      stepCap: stepCap,
      createdAt: DateTime.now(),
      providerId: providerId,
      modelName: modelName,
    );

    await TaskDatabase.insertTask(task);
    _emitUpdate(task);
    callbacks?.onTaskUpdated?.call(task);

    // الحلقة تعمل بالخلفية دون await
    _runLoop(
      task,
      apiKey ?? '',
      callbacks: callbacks,
      requirePlanApproval: requirePlanApproval,
    );

    return task;
  }

  /// يستأنف مهمة مؤجلة بنفس الـ thread_id (بعد انقطاع أو إعادة تشغيل).
  ///
  /// يقرأ الخطة المحفوظة من SQLite، يتخطى المهام الفرعية المكتملة،
  /// ويستأنف من أول مهمة حالتها pending أو inProgress.
  Future<Task?> resumeTaskFromPlan(String taskId) async {
    final task = await TaskDatabase.getTaskById(taskId);
    if (task == null) return null;
    if (task.status != TaskStatus.running &&
        task.status != TaskStatus.waitingForUser) {
      return null;
    }

    final plan = await TaskPlanDatabase.getPlanByTaskId(taskId);
    if (plan == null || plan.isFullyCompleted) return null;

    // تنظيف أي علم إلغاء قديم قبل الاستئناف
    _cancelledTasks.remove(taskId);

    final apiKey = await SecureStorageService.getApiKey(task.providerId);
    final running = task.copyWith(status: TaskStatus.running);
    await TaskDatabase.updateTask(running);
    _emitUpdate(running);

    _runLoopWithPlan(running, plan, apiKey ?? '');
    return running;
  }

  /// يعتمد خطة عمل مهمة معلقة ويبدأ في تنفيذ المهام الفرعية فوراً
  Future<void> approveAndExecutePlan(
    String taskId, {
    TaskExecutionCallbacks? callbacks,
  }) async {
    final task = await TaskDatabase.getTaskById(taskId);
    if (task == null) return;

    final plan = await TaskPlanDatabase.getPlanByTaskId(taskId);
    if (plan == null) return;

    // تنظيف أي علم إلغاء قديم — وإلا كسر _runLoopWithPlan من أول خطوة
    // (العلم كان يبقى true إلى الأبد بعد أي إلغاء سابق لنفس المهمة).
    _cancelledTasks.remove(taskId);

    final apiKey = await SecureStorageService.getApiKey(task.providerId);

    final running = task.copyWith(
      status: TaskStatus.running,
      clearPendingQuestion: true,
    );
    await TaskDatabase.updateTask(running);
    _emitUpdate(running);
    callbacks?.onTaskUpdated?.call(running);

    debugPrint(
      '[TaskExecutionEngine] Plan approved for $taskId. Starting execution of ${plan.taskList.length} sub-tasks.',
    );
    _runLoopWithPlan(running, plan, apiKey ?? '', callbacks: callbacks);
  }

  /// يستأنف مهمة في حالة [TaskStatus.waitingForUser] برد المستخدم.
  Future<void> resumeTask(
    String taskId,
    String userReply, {
    TaskExecutionCallbacks? callbacks,
  }) async {
    final task = await TaskDatabase.getTaskById(taskId);
    if (task == null || task.status != TaskStatus.waitingForUser) return;

    // تنظيف أي علم إلغاء قديم قبل الاستئناف
    _cancelledTasks.remove(taskId);

    // فحص ما إذا كانت المهمة تنتظر اعتماد خطة عمل
    final plan = await TaskPlanDatabase.getPlanByTaskId(taskId);
    if (plan != null && !plan.isFullyCompleted) {
      final isAwaitingPlanApproval =
          task.pendingQuestion != null &&
          task.pendingQuestion!.contains('هل تعتمد الخطة للبدء');

      if (isAwaitingPlanApproval) {
        final trimmed = userReply.trim().toLowerCase();
        final isAffirmative =
            trimmed.contains('نعم') ||
            trimmed.contains('موافق') ||
            trimmed.contains('اعتمد') ||
            trimmed.contains('ابدأ') ||
            trimmed.contains('تم') ||
            trimmed.contains('yes') ||
            trimmed.contains('ok') ||
            trimmed.contains('approve');

        final isNegative =
            trimmed == 'لا' ||
            trimmed.contains('الغاء') ||
            trimmed.contains('إلغاء') ||
            trimmed.contains('ارفض') ||
            trimmed.contains('cancel') ||
            trimmed.contains('no');

        if (isAffirmative) {
          await approveAndExecutePlan(taskId, callbacks: callbacks);
          return;
        } else if (isNegative) {
          await cancelTask(taskId);
          callbacks?.onProgress?.call('تم إلغاء المهمة بناءً على طلبك.');
          return;
        }
      }

      // ── قرار المستخدم بعد فشل خطوة فرعية: متابعة / إعادة / إلغاء ──────
      final isAwaitingFailureDecision =
          task.pendingQuestion != null &&
          task.pendingQuestion!.contains('هل أُكمل بقية الخطوات');

      if (isAwaitingFailureDecision) {
        final trimmed = userReply.trim().toLowerCase();

        final wantsCancel =
            trimmed == 'لا' ||
            trimmed.contains('الغاء') ||
            trimmed.contains('إلغاء') ||
            trimmed.contains('ارفض') ||
            trimmed.contains('cancel') ||
            trimmed.contains('no');
        if (wantsCancel) {
          await cancelTask(taskId);
          callbacks?.onProgress?.call('تم إلغاء المهمة بناءً على طلبك.');
          return;
        }

        final wantsRetry =
            trimmed.contains('أعد') ||
            trimmed.contains('اعد') ||
            trimmed.contains('إعاد') ||
            trimmed.contains('اعاد') ||
            trimmed.contains('حاول') ||
            trimmed.contains('retry');
        if (wantsRetry) {
          // إرجاع كل الخطوات الفاشلة إلى pending لإعادة تنفيذها، ثم يتبع
          // المسار العام أدناه فيستأنف الخطة (بالخطة المحدثة) مع رد المستخدم.
          var updatedPlan = plan;
          for (var j = 0; j < updatedPlan.taskList.length; j++) {
            final st = updatedPlan.taskList[j];
            if (st.status == SubTaskStatus.failed) {
              updatedPlan = updatedPlan.updateSubTask(
                j,
                st.copyWith(
                  status: SubTaskStatus.pending,
                  retryCount: 0,
                  clearError: true,
                  clearResult: true,
                ),
              );
            }
          }
          await TaskPlanDatabase.updateTaskList(taskId, updatedPlan);
          callbacks?.onProgress?.call('🔄 سيُعاد تنفيذ الخطوة الفاشلة...');
        }
        // «متابعة» أو أي رد آخر → المسار العام: يستأنف الخطة متخطياً
        // الخطوات الفاشلة، مع حقن رد المستخدم كسياق.
      }
    }

    final apiKey = await SecureStorageService.getApiKey(task.providerId);

    // أضف رد المستخدم كسياق إضافي
    final updatedTask = task.copyWith(
      status: TaskStatus.running,
      clearPendingQuestion: true,
      stepsLog: [
        ...task.stepsLog,
        TaskStepLog(
          stepIndex: task.stepCount,
          action: 'رد المستخدم على السؤال',
          thinking: userReply,
          timestamp: DateTime.now(),
        ),
      ],
    );

    await TaskDatabase.updateTask(updatedTask);
    _emitUpdate(updatedTask);
    callbacks?.onTaskUpdated?.call(updatedTask);
    _runLoop(
      updatedTask,
      apiKey ?? '',
      userReplyInjection: userReply,
      callbacks: callbacks,
    );
  }

  /// يستأنف مهمة في حالة [TaskStatus.pausedAtLimit] بخطوات إضافية.
  Future<void> extendTask(String taskId) async {
    final task = await TaskDatabase.getTaskById(taskId);
    if (task == null || task.status != TaskStatus.pausedAtLimit) return;

    // تنظيف أي علم إلغاء قديم قبل التمديد
    _cancelledTasks.remove(taskId);

    final apiKey = await SecureStorageService.getApiKey(task.providerId);
    final extended = task.copyWith(
      status: TaskStatus.running,
      stepCap: task.stepCap + defaultStepCap,
    );

    await TaskDatabase.updateTask(extended);
    _emitUpdate(extended);
    _runLoop(extended, apiKey ?? '');
  }

  /// يلغي مهمة نشطة
  Future<void> cancelTask(String taskId) async {
    _cancelledTasks[taskId] = true;
    _cancellationCompleters[taskId]?.complete();

    // إصلاح 03: إلغاء المهمة يُنهي أيضاً أي انتظار قرار Diff معلّق ضمنها —
    // الانتظار لم يعد يملك مهلة تلقائية تُحرره.
    ProjectManager.instance.cancelAllPendingDecisions();

    // إصلاح 10: إلغاء المهمة يقطع أيضاً أي أداة قيد التنفيذ ضمنها (خاصة
    // أوامر الترمينال الجارية) فوراً — لا يُترك الأمر يعمل بعد الإلغاء.
    ToolRegistry.cancelActiveTools('تم إلغاء المهمة بواسطة المستخدم');

    final task = await TaskDatabase.getTaskById(taskId);
    if (task == null) return;
    final cancelled = task.copyWith(
      status: TaskStatus.cancelled,
      completedAt: DateTime.now(),
    );
    await TaskDatabase.updateTask(cancelled);
    _emitUpdate(cancelled);
  }

  // ── الحلقة الداخلية ───────────────────────────────────────────────────────

  /// نقطة الدخول الرئيسية — تُقرر تلقائياً ما إذا تحتاج مرحلة تخطيط
  Future<void> _runLoop(
    Task task,
    String apiKey, {
    String? userReplyInjection,
    TaskExecutionCallbacks? callbacks,
    bool requirePlanApproval = false,
  }) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logInfo(
      'Starting _runLoop',
      correlationId: correlationId,
      taskId: task.id,
      meta: {
        'goal': task.goal,
        'stepCap': task.stepCap,
        'provider': task.providerId,
        'model': task.modelName,
        'userReplyInjection': userReplyInjection != null,
        'requirePlanApproval': requirePlanApproval,
      },
    );

    // ── مرحلة التخطيط المسبق (Planner Node) ──────────────────────────────
    if (userReplyInjection == null) {
      final savedPlan = await TaskPlanDatabase.getPlanByTaskId(task.id);
      TaskPlan plan;

      if (savedPlan != null && !savedPlan.isFullyCompleted) {
        logInfo(
          'Resuming from saved plan',
          correlationId: correlationId,
          taskId: task.id,
          meta: {
            'planId': savedPlan.taskId,
            'subTasks': savedPlan.taskList.length,
          },
        );
        plan = savedPlan;
      } else {
        logInfo(
          'Generating new plan via TaskPlannerService',
          correlationId: correlationId,
          taskId: task.id,
          meta: {'goal': task.goal},
        );
        plan = await TaskPlannerService.generatePlan(
          taskId: task.id,
          goal: task.goal,
          providerId: task.providerId,
          modelName: task.modelName,
          apiKey: apiKey,
        );
        await TaskPlanDatabase.upsertPlan(plan);
        callbacks?.onPlanCreated?.call(plan);
        logInfo(
          'New plan generated',
          correlationId: correlationId,
          taskId: task.id,
          meta: {'planId': plan.taskId, 'subTasks': plan.taskList.length},
        );
      }

      // إذا كانت الخطة تتطلب اعتماد المستخدم الصريح قبل البدء
      if (requirePlanApproval && !plan.isFullyCompleted) {
        // حارس: أُلغيت المهمة أثناء التخطيط (زر الإيقاف) — لا تعرض بطاقة
        // اعتماد لميت، ولا تترك المهمة معلقة بانتظار مستخدم لن يأتي
        if (_cancelledTasks[task.id] == true) {
          final cancelled = task.copyWith(
            status: TaskStatus.cancelled,
            completedAt: DateTime.now(),
          );
          await TaskDatabase.updateTask(cancelled);
          _emitUpdate(cancelled);
          callbacks?.onTaskUpdated?.call(cancelled);
          logInfo(
            'Task cancelled during planning — skipping plan approval UI',
            correlationId: correlationId,
            taskId: task.id,
          );
          return;
        }
        final waitingTask = task.copyWith(
          status: TaskStatus.waitingForUser,
          pendingQuestion:
              'تم إعداد خطة العمل (${plan.taskList.length} مهام فرعية). هل تعتمد الخطة للبدء في التنفيذ؟',
        );
        await TaskDatabase.updateTask(waitingTask);
        _emitUpdate(waitingTask);
        callbacks?.onPlanAwaitingApproval?.call(plan);
        callbacks?.onTaskUpdated?.call(waitingTask);
        // إشعار ويندوز — جهوزية الخطة حدث يستحق الانتباه حتى والنافذة
        // غير مركزة، فالتنفيذ متوقف بانتظار قرارك
        await NotificationService.showNotification(
          identifier: 'task_plan_${task.id}',
          title: '📋 خوارزمي: خطة جاهزة للاعتماد',
          body:
              'تم إعداد خطة العمل (${plan.taskList.length} مهام فرعية) — راجعها في الشات واعتمدها للبدء.',
        );
        logInfo(
          'Paused for user plan approval',
          correlationId: correlationId,
          taskId: task.id,
          meta: {'planId': plan.taskId},
        );
        return;
      }

      logInfo(
        'Delegating to _runLoopWithPlan',
        correlationId: correlationId,
        taskId: task.id,
        meta: {'planId': plan.taskId},
      );
      return _runLoopWithPlan(task, plan, apiKey, callbacks: callbacks);
    }

    // إذا كان هناك رد مستخدم وكانت هناك خطة محفوظة غير مكتملة، استأنف تنفيذ الخطة
    final savedPlan = await TaskPlanDatabase.getPlanByTaskId(task.id);
    if (savedPlan != null && !savedPlan.isFullyCompleted) {
      logInfo(
        'Resuming plan execution with user reply',
        correlationId: correlationId,
        taskId: task.id,
        meta: {'planId': savedPlan.taskId},
      );
      return _runLoopWithPlan(
        task,
        savedPlan,
        apiKey,
        callbacks: callbacks,
        userReplyInjection: userReplyInjection,
      );
    }

    logInfo(
      'Delegating to _runClassicLoop (no saved plan)',
      correlationId: correlationId,
      taskId: task.id,
    );
    return _runClassicLoop(
      task,
      apiKey,
      userReplyInjection: userReplyInjection,
      callbacks: callbacks,
    );
  }

  /// تنفيذ الخطة مهمة فرعية تلو الأخرى مع Checkpoint بعد كل مهمة
  Future<void> _runLoopWithPlan(
    Task task,
    TaskPlan plan,
    String apiKey, {
    TaskExecutionCallbacks? callbacks,
    String? userReplyInjection,
  }) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logInfo(
      'Starting _runLoopWithPlan',
      correlationId: correlationId,
      taskId: task.id,
      meta: {
        'planId': plan.taskId,
        'totalSubTasks': plan.taskList.length,
        'userReplyInjection': userReplyInjection != null,
      },
    );

    var currentTask = task;
    var currentPlan = plan;
    var pendingUserReply = userReplyInjection;

    for (var i = 0; i < currentPlan.taskList.length; i++) {
      final subTask = currentPlan.taskList[i];

      if (subTask.status == SubTaskStatus.completed ||
          subTask.status == SubTaskStatus.skipped) {
        logDebug(
          'Sub-task already done, skipping',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {
            'subTaskIndex': i,
            'subTaskId': subTask.id,
            'status': subTask.status.name,
          },
        );
        continue;
      }
      if (subTask.status == SubTaskStatus.failed) {
        logWarn(
          'Sub-task permanently failed, skipping',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {
            'subTaskIndex': i,
            'subTaskId': subTask.id,
            'error': subTask.errorMessage,
          },
        );
        continue;
      }
      if (_cancelledTasks[currentTask.id] == true) {
        logInfo(
          'Task cancelled, breaking plan execution',
          correlationId: correlationId,
          taskId: currentTask.id,
        );
        break;
      }

      var activeSubTask = subTask.copyWith(
        status: SubTaskStatus.inProgress,
        startedAt: DateTime.now(),
      );
      currentPlan = currentPlan.updateSubTask(i, activeSubTask);
      await TaskPlanDatabase.updateTaskList(currentTask.id, currentPlan);
      callbacks?.onSubTaskStarted?.call(activeSubTask);

      logInfo(
        'Starting sub-task execution',
        correlationId: correlationId,
        taskId: currentTask.id,
        meta: {
          'subTaskIndex': i,
          'subTaskId': activeSubTask.id,
          'description': activeSubTask.description,
        },
      );

      bool subTaskSucceeded = false;
      String lastError = '';

      for (int attempt = 0; attempt <= _maxRetries; attempt++) {
        if (attempt > 0) {
          final waitSecs = math.pow(_backoffBase, attempt).toInt();
          logInfo(
            'Retrying sub-task',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'subTaskIndex': i,
              'subTaskId': activeSubTask.id,
              'attempt': attempt,
              'maxRetries': _maxRetries,
              'waitSeconds': waitSecs,
            },
          );
          callbacks?.onSubTaskRetry?.call(activeSubTask, attempt);
          callbacks?.onProgress?.call(
            '⏳ إعادة محاولة $attempt/$_maxRetries للمهمة الفرعية ${i + 1} — انتظار ${waitSecs}s...',
          );
          await Future.delayed(Duration(seconds: waitSecs));
        }

        try {
          final result = await _executeSubTask(
            currentTask,
            activeSubTask,
            apiKey,
            callbacks: callbacks,
            userReply: pendingUserReply,
          );
          pendingUserReply = null; // تُحقن مرة واحدة فقط للخطوة المستأنفة

          // إصلاح 02: الإشارات الطرفية الآن هي فقط ask_user (إيقاف
          // بانتظار رد المستخدم) أو الإلغاء — complete_task داخل خطة لم
          // يعد طرفياً بل مهمة فرعية منتهية، فتستمر الخطة للمهام التالية.
          if (result.wasTerminalSignal) {
            logInfo(
              'Sub-task returned terminal signal (ask_user/cancel), stopping plan',
              correlationId: correlationId,
              taskId: currentTask.id,
              meta: {'subTaskIndex': i, 'summary': result.summary},
            );
            return;
          }

          activeSubTask = activeSubTask.copyWith(
            status: SubTaskStatus.completed,
            completedAt: DateTime.now(),
            result: result.summary,
            clearError: true,
          );
          currentPlan = currentPlan.updateSubTask(i, activeSubTask);
          await TaskPlanDatabase.updateTaskList(currentTask.id, currentPlan);
          callbacks?.onSubTaskCompleted?.call(activeSubTask);
          logInfo(
            'Sub-task completed successfully',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'subTaskIndex': i,
              'subTaskId': activeSubTask.id,
              'summary': result.summary,
            },
          );
          subTaskSucceeded = true;
          break;
        } catch (e) {
          lastError = e.toString();
          logError(
            'Sub-task attempt failed',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'subTaskIndex': i,
              'subTaskId': activeSubTask.id,
              'attempt': attempt + 1,
              'error': lastError,
            },
          );
          activeSubTask = activeSubTask.copyWith(
            retryCount: attempt + 1,
            errorMessage: lastError,
          );
          currentPlan = currentPlan.updateSubTask(i, activeSubTask);
          await TaskPlanDatabase.updateTaskList(currentTask.id, currentPlan);

          // فشل غير قابل للإعادة (HTTP 400، مفتاح مفقود، رد فارغ...) —
          // إعادة المحاولة بنفس الطلب لن تغير النتيجة، فلا تُهدر backoff.
          if (e is _NonRetryableSubTaskFailure) {
            logWarn(
              'Non-retryable sub-task failure — skipping remaining retries',
              correlationId: correlationId,
              taskId: currentTask.id,
              meta: {'subTaskIndex': i, 'error': lastError},
            );
            break;
          }
        }
      }

      if (!subTaskSucceeded) {
        activeSubTask = activeSubTask.copyWith(
          status: SubTaskStatus.failed,
          completedAt: DateTime.now(),
          errorMessage: lastError,
        );
        currentPlan = currentPlan.updateSubTask(i, activeSubTask);
        await TaskPlanDatabase.updateTaskList(currentTask.id, currentPlan);
        callbacks?.onSubTaskFailed?.call(activeSubTask, lastError);

        // إصلاح جوهري: فشل خطوة لم يعد يُجهض المهمة كلها — المهمة تتحول
        // إلى waitingForUser ويُعرض السؤال على المستخدم ليقرر بنفسه:
        // «متابعة» (تخطي الفاشلة وإكمال البقية) أو «إعادة» (إعادة محاولتها)
        // أو «إلغاء» (إيقاف المهمة). الاستئناف يمر عبر resumeTask أدناه.
        final question =
            'فشلت المهمة الفرعية ${i + 1} "${activeSubTask.description}" '
            'بعد ${_maxRetries + 1} محاولات.\n'
            'الخطأ: $lastError\n\n'
            'هل أُكمل بقية الخطوات؟ أجب «متابعة» للانتقال إلى الخطوة التالية، '
            'أو «إعادة» لإعادة محاولة هذه الخطوة، أو «إلغاء» لإيقاف المهمة.';
        currentTask = await _askUser(currentTask, question);
        callbacks?.onTaskUpdated?.call(currentTask);
        logWarn(
          'Sub-task failed — task paused for user decision',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {'subTaskIndex': i, 'error': lastError},
        );
        return;
      }

      currentTask = currentTask.copyWith(stepCount: currentTask.stepCount + 1);
      await TaskDatabase.updateTask(currentTask);
      _emitUpdate(currentTask);
      callbacks?.onTaskUpdated?.call(currentTask);
    }

    if (_cancelledTasks[currentTask.id] != true) {
      final summary = _buildPlanSummary(currentPlan);
      logInfo(
        'Plan fully executed, completing task',
        correlationId: correlationId,
        taskId: currentTask.id,
        meta: {'summary': summary},
      );
      currentTask = await _completeTask(currentTask, summary);
      callbacks?.onComplete?.call(summary);
      callbacks?.onTaskUpdated?.call(currentTask);
    } else {
      logInfo(
        'Plan execution cancelled',
        correlationId: correlationId,
        taskId: currentTask.id,
      );
    }
  }

  Future<_SubTaskResult> _executeSubTask(
    Task task,
    SubTask subTask,
    String apiKey, {
    TaskExecutionCallbacks? callbacks,
    String? userReply,
  }) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logInfo(
      'Starting _executeSubTask',
      correlationId: correlationId,
      taskId: task.id,
      meta: {
        'subTaskId': subTask.id,
        'subTaskIndex': subTask.index,
        'subTaskDescription': subTask.description,
        'hasUserReply': userReply != null && userReply.trim().isNotEmpty,
      },
    );

    final systemPrompt = await AgentIdentityService.loadSystemPrompt();
    String effectiveSystem = systemPrompt;

    try {
      final geminiKey = (task.providerId == 'gemini')
          ? apiKey
          : await SecureStorageService.getApiKey('gemini');
      final relevant = await MemoryRepository.searchMemory(
        query: subTask.description,
        limit: 2,
        minScore: 0.35,
        apiKey: geminiKey,
      );
      if (relevant.isNotEmpty) {
        effectiveSystem +=
            '\n\n[ذكريات ذات صلة]:\n${relevant.map((m) => '- ${m.entry.content}').join('\n')}\n';
        logDebug(
          'Injected relevant memories',
          correlationId: correlationId,
          taskId: task.id,
          meta: {'count': relevant.length},
        );
      }
    } catch (e) {
      logWarn(
        'Memory search failed',
        correlationId: correlationId,
        taskId: task.id,
        meta: {'error': e.toString()},
      );
    }

    effectiveSystem += _subTaskInstructions(task, subTask);

    final subTaskPrompt = (userReply != null && userReply.trim().isNotEmpty)
        ? 'نفّذ المهمة الفرعية التالية باستقلالية كاملة:\n\n${subTask.description}\n\n[إجابة المستخدم على سؤالك المعلق]:\n$userReply'
        : 'نفّذ المهمة الفرعية التالية باستقلالية كاملة:\n\n${subTask.description}';

    final history = [
      ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: subTaskPrompt,
        timestamp: DateTime.now(),
      ),
    ];

    var currentTask = task;
    var promiseRecoveryAttempt = 0;
    var thinkingNudgeUsed = false;
    var iteration = 0;
    while (true) {
      iteration++;
      if (_cancelledTasks[currentTask.id] == true) {
        logInfo(
          'Task cancelled during sub-task execution',
          correlationId: correlationId,
          taskId: currentTask.id,
        );
        return _SubTaskResult(wasTerminalSignal: true, summary: 'ألغيت المهمة');
      }

      // سقف التكرارات — يمنع دوران الخطوة الواحدة إلى ما لا نهاية
      if (iteration > subTaskIterationCap) {
        logWarn(
          'Sub-task iteration cap reached',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {'iteration': iteration, 'cap': subTaskIterationCap},
        );
        throw _NonRetryableSubTaskFailure(
          'iteration_cap_exceeded: تجاوزت هذه المهمة الفرعية الحد الأقصى '
          'للتكرارات ($subTaskIterationCap) دون إكمال.',
        );
      }

      final provider = ProviderRegistry.getProvider(currentTask.providerId);

      logDebug(
        'Calling provider.sendMessage',
        correlationId: correlationId,
        taskId: currentTask.id,
        meta: {
          'iteration': iteration,
          'provider': currentTask.providerId,
          'model': currentTask.modelName,
          'historyLength': history.length,
          'toolsAvailable': ToolRegistry.getAutonomousDefinitions().length,
          'promiseRecoveryAttempt': promiseRecoveryAttempt,
        },
      );

      // ── إصلاح جوهري: جمع البث عبر StreamCollector الموحّد ────────────────
      // النمط القديم (listen + asFuture + throw داخل الـ listener) كان يبتلع
      // الأخطاء كأخطاء Zone صامتة لا تصل لـ catch الخارجي أبداً، فيُفسَّر
      // الخطأ كـ«رد فارغ» وتُهدر 3 محاولات إعادة قبل إفشال المهمة كلها.
      // StreamCollector لا يرمي استثناءات إطلاقاً: كل فشل يعود مُصنَّفاً
      // (retryable أم لا) مع الحفاظ على النص الجزئي المُستقبَل.
      final collector = StreamCollector(
        correlationId: correlationId,
        context: 'TaskExecutionEngine._executeSubTask',
      );
      final result = await collector.collect(
        provider.sendMessage(
          history: history,
          availableTools: ToolRegistry.getAutonomousDefinitions(),
          systemPrompt: effectiveSystem,
          apiKey: apiKey,
          modelName: currentTask.modelName,
        ),
        onEvent: (event) {
          if (_cancelledTasks[currentTask.id] == true) return;
          if (event is AgentTextChunk) {
            callbacks?.onTextChunk?.call(event.text);
          } else if (event is AgentToolCallEvent) {
            callbacks?.onToolCall?.call(event.toolCall);
          }
        },
        shouldAbort: () => _cancelledTasks[currentTask.id] == true,
        onIdleAdvisory: (idleSeconds) {
          // نبض إحاطة أثناء صمت البث (ميكانيكية opencode): البث حي ويعمل —
          // النموذج يولّد على الخادم. لا إلغاء، فقط يطمئن المستخدم.
          callbacks?.onProgress?.call(
            '⏳ لا استجابة جديدة من الخادم منذ $idleSeconds ثانية — '
            'البث ما زال مفتوحاً والنموذج يعمل على الرد...',
          );
        },
      );

      if (_cancelledTasks[currentTask.id] == true) {
        logInfo(
          'Task cancelled after stream',
          correlationId: correlationId,
          taskId: currentTask.id,
        );
        return _SubTaskResult(wasTerminalSignal: true, summary: 'ألغيت');
      }

      // فشل مُصنَّف من المزوّد أو الشبكة — قرار الإعادة مبني على التصنيف
      if (!result.completed && result.failure != null) {
        final failure = result.failure!;
        logError(
          'Provider stream failed in _executeSubTask',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {
            'iteration': iteration,
            'code': failure.code.name,
            'isRetryable': failure.isRetryable,
            'detail': failure.detail,
          },
        );
        if (!failure.isRetryable) {
          // فشل نهائي (HTTP 400، مفتاح مفقود...) — لا تُهدر محاولات backoff
          throw _NonRetryableSubTaskFailure(
            '${failure.code.name}: ${failure.detail}',
          );
        }
        throw Exception('${failure.code.name}: ${failure.detail}');
      }

      final assistantText = result.text;
      final toolCalls = result.toolCalls;

      logInfo(
        'Provider stream completed',
        correlationId: correlationId,
        taskId: currentTask.id,
        meta: {
          'iteration': iteration,
          'assistantTextLength': assistantText.length,
          'toolCallsCount': toolCalls.length,
        },
      );

      // حماية نماذج التفكير: رد تفكير فقط (reasoning) بلا نص/أدوات — يُحقن
      // توجيه وحيد لطلب النتيجة بدل إفشال الخطوة زائفاً.
      if (assistantText.trim().isEmpty && toolCalls.isEmpty) {
        if (result.thinking.trim().isNotEmpty && !thinkingNudgeUsed) {
          thinkingNudgeUsed = true;
          logWarn(
            'Thinking-only response — injecting result nudge',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'iteration': iteration,
              'thinkingLength': result.thinking.length,
            },
          );
          history.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.user,
              content:
                  '[توجيه نظام]: أنهيتَ التفكير ولم تُصدر أي نتيجة نصية. '
                  'قدّم الآن نتيجة المهمة الفرعية الحالية كنص موجز وواضح — '
                  'دون أي استدعاء أدوات.',
              timestamp: DateTime.now(),
            ),
          );
          continue;
        }
        logWarn(
          'Empty model response (no text, no tools)',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {'iteration': iteration},
        );
        throw _NonRetryableSubTaskFailure(
          'empty_model_response: أعاد النموذج ردًا فارغًا بدون نص أو أدوات',
        );
      }

      // مساعد ID للاعتراض الموحد
      final assistantMsgId = _uuid.v4();

      history.add(
        ChatMessage(
          id: assistantMsgId,
          role: MessageRole.assistant,
          content: assistantText,
          timestamp: DateTime.now(),
          toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
        ),
      );

      if (toolCalls.isEmpty) {
        logDebug(
          'No tool calls returned, checking promise recovery',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {
            'iteration': iteration,
            'assistantTextPreview': assistantText.length > 100
                ? '${assistantText.substring(0, 100)}...'
                : assistantText,
          },
        );
        if (_checkAndInjectPromiseRecovery(
          history,
          promiseRecoveryAttempt: promiseRecoveryAttempt,
          assistantMsgId: assistantMsgId,
          assistantContent: assistantText,
          toolCalls: toolCalls,
        )) {
          promiseRecoveryAttempt++;
          logInfo(
            'Promise recovery injected, continuing loop',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {'promiseRecoveryAttempt': promiseRecoveryAttempt},
          );
          continue;
        }
        logInfo(
          'Sub-task completed with text response (no tools)',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {'iteration': iteration, 'summaryLength': assistantText.length},
        );
        return _SubTaskResult(wasTerminalSignal: false, summary: assistantText);
      }

      logInfo(
        'Processing tool calls',
        correlationId: correlationId,
        taskId: currentTask.id,
        meta: {
          'iteration': iteration,
          'toolCalls': toolCalls.map((tc) => tc.toolName).toList(),
        },
      );

      for (final toolCall in toolCalls) {
        if (_cancelledTasks[currentTask.id] == true) break;

        if (toolCall.toolName == 'complete_task') {
          final s = toolCall.arguments['summary'] as String? ?? assistantText;
          // إصلاح 02: داخل خطة، complete_task ليست إشارة إتمام للهدف —
          // تُعامل دفاعياً كمهمة فرعية منتهية فقط (قرار معتمد). إشارة
          // اكتمال المهمة الفرعية هي رد نصي خالص دون أدوات (toolCalls
          //isEmpty أعلاه). لا نستدعي _completeTask هنا إطلاقاً — إتمام
          // الهدف يُدار مركزياً في _runLoopWithPlan بعد اكتمال كل المهام.
          logInfo(
            'Sub-task complete_task tool called',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {'summary': s},
          );
          return _SubTaskResult(wasTerminalSignal: false, summary: s);
        }

        if (toolCall.toolName == 'ask_user') {
          final q = toolCall.arguments['question'] as String? ?? '';
          logInfo(
            'Sub-task ask_user tool called',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {'question': q},
          );
          await _askUser(currentTask, q);
          callbacks?.onAskUser?.call(q);
          return _SubTaskResult(wasTerminalSignal: true, summary: q);
        }

        if (toolCall.toolName == 'report_progress') {
          final msg = toolCall.arguments['message'] as String? ?? '';
          logDebug(
            'Sub-task report_progress',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {'message': msg},
          );
          callbacks?.onProgress?.call(msg);
          history.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.tool,
              content: jsonEncode({
                'status': 'progress_reported',
                'message': msg,
              }),
              timestamp: DateTime.now(),
              toolCallId: toolCall.callId,
              // إصلاح 01: اسم الأداة صراحةً — لا يُستخرج من toolCallId.
              toolName: toolCall.toolName,
            ),
          );
          continue;
        }

        if (_isBrowserTool(toolCall.toolName)) {
          _eventController.add(
            TaskBrowserActionEvent(
              '${_browserActionLabel(toolCall.toolName)}: '
              '${toolCall.arguments['url'] ?? toolCall.arguments['selector'] ?? ""}',
            ),
          );
        }

        String resultJson;
        try {
          if (BrowserSecurityInterceptor.isAwaitingConfirmation) {
            resultJson = jsonEncode({
              'isBlocked': true,
              'reason': 'تنتظر تأكيد المستخدم',
            });
          } else {
            // إصلاح 06: مهلة ديناميكية لكل أداة بدل 60 ثانية ثابتة، مع
            // إلغاء التنفيذ فعلياً عند انتهائها (قتل العملية الداخلية).
            final toolTimeout = ToolRegistry.timeoutFor(toolCall.toolName);
            resultJson =
                await ToolRegistry.executeTool(
                  toolCall.toolName,
                  toolCall.arguments,
                ).timeout(
                  toolTimeout,
                  onTimeout: () {
                    ToolRegistry.cancelToolExecution(
                      toolCall.toolName,
                      'انتهت مهلة الأداة',
                    );
                    return jsonEncode({
                      'error':
                          'انتهت مهلة الأداة (${toolTimeout.inSeconds} ثانية) — تجمّد محتمل أو تأخر في الشبكة.',
                      'timed_out': true,
                      'tool': toolCall.toolName,
                    });
                  },
                );
          }
          if (resultJson.contains('"isBlocked":true')) {
            final blocked = jsonDecode(resultJson) as Map<String, dynamic>;
            final q = '🔒 تأكيد مطلوب: ${blocked['reason']}';
            await _askUser(currentTask, q);
            callbacks?.onAskUser?.call(q);
            return _SubTaskResult(wasTerminalSignal: true, summary: q);
          }
        } catch (e) {
          resultJson = jsonEncode({'error': e.toString()});
        }

        callbacks?.onToolResult?.call(
          toolCall.copyWith(
            status: resultJson.contains('"error"')
                ? ToolCallStatus.error
                : ToolCallStatus.success,
            result: resultJson,
          ),
        );

        history.add(
          ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.tool,
            content: resultJson,
            timestamp: DateTime.now(),
            toolCallId: toolCall.callId,
            // إصلاح 01: اسم الأداة صراحةً — لا يُستخرج من toolCallId.
            toolName: toolCall.toolName,
          ),
        );
      }
    }
  }

  String _buildPlanSummary(TaskPlan plan) {
    return 'اكتملت الخطة: ${plan.completedCount}/${plan.taskList.length} مهمة فرعية'
        '${plan.failedCount > 0 ? " (${plan.failedCount} فشلت)" : ""}. '
        'الهدف: ${plan.goal}';
  }

  /// الحلقة الكلاسيكية (للاستخدام عند استئناف رد المستخدم)
  Future<void> _runClassicLoop(
    Task task,
    String apiKey, {
    String? userReplyInjection,
    TaskExecutionCallbacks? callbacks,
  }) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logInfo(
      'Starting _runClassicLoop',
      correlationId: correlationId,
      taskId: task.id,
      meta: {
        'goal': task.goal,
        'stepCap': task.stepCap,
        'provider': task.providerId,
        'model': task.modelName,
        'userReplyInjection': userReplyInjection != null,
        'stepCount': task.stepCount,
      },
    );

    final canceller = Completer<void>();
    _cancellationCompleters[task.id] = canceller;
    _cancelledTasks.remove(task.id);

    var currentTask = task;
    var iteration = 0;

    try {
      // ─── بناء سياق المحادثة الأولي ─────────────────────────────────────
      final systemPrompt = await AgentIdentityService.loadSystemPrompt();

      // حقن ذاكرة ذات صلة
      String effectiveSystem = systemPrompt;
      try {
        final geminiKey = (currentTask.providerId == 'gemini')
            ? apiKey
            : await SecureStorageService.getApiKey('gemini');
        final relevant = await MemoryRepository.searchMemory(
          query: currentTask.goal,
          limit: 3,
          minScore: 0.35,
          apiKey: geminiKey,
        );
        if (relevant.isNotEmpty) {
          final memStr = relevant
              .map((sm) => '- [${sm.entry.category}] ${sm.entry.content}')
              .join('\n');
          effectiveSystem +=
              '\n\n[ذكريات ذات صلة مسترجعة]:\n$memStr\n(استخدمها بسلاسة).\n';
          logDebug(
            'Injected relevant memories',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {'count': relevant.length},
          );
        }
      } catch (e) {
        logWarn(
          'Memory search failed',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {'error': e.toString()},
        );
      }

      // تعليمات الوكيل المستقل
      effectiveSystem += _autonomousInstructions(currentTask);

      // حقن الفهرس الخفيف للمهارات النصية الإرشادية
      try {
        final textSkillsIndex = await TextSkillService.instance
            .getLightweightIndexPrompt();
        if (textSkillsIndex.isNotEmpty) {
          effectiveSystem += '\n\n$textSkillsIndex\n';
        }
      } catch (e) {
        logWarn(
          'TextSkill index failed',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {'error': e.toString()},
        );
      }

      // رسالة البدء
      final List<ChatMessage> history = [
        ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.user,
          content: userReplyInjection != null
              ? '--- رد المستخدم على سؤالي ---\n$userReplyInjection\n\nأكمل تنفيذ المهمة الأصلية: ${currentTask.goal}'
              : 'نفّذ المهمة التالية باستقلالية كاملة: ${currentTask.goal}',
          timestamp: DateTime.now(),
        ),
      ];

      var promiseRecoveryAttempt = 0;
      var thinkingNudgeUsed = false;

      // ─── الحلقة الرئيسية ──────────────────────────────────────────────
      while (true) {
        iteration++;
        // فحص الإلغاء
        if (_cancelledTasks[currentTask.id] == true) {
          logInfo(
            'Task cancelled, breaking classic loop',
            correlationId: correlationId,
            taskId: currentTask.id,
          );
          break;
        }

        // فحص السقف — الأهم بعد الأمان
        if (currentTask.stepCount >= currentTask.stepCap) {
          logWarn(
            'Step cap reached, pausing at limit',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'stepCount': currentTask.stepCount,
              'stepCap': currentTask.stepCap,
            },
          );
          currentTask = await _pauseAtLimit(currentTask);
          callbacks?.onTaskUpdated?.call(currentTask);
          break;
        }

        final provider = ProviderRegistry.getProvider(currentTask.providerId);
        final availableTools = ToolRegistry.getAutonomousDefinitions();

        logDebug(
          'Calling provider.sendMessage (classic loop)',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {
            'iteration': iteration,
            'provider': currentTask.providerId,
            'model': currentTask.modelName,
            'historyLength': history.length,
            'toolsAvailable': availableTools.length,
            'promiseRecoveryAttempt': promiseRecoveryAttempt,
          },
        );

        // ── StreamCollector الموحّد — نفس إصلاح _executeSubTask ──────────
        // لا يُرمى استثناء من داخل listener (كان يُبتلع كخطأ Zone صامت)،
        // وكل فشل يعود مُصنَّفاً مع النص الجزئي المُستقبَل.
        final collector = StreamCollector(
          correlationId: correlationId,
          context: 'TaskExecutionEngine._runClassicLoop',
        );
        final result = await collector.collect(
          provider.sendMessage(
            history: history,
            availableTools: availableTools,
            systemPrompt: effectiveSystem,
            apiKey: apiKey,
            modelName: currentTask.modelName,
          ),
          onEvent: (event) {
            if (_cancelledTasks[currentTask.id] == true) return;
            if (event is AgentTextChunk) {
              callbacks?.onTextChunk?.call(event.text);
            } else if (event is AgentToolCallEvent) {
              callbacks?.onToolCall?.call(event.toolCall);
            }
          },
          shouldAbort: () => _cancelledTasks[currentTask.id] == true,
          abortSignal: canceller.future,
          onIdleAdvisory: (idleSeconds) {
            // نبض إحاطة أثناء صمت البث — لا إلغاء (ميكانيكية opencode)
            callbacks?.onProgress?.call(
              '⏳ لا استجابة جديدة من الخادم منذ $idleSeconds ثانية — '
              'البث ما زال مفتوحاً والنموذج يعمل على الرد...',
            );
          },
        );

        if (_cancelledTasks[currentTask.id] == true) break;

        if (!result.completed && result.failure != null) {
          final failure = result.failure!;
          logError(
            'Provider stream failed in _runClassicLoop',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'iteration': iteration,
              'code': failure.code.name,
              'isRetryable': failure.isRetryable,
              'detail': failure.detail,
            },
          );
          if (failure.code == ExecutionFailureCode.cancelledByUser) break;
          currentTask = await _failTask(
            currentTask,
            '${failure.code.name}: ${failure.detail}',
          );
          callbacks?.onTaskUpdated?.call(currentTask);
          return;
        }

        final assistantText = result.text;
        final toolCalls = result.toolCalls;

        logInfo(
          'Provider stream completed (classic loop)',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {
            'iteration': iteration,
            'assistantTextLength': assistantText.length,
            'toolCallsCount': toolCalls.length,
          },
        );

        // حماية: رد فارغ تمامًا (أو تفكير فقط) — نفس حماية _executeSubTask
        if (assistantText.trim().isEmpty && toolCalls.isEmpty) {
          if (result.thinking.trim().isNotEmpty && !thinkingNudgeUsed) {
            thinkingNudgeUsed = true;
            logWarn(
              'Thinking-only response — injecting result nudge (classic loop)',
              correlationId: correlationId,
              taskId: currentTask.id,
              meta: {'iteration': iteration},
            );
            history.add(
              ChatMessage(
                id: _uuid.v4(),
                role: MessageRole.user,
                content:
                    '[توجيه نظام]: أنهيتَ التفكير ولم تُصدر أي نتيجة نصية. '
                    'قدّم الآن نتيجتك نصياً — دون أي استدعاء أدوات.',
                timestamp: DateTime.now(),
              ),
            );
            continue;
          }
          logWarn(
            'Empty model response (no text, no tools)',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {'iteration': iteration},
          );
          currentTask = await _failTask(
            currentTask,
            'empty_model_response: أعاد النموذج ردًا فارغًا بدون نص أو أدوات. '
            'تأكد من أن النموذج يدعم وضع الوكيل المستقل مع أدوات.',
          );
          callbacks?.onTaskUpdated?.call(currentTask);
          return;
        }

        // مساعد ID للاعتراض الموحد
        final assistantMsgId = _uuid.v4();

        // أضف رد المساعد للتاريخ
        history.add(
          ChatMessage(
            id: assistantMsgId,
            role: MessageRole.assistant,
            content: assistantText,
            timestamp: DateTime.now(),
            toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
          ),
        );

        // ─── لا أدوات = إجابة نصية مباشرة = لا يجوز بالمهام المستقلة ──
        if (toolCalls.isEmpty) {
          logDebug(
            'No tool calls returned, checking promise recovery',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'iteration': iteration,
              'assistantTextPreview': assistantText.length > 100
                  ? '${assistantText.substring(0, 100)}...'
                  : assistantText,
            },
          );
          if (_checkAndInjectPromiseRecovery(
            history,
            promiseRecoveryAttempt: promiseRecoveryAttempt,
            assistantMsgId: assistantMsgId,
            assistantContent: assistantText,
            toolCalls: toolCalls,
          )) {
            promiseRecoveryAttempt++;
            logInfo(
              'Promise recovery injected, continuing classic loop',
              correlationId: correlationId,
              taskId: currentTask.id,
              meta: {'promiseRecoveryAttempt': promiseRecoveryAttempt},
            );
            continue;
          }
          // إن رجع نصاً بدون أداة، نعتبره إتماماً ضمنياً
          logInfo(
            'Classic loop completed with text response (no tools)',
            correlationId: correlationId,
            taskId: currentTask.id,
            meta: {
              'iteration': iteration,
              'summaryLength': assistantText.length,
            },
          );
          currentTask = await _completeTask(currentTask, assistantText);
          callbacks?.onComplete?.call(assistantText);
          callbacks?.onTaskUpdated?.call(currentTask);
          break;
        }

        logInfo(
          'Processing tool calls (classic loop)',
          correlationId: correlationId,
          taskId: currentTask.id,
          meta: {
            'iteration': iteration,
            'toolCalls': toolCalls.map((tc) => tc.toolName).toList(),
          },
        );

        // ─── تنفيذ الأدوات ────────────────────────────────────────────
        bool shouldBreak = false;

        for (final toolCall in toolCalls) {
          if (_cancelledTasks[currentTask.id] == true) break;

          // ─ فحص أدوات التحكم أولاً ─────────────────────────────────
          if (toolCall.toolName == 'complete_task') {
            final summary =
                toolCall.arguments['summary'] as String? ?? assistantText;
            currentTask = await _completeTask(currentTask, summary);
            callbacks?.onComplete?.call(summary);
            callbacks?.onTaskUpdated?.call(currentTask);
            shouldBreak = true;
            break;
          }

          if (toolCall.toolName == 'ask_user') {
            final question = toolCall.arguments['question'] as String? ?? '';
            currentTask = await _askUser(currentTask, question);
            callbacks?.onAskUser?.call(question);
            callbacks?.onTaskUpdated?.call(currentTask);
            shouldBreak = true;
            break;
          }

          if (toolCall.toolName == 'report_progress') {
            final message = toolCall.arguments['message'] as String? ?? '';
            currentTask = _addProgressLog(currentTask, message);
            await TaskDatabase.updateTask(currentTask);
            _emitUpdate(currentTask);
            callbacks?.onProgress?.call(message);
            callbacks?.onTaskUpdated?.call(currentTask);
            // لا break — التنفيذ يستمر
            history.add(
              ChatMessage(
                id: _uuid.v4(),
                role: MessageRole.tool,
                content: jsonEncode({
                  'status': 'progress_reported',
                  'message': message,
                }),
                timestamp: DateTime.now(),
                toolCallId: toolCall.callId,
                // إصلاح 01: اسم الأداة صراحةً — لا يُستخرج من toolCallId.
                toolName: toolCall.toolName,
              ),
            );
            continue;
          }

          // ─ تنفيذ أداة عادية ──────────────────────────────────────
          if (_isBrowserTool(toolCall.toolName)) {
            _eventController.add(
              TaskBrowserActionEvent(
                '${_browserActionLabel(toolCall.toolName)}: '
                '${toolCall.arguments['url'] ?? toolCall.arguments['selector'] ?? ''}',
              ),
            );
          }

          String resultJson;
          try {
            // حاجز أمان الدفع (المرحلة 6) يبقى سارياً داخل الحلقة
            if (BrowserSecurityInterceptor.isAwaitingConfirmation) {
              resultJson = jsonEncode({
                'isBlocked': true,
                'reason': 'تنتظر تأكيد المستخدم للإجراء المالي السابق',
              });
            } else {
              // إصلاح 06: مهلة ديناميكية لكل أداة بدل 60 ثانية ثابتة، مع
              // إلغاء التنفيذ فعلياً عند انتهائها (قتل العملية الداخلية).
              final toolTimeout = ToolRegistry.timeoutFor(toolCall.toolName);
              resultJson =
                  await ToolRegistry.executeTool(
                    toolCall.toolName,
                    toolCall.arguments,
                  ).timeout(
                    toolTimeout,
                    onTimeout: () {
                      ToolRegistry.cancelToolExecution(
                        toolCall.toolName,
                        'انتهت مهلة الأداة',
                      );
                      return jsonEncode({
                        'error':
                            'انتهت مهلة الأداة (${toolTimeout.inSeconds} ثانية) — تجمّد محتمل أو تأخر في الشبكة.',
                        'timed_out': true,
                        'tool': toolCall.toolName,
                      });
                    },
                  );
            }

            // إن صدر حاجز أمان → ask_user للمستخدم يرى الصفحة
            if (resultJson.contains('"isBlocked":true')) {
              final blocked = jsonDecode(resultJson) as Map<String, dynamic>;
              final question =
                  '🔒 تأكيد مطلوب: ${blocked['reason'] ?? 'إجراء مالي يستلزم موافقتك الصريحة. هل تريد المتابعة؟'}';
              currentTask = await _askUser(currentTask, question);
              callbacks?.onAskUser?.call(question);
              callbacks?.onTaskUpdated?.call(currentTask);
              shouldBreak = true;
              break;
            }
          } catch (e) {
            resultJson = jsonEncode({'error': e.toString()});
          }

          // إعلام الشات بنتيجة الأداة
          final finishedCall = toolCall.copyWith(
            status: resultJson.contains('"error"')
                ? ToolCallStatus.error
                : (resultJson.contains('"isBlocked":true')
                      ? ToolCallStatus.awaitingConfirmation
                      : ToolCallStatus.success),
            result: resultJson,
          );
          callbacks?.onToolResult?.call(finishedCall);

          // تسجيل الخطوة
          final stepLog = TaskStepLog(
            stepIndex: currentTask.stepCount + 1,
            action: 'استدعاء أداة: ${toolCall.toolName}',
            toolName: toolCall.toolName,
            toolResult: _truncate(resultJson, 400),
            timestamp: DateTime.now(),
          );

          currentTask = currentTask.copyWith(
            stepCount: currentTask.stepCount + 1,
            stepsLog: [...currentTask.stepsLog, stepLog],
          );

          await TaskDatabase.updateTask(currentTask);
          _emitUpdate(currentTask);
          callbacks?.onTaskUpdated?.call(currentTask);

          history.add(
            ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.tool,
              content: resultJson,
              timestamp: DateTime.now(),
              toolCallId: toolCall.callId,
              // إصلاح 01: اسم الأداة صراحةً — لا يُستخرج من toolCallId.
              toolName: toolCall.toolName,
            ),
          );

          // فحص السقف بعد كل أداة
          if (currentTask.stepCount >= currentTask.stepCap) {
            currentTask = await _pauseAtLimit(currentTask);
            callbacks?.onTaskUpdated?.call(currentTask);
            shouldBreak = true;
            break;
          }
        }

        if (shouldBreak || _cancelledTasks[currentTask.id] == true) break;
      }
    } catch (e, st) {
      debugPrint(
        '[TaskExecutionEngine] Unhandled error in task ${task.id}: $e\n$st',
      );
      currentTask = await _failTask(currentTask, e.toString());
      callbacks?.onTaskUpdated?.call(currentTask);
    } finally {
      _cancellationCompleters.remove(task.id);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Task> _completeTask(Task task, String summary) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logInfo(
      'Completing task',
      correlationId: correlationId,
      taskId: task.id,
      meta: {'summaryLength': summary.length},
    );

    final completed = task.copyWith(
      status: TaskStatus.completed,
      completionSummary: summary,
      completedAt: DateTime.now(),
    );
    await TaskDatabase.updateTask(completed);
    _emitUpdate(completed);

    // إشعار Windows
    await NotificationService.showNotification(
      identifier: 'task_done_${task.id}',
      title: '✅ خوارزمي: مهمة مكتملة',
      body: 'المهمة: "${_truncate(task.goal, 60)}" — اكتملت بنجاح.',
    );
    logInfo(
      'Task completed',
      correlationId: correlationId,
      taskId: completed.id,
    );
    return completed;
  }

  Future<Task> _askUser(Task task, String question) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logInfo(
      'Task waiting for user',
      correlationId: correlationId,
      taskId: task.id,
      meta: {'questionPreview': _truncate(question, 100)},
    );

    final waiting = task.copyWith(
      status: TaskStatus.waitingForUser,
      pendingQuestion: question,
    );
    await TaskDatabase.updateTask(waiting);
    _emitUpdate(waiting);

    await NotificationService.showNotification(
      identifier: 'task_ask_${task.id}',
      title: '❓ خوارزمي يحتاج إجابة',
      body: _truncate(question, 150),
    );
    logInfo(
      'Task set to waitingForUser',
      correlationId: correlationId,
      taskId: waiting.id,
    );
    return waiting;
  }

  Future<Task> _pauseAtLimit(Task task) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logWarn(
      'Task paused at step limit',
      correlationId: correlationId,
      taskId: task.id,
      meta: {'stepCount': task.stepCount, 'stepCap': task.stepCap},
    );

    final paused = task.copyWith(status: TaskStatus.pausedAtLimit);
    await TaskDatabase.updateTask(paused);
    _emitUpdate(paused);

    await NotificationService.showNotification(
      identifier: 'task_limit_${task.id}',
      title: '⏸️ خوارزمي: وصلت للحد الأقصى للخطوات',
      body:
          'المهمة "${_truncate(task.goal, 60)}" وصلت لـ ${task.stepCap} خطوة — موافقتك مطلوبة للاستمرار.',
    );
    logInfo(
      'Task set to pausedAtLimit',
      correlationId: correlationId,
      taskId: paused.id,
    );
    return paused;
  }

  Future<Task> _failTask(Task task, String error) async {
    final correlationId = _uuid.v4().substring(0, 8);
    logError(
      'Task failed',
      correlationId: correlationId,
      taskId: task.id,
      meta: {'errorPreview': _truncate(error, 200)},
    );

    final failed = task.copyWith(
      status: TaskStatus.failed,
      errorMessage: error,
      completedAt: DateTime.now(),
    );
    await TaskDatabase.updateTask(failed);
    _emitUpdate(failed);
    logInfo(
      'Task set to failed',
      correlationId: correlationId,
      taskId: failed.id,
    );
    return failed;
  }

  Task _addProgressLog(Task task, String message) {
    return task.copyWith(
      stepsLog: [
        ...task.stepsLog,
        TaskStepLog(
          stepIndex: task.stepCount,
          action: '📊 تحديث تقدم: $message',
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  void _emitUpdate(Task task) {
    _eventController.add(TaskUpdatedEvent(task));
  }

  bool _isBrowserTool(String name) =>
      name == 'browse_url' || name == 'click_element' || name == 'fill_input';

  String _browserActionLabel(String toolName) {
    switch (toolName) {
      case 'browse_url':
        return 'يفتح';
      case 'click_element':
        return 'ينقر على';
      case 'fill_input':
        return 'يملأ حقل';
      default:
        return toolName;
    }
  }

  /// يستخدم UnifiedInterceptor للكشف عن حلقة الوعود وحقن رسائل الاسترداد
  /// يرجع true إذا تم حقن رسائل الاسترداد ويجب المتابعة (conitnue)
  bool _checkAndInjectPromiseRecovery(
    List<ChatMessage> history, {
    required int promiseRecoveryAttempt,
    required String assistantMsgId,
    required String assistantContent,
    required List<ToolCallInfo> toolCalls,
  }) {
    final correlationId = _uuid.v4().substring(0, 8);
    final interception = UnifiedInterceptor.intercept(
      conversationHistory: history,
      assistantMessage: ChatMessage(
        id: assistantMsgId,
        role: MessageRole.assistant,
        content: assistantContent,
        timestamp: DateTime.now(),
        toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
      ),
      toolCalls: toolCalls,
      promiseRecoveryAttempt: promiseRecoveryAttempt,
      timing: InterceptionTiming.postAssistantTurn,
    );

    if (!interception.isIntercepted) {
      logDebug(
        'UnifiedInterceptor: no interception',
        correlationId: correlationId,
        meta: {'promiseRecoveryAttempt': promiseRecoveryAttempt},
      );
      return false;
    }

    logInfo(
      'UnifiedInterceptor triggered',
      correlationId: correlationId,
      meta: {
        'promiseRecoveryAttempt': promiseRecoveryAttempt,
        'action': interception.action.name,
        'debugInfo': interception.debugInfo,
        'consecutiveCount': interception.consecutiveCount,
        'shouldInjectSystemTurn': interception.shouldInjectSystemTurn,
        'shouldInjectRecoveryUserMessage':
            interception.shouldInjectRecoveryUserMessage,
      },
    );

    // تطبيق الاعتراض على التاريخ — نص الاستبدال حسب نوع الاعتراض
    final interceptedMessages = UnifiedInterceptor.applyInterception(
      currentMessages: history,
      result: interception,
      assistantMsgId: assistantMsgId,
      interceptedAssistantStub:
          interception.action == ExecutionPromiseGuardAction.interceptAndRecover
          ? ExecutionPromiseGuard.interceptedAssistantStub
          : ExecutionPromiseGuard.interceptedAssistantNoticeOnlyStub,
    );

    // نسخ الرسائل المحقونة للـ history (مرجع القائمة)
    history.clear();
    history.addAll(interceptedMessages);

    // نعيد true فقط إذا كان هناك استرداد (يجب المتابعة في الحلقة)
    final shouldContinue =
        interception.action == ExecutionPromiseGuardAction.interceptAndRecover;
    logDebug(
      'UnifiedInterceptor: applied interception',
      correlationId: correlationId,
      meta: {
        'shouldContinue': shouldContinue,
        'newHistoryLength': history.length,
      },
    );
    return shouldContinue;
  }

  String _truncate(String s, int maxLen) =>
      s.length > maxLen ? '${s.substring(0, maxLen)}...' : s;

  String _autonomousInstructions(Task task) =>
      '''

[وضع التنفيذ المستقل — تعليمات ملزمة]
أنت تعمل في وضع الوكيل المستقل. هدفك: "${task.goal}"
- نفّذ الخطوات بنفسك دون انتظار أي إدخال من المستخدم بين الخطوات.
- عند إتمام الهدف الكامل: استدعِ `complete_task` مع تقرير شامل.
- عند احتياج معلومة ضرورية ناقصة فعلاً: استدعِ `ask_user` مع سؤال واضح ومحدد.
- لتحديث المستخدم أثناء العمل (اختياري): استدعِ `report_progress`.
- لا تُنهِ ردك بنص مجرد دون استدعاء أداة — كل دورة يجب أن تنتهي بأداة.
- الخطوات المستهلكة: ${task.stepCount} من ${task.stepCap}.
''';

  String _subTaskInstructions(Task task, SubTask subTask) =>
      '''

[وضع التنفيذ المستقل — مهمة فرعية ${subTask.index + 1}]
أنت تنفذ مهمة فرعية واحدة ضمن هدف أكبر.
الهدف الأصلي: "${task.goal}"
مهمتك الفرعية الحالية: "${subTask.description}"

تعليمات إلزامية:
- ركّز فقط على هذه المهمة الفرعية تحديداً.
- إصلاح 02: عند إتمام المهمة الفرعية أنهِ فوراً بملخص نصي موجز لما
  أنجزته، دون استدعاء أي أداة في ردك الأخير — النص الخالص دون أدوات
  هو إشارة الاكتمال الرسمية لهذه المهمة الفرعية.
- لا تستدعِ `complete_task` هنا — إتمام الهدف الكامل يُدار تلقائياً بعد
  اكتمال جميع المهام الفرعية، واستدعاؤها هنا يُعامل كمهمة فرعية منتهية
  فقط ويتجاهل بقية الخطة فلا تكملها.
- إذا احتجت معلومة ضرورية ناقصة: استدعِ `ask_user`.
- لتحديث المستخدم أثناء العمل (اختياري): استدعِ `report_progress`.
''';

  void dispose() {
    _eventController.close();
  }
}

/// نتيجة تنفيذ مهمة فرعية واحدة
class _SubTaskResult {
  /// إذا صحّ: تلقّت الحلقة إشارة إنهاء للمهمة كاملة — فقط ask_user
  /// (إيقاف بانتظار رد المستخدم) أو الإلغاء.
  /// **إصلاح 02:** complete_task داخل خطة لم تعد إشارة طرفية — إنها
  /// مهمة فرعية منتهية فقط (كانت تُنهي الخطة كلها بعد أول مهمة فرعية).
  final bool wasTerminalSignal;

  /// ملخص ما أُنجز في هذه المهمة الفرعية
  final String summary;

  const _SubTaskResult({
    required this.wasTerminalSignal,
    required this.summary,
  });
}

/// فشل خطوة فرعية غير قابل لإعادة المحاولة — يُفشل فوراً دون إهدار محاولات
/// backoff على أخطاء لن تُحل بإعادة الطلب نفسه (HTTP 400، مفتاح مفقود،
/// رد فارغ بعد توجيه النتيجة، تجاوز سقف التكرارات...).
class _NonRetryableSubTaskFailure implements Exception {
  final String message;
  const _NonRetryableSubTaskFailure(this.message);

  @override
  String toString() => message;
}
