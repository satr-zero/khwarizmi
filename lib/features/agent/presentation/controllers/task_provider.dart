import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/features/agent/data/task_database.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/services/task_execution_engine.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class TasksState {
  final List<Task> tasks;
  final bool isStarting; // جارٍ إنشاء مهمة جديدة
  final String? lastBrowserAction; // آخر إجراء متصفح (للوحة الحية)
  final bool showBrowserPanel;

  const TasksState({
    this.tasks = const [],
    this.isStarting = false,
    this.lastBrowserAction,
    this.showBrowserPanel = false,
  });

  List<Task> get activeTasks => tasks
      .where((t) =>
          t.status == TaskStatus.running ||
          t.status == TaskStatus.waitingForUser ||
          t.status == TaskStatus.pausedAtLimit)
      .toList();

  List<Task> get completedTasks => tasks
      .where((t) =>
          t.status == TaskStatus.completed ||
          t.status == TaskStatus.failed ||
          t.status == TaskStatus.cancelled)
      .toList();

  bool get hasBrowserTask => activeTasks.any((t) => t.stepsLog
      .any((s) => s.toolName != null && _isBrowserTool(s.toolName!)));

  static bool _isBrowserTool(String name) =>
      name == 'browse_url' || name == 'click_element' || name == 'fill_input';

  TasksState copyWith({
    List<Task>? tasks,
    bool? isStarting,
    String? lastBrowserAction,
    bool? showBrowserPanel,
    bool clearBrowserAction = false,
  }) {
    return TasksState(
      tasks: tasks ?? this.tasks,
      isStarting: isStarting ?? this.isStarting,
      lastBrowserAction: clearBrowserAction ? null : (lastBrowserAction ?? this.lastBrowserAction),
      showBrowserPanel: showBrowserPanel ?? this.showBrowserPanel,
    );
  }
}

// ── StateNotifier ─────────────────────────────────────────────────────────────

class TasksController extends StateNotifier<TasksState> {
  StreamSubscription? _engineSub;

  TasksController() : super(const TasksState()) {
    _loadPersistedTasks();
    _listenToEngine();
  }

  @override
  void dispose() {
    _engineSub?.cancel();
    super.dispose();
  }

  // ── Initialization ────────────────────────────────────────────────────────

  Future<void> _loadPersistedTasks() async {
    try {
      final all = await TaskDatabase.getAllTasks();
      state = state.copyWith(tasks: all);

      // استأنف أي مهام كانت تعمل (running) قبل إغلاق التطبيق
      // ملاحظة: running → pausedAtLimit عند الاسترداد للسلامة
      for (final task in all) {
        if (task.status == TaskStatus.running) {
          final paused = task.copyWith(status: TaskStatus.pausedAtLimit);
          await TaskDatabase.updateTask(paused);
          _updateTaskInState(paused);
        }
      }
    } catch (e) {
      // DB ربما لم تُهيأ بعد
    }
  }

  void _listenToEngine() {
    _engineSub = TaskExecutionEngine.instance.eventStream.listen((event) {
      if (event is TaskUpdatedEvent) {
        _updateTaskInState(event.task);

        // إظهار لوحة المتصفح تلقائياً إن استُخدمت أداة متصفح
        if (_isBrowserStep(event.task)) {
          if (!state.showBrowserPanel) {
            state = state.copyWith(showBrowserPanel: true);
          }
        }
      } else if (event is TaskBrowserActionEvent) {
        state = state.copyWith(lastBrowserAction: event.action);
      }
    });
  }

  bool _isBrowserStep(Task task) {
    if (task.stepsLog.isEmpty) return false;
    final last = task.stepsLog.last;
    return last.toolName == 'browse_url' ||
        last.toolName == 'scroll_page' ||
        last.toolName == 'inspect_visual_page' ||
        last.toolName == 'click_element' ||
        last.toolName == 'fill_input' ||
        last.toolName == 'download_file';
  }

  // ── Public Actions ────────────────────────────────────────────────────────

  Future<void> startTask(String goal) async {
    if (goal.trim().isEmpty) return;
    state = state.copyWith(isStarting: true);
    try {
      final task = await TaskExecutionEngine.instance.startTask(goal: goal.trim());
      final updated = List<Task>.from(state.tasks)..insert(0, task);
      state = state.copyWith(tasks: updated, isStarting: false);
    } catch (e) {
      state = state.copyWith(isStarting: false);
    }
  }

  Future<void> resumeTask(String taskId, String userReply) async {
    await TaskExecutionEngine.instance.resumeTask(taskId, userReply);
  }

  Future<void> extendTask(String taskId) async {
    await TaskExecutionEngine.instance.extendTask(taskId);
  }

  Future<void> cancelTask(String taskId) async {
    await TaskExecutionEngine.instance.cancelTask(taskId);
  }

  void toggleBrowserPanel() {
    state = state.copyWith(showBrowserPanel: !state.showBrowserPanel);
  }

  void setBrowserPanelVisible(bool visible, {String? lastAction}) {
    state = state.copyWith(
      showBrowserPanel: visible,
      lastBrowserAction: lastAction ?? state.lastBrowserAction,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _updateTaskInState(Task task) {
    final index = state.tasks.indexWhere((t) => t.id == task.id);
    if (index == -1) {
      state = state.copyWith(tasks: [task, ...state.tasks]);
    } else {
      final updated = List<Task>.from(state.tasks);
      updated[index] = task;
      state = state.copyWith(tasks: updated);
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final tasksProvider =
    StateNotifierProvider<TasksController, TasksState>((ref) {
  return TasksController();
});

final activeTasksProvider = Provider<List<Task>>((ref) {
  return ref.watch(tasksProvider).activeTasks;
});

final showBrowserPanelProvider = Provider<bool>((ref) {
  return ref.watch(tasksProvider).showBrowserPanel;
});

final lastBrowserActionProvider = Provider<String?>((ref) {
  return ref.watch(tasksProvider).lastBrowserAction;
});
