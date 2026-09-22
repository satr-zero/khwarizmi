import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:khwarizmi/core/security/browser_security_interceptor.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/core/services/agent_identity_service.dart';
import 'package:khwarizmi/features/agent/data/task_database.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/memory/data/memory_repository.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:khwarizmi/features/scheduler/services/notification_service.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
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

  const TaskExecutionCallbacks({
    this.onToolCall,
    this.onToolResult,
    this.onTextChunk,
    this.onAskUser,
    this.onComplete,
    this.onProgress,
    this.onTaskUpdated,
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
class TaskExecutionEngine {
  static final TaskExecutionEngine instance = TaskExecutionEngine._();
  TaskExecutionEngine._();

  static const _uuid = Uuid();

  /// الحد الأقصى الافتراضي للخطوات المستقلة لكل مهمة
  static const int defaultStepCap = 25;

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
      final runningTasks = await TaskDatabase.getTasksByStatus(TaskStatus.running);
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
        debugPrint('[TaskExecutionEngine] Recovered ${runningTasks.length} interrupted task(s).');
      }
    } catch (e) {
      debugPrint('[TaskExecutionEngine] recoverInterruptedTasks error: $e');
    }
  }

  /// يبدأ مهمة مستقلة جديدة.
  /// يرجع [Task] المنشأة فوراً — الحلقة تعمل بالخلفية.
  Future<Task> startTask({
    required String goal,
    int stepCap = defaultStepCap,
    TaskExecutionCallbacks? callbacks,
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
    _runLoop(task, apiKey ?? '', callbacks: callbacks);

    return task;
  }

  /// يستأنف مهمة في حالة [TaskStatus.waitingForUser] برد المستخدم.
  Future<void> resumeTask(
    String taskId,
    String userReply, {
    TaskExecutionCallbacks? callbacks,
  }) async {
    final task = await TaskDatabase.getTaskById(taskId);
    if (task == null || task.status != TaskStatus.waitingForUser) return;

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

  Future<void> _runLoop(
    Task task,
    String apiKey, {
    String? userReplyInjection,
    TaskExecutionCallbacks? callbacks,
  }) async {
    final canceller = Completer<void>();
    _cancellationCompleters[task.id] = canceller;
    _cancelledTasks.remove(task.id);

    var currentTask = task;

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
        }
      } catch (_) {}

      // تعليمات الوكيل المستقل
      effectiveSystem += _autonomousInstructions(currentTask);

      // حقن الفهرس الخفيف للمهارات النصية الإرشادية
      try {
        final textSkillsIndex = await TextSkillService.instance.getLightweightIndexPrompt();
        if (textSkillsIndex.isNotEmpty) {
          effectiveSystem += '\n\n$textSkillsIndex\n';
        }
      } catch (_) {}

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

      // ─── الحلقة الرئيسية ──────────────────────────────────────────────
      while (true) {
        // فحص الإلغاء
        if (_cancelledTasks[currentTask.id] == true) break;

        // فحص السقف — الأهم بعد الأمان
        if (currentTask.stepCount >= currentTask.stepCap) {
          currentTask = await _pauseAtLimit(currentTask);
          callbacks?.onTaskUpdated?.call(currentTask);
          break;
        }

        final provider = ProviderRegistry.getProvider(currentTask.providerId);
        final availableTools = ToolRegistry.getAutonomousDefinitions();

        // استدعاء النموذج
        final List<ToolCallInfo> toolCalls = [];
        var assistantText = '';

        try {
          final stream = provider.sendMessage(
            history: history,
            availableTools: availableTools,
            systemPrompt: effectiveSystem,
            apiKey: apiKey,
            modelName: currentTask.modelName,
          );

          await for (final event in stream) {
            if (_cancelledTasks[currentTask.id] == true) break;
            if (event is AgentTextChunk) {
              assistantText += event.text;
              callbacks?.onTextChunk?.call(event.text);
            } else if (event is AgentToolCallEvent) {
              toolCalls.add(event.toolCall);
              callbacks?.onToolCall?.call(event.toolCall);
            } else if (event is AgentErrorEvent) {
              currentTask = await _failTask(currentTask, event.message);
              callbacks?.onTaskUpdated?.call(currentTask);
              return;
            }
          }
        } catch (e) {
          currentTask = await _failTask(currentTask, e.toString());
          callbacks?.onTaskUpdated?.call(currentTask);
          return;
        }

        if (_cancelledTasks[currentTask.id] == true) break;

        // أضف رد المساعد للتاريخ
        history.add(ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: assistantText,
          timestamp: DateTime.now(),
          toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
        ));

        // ─── لا أدوات = إجابة نصية مباشرة = لا يجوز بالمهام المستقلة ──
        if (toolCalls.isEmpty) {
          // إن رجع نصاً بدون أداة، نعتبره إتماماً ضمنياً
          currentTask = await _completeTask(currentTask, assistantText);
          callbacks?.onComplete?.call(assistantText);
          callbacks?.onTaskUpdated?.call(currentTask);
          break;
        }

        // ─── تنفيذ الأدوات ────────────────────────────────────────────
        bool shouldBreak = false;

        for (final toolCall in toolCalls) {
          if (_cancelledTasks[currentTask.id] == true) break;

          // ─ فحص أدوات التحكم أولاً ─────────────────────────────────
          if (toolCall.toolName == 'complete_task') {
            final summary = toolCall.arguments['summary'] as String? ?? assistantText;
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
            history.add(ChatMessage(
              id: _uuid.v4(),
              role: MessageRole.tool,
              content: jsonEncode({'status': 'progress_reported', 'message': message}),
              timestamp: DateTime.now(),
              toolCallId: toolCall.callId,
            ));
            continue;
          }

          // ─ تنفيذ أداة عادية ──────────────────────────────────────
          if (_isBrowserTool(toolCall.toolName)) {
            _eventController.add(TaskBrowserActionEvent(
              '${_browserActionLabel(toolCall.toolName)}: '
              '${toolCall.arguments['url'] ?? toolCall.arguments['selector'] ?? ''}',
            ));
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
              resultJson = await ToolRegistry.executeTool(
                toolCall.toolName,
                toolCall.arguments,
              );
            }

            // إن صدر حاجز أمان → ask_user للمستخدم يرى الصفحة
            if (resultJson.contains('"isBlocked":true')) {
              final blocked = jsonDecode(resultJson) as Map<String, dynamic>;
              final question = '🔒 تأكيد مطلوب: ${blocked['reason'] ?? 'إجراء مالي يستلزم موافقتك الصريحة. هل تريد المتابعة؟'}';
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

          history.add(ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.tool,
            content: resultJson,
            timestamp: DateTime.now(),
            toolCallId: toolCall.callId,
          ));

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
      debugPrint('[TaskExecutionEngine] Unhandled error in task ${task.id}: $e\n$st');
      currentTask = await _failTask(currentTask, e.toString());
      callbacks?.onTaskUpdated?.call(currentTask);
    } finally {
      _cancellationCompleters.remove(task.id);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Task> _completeTask(Task task, String summary) async {
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
    return completed;
  }

  Future<Task> _askUser(Task task, String question) async {
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
    return waiting;
  }

  Future<Task> _pauseAtLimit(Task task) async {
    final paused = task.copyWith(status: TaskStatus.pausedAtLimit);
    await TaskDatabase.updateTask(paused);
    _emitUpdate(paused);

    await NotificationService.showNotification(
      identifier: 'task_limit_${task.id}',
      title: '⏸️ خوارزمي: وصلت للحد الأقصى للخطوات',
      body: 'المهمة "${_truncate(task.goal, 60)}" وصلت لـ ${task.stepCap} خطوة — موافقتك مطلوبة للاستمرار.',
    );
    return paused;
  }

  Future<Task> _failTask(Task task, String error) async {
    final failed = task.copyWith(
      status: TaskStatus.failed,
      errorMessage: error,
      completedAt: DateTime.now(),
    );
    await TaskDatabase.updateTask(failed);
    _emitUpdate(failed);
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
      case 'browse_url': return 'يفتح';
      case 'click_element': return 'ينقر على';
      case 'fill_input': return 'يملأ حقل';
      default: return toolName;
    }
  }

  String _truncate(String s, int maxLen) =>
      s.length > maxLen ? '${s.substring(0, maxLen)}...' : s;

  String _autonomousInstructions(Task task) => '''

[وضع التنفيذ المستقل — تعليمات ملزمة]
أنت تعمل في وضع الوكيل المستقل. هدفك: "${task.goal}"
- نفّذ الخطوات بنفسك دون انتظار أي إدخال من المستخدم بين الخطوات.
- عند إتمام الهدف الكامل: استدعِ `complete_task` مع تقرير شامل.
- عند احتياج معلومة ضرورية ناقصة فعلاً: استدعِ `ask_user` مع سؤال واضح ومحدد.
- لتحديث المستخدم أثناء العمل (اختياري): استدعِ `report_progress`.
- لا تُنهِ ردك بنص مجرد دون استدعاء أداة — كل دورة يجب أن تنتهي بأداة.
- الخطوات المستهلكة: ${task.stepCount} من ${task.stepCap}.
''';

  void dispose() {
    _eventController.close();
  }
}
