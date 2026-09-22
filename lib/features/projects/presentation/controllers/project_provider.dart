import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/features/projects/domain/entities/pending_file_change.dart';
import 'package:khwarizmi/features/projects/domain/entities/project.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class ProjectState {
  /// المشروع النشط حاليًا (null = لا يوجد مشروع مفتوح).
  final Project? activeProject;

  /// قائمة التعديلات المعلَّقة بانتظار الموافقة.
  final List<PendingFileChange> pendingChanges;

  /// ناتج الترمينال التراكمي (للعرض في لوحة الترمينال).
  final List<TerminalLine> terminalOutput;

  /// هل يتم تنفيذ أمر حاليًا؟
  final bool isRunningCommand;

  /// آخر exit code بعد انتهاء أمر.
  final int? lastExitCode;

  /// المشاريع الأخيرة.
  final List<Project> recentProjects;

  /// هل لوحة الترمينال مفتوحة يدويًا من المستخدم؟
  final bool isTerminalPanelVisible;

  const ProjectState({
    this.activeProject,
    this.pendingChanges = const [],
    this.terminalOutput = const [],
    this.isRunningCommand = false,
    this.lastExitCode,
    this.recentProjects = const [],
    this.isTerminalPanelVisible = false,
  });

  ProjectState copyWith({
    Project? activeProject,
    bool clearActiveProject = false,
    List<PendingFileChange>? pendingChanges,
    List<TerminalLine>? terminalOutput,
    bool? isRunningCommand,
    int? lastExitCode,
    bool clearLastExitCode = false,
    List<Project>? recentProjects,
    bool? isTerminalPanelVisible,
  }) {
    return ProjectState(
      activeProject: clearActiveProject ? null : (activeProject ?? this.activeProject),
      pendingChanges: pendingChanges ?? this.pendingChanges,
      terminalOutput: terminalOutput ?? this.terminalOutput,
      isRunningCommand: isRunningCommand ?? this.isRunningCommand,
      lastExitCode: clearLastExitCode ? null : (lastExitCode ?? this.lastExitCode),
      recentProjects: recentProjects ?? this.recentProjects,
      isTerminalPanelVisible: isTerminalPanelVisible ?? this.isTerminalPanelVisible,
    );
  }
}

/// سطر واحد في ناتج الترمينال.
class TerminalLine {
  final String content;
  final bool isStderr;
  final DateTime timestamp;

  const TerminalLine({
    required this.content,
    this.isStderr = false,
    required this.timestamp,
  });
}

// ── StateNotifier ─────────────────────────────────────────────────────────────

class ProjectController extends StateNotifier<ProjectState> {
  StreamSubscription<ProjectEvent>? _sub;

  ProjectController() : super(const ProjectState()) {
    _listenToManager();
    _loadRecentProjects();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listenToManager() {
    _sub = ProjectManager.instance.eventStream.listen((event) {
      if (event is ProjectChangedEvent) {
        if (event.project == null) {
          state = state.copyWith(
            clearActiveProject: true,
            pendingChanges: [],
            terminalOutput: [],
            clearLastExitCode: true,
            isRunningCommand: false,
          );
        } else {
          state = state.copyWith(activeProject: event.project);
          _loadRecentProjects();
        }
      } else if (event is PendingChangeAddedEvent) {
        state = state.copyWith(
          pendingChanges: [...state.pendingChanges, event.change],
        );
      } else if (event is PendingChangeResolvedEvent) {
        state = state.copyWith(
          pendingChanges: state.pendingChanges
              .where((c) => c.id != event.changeId)
              .toList(),
        );
      } else if (event is TerminalOutputEvent) {
        // إلحاق الناتج الحي
        final newLines = List<TerminalLine>.from(state.terminalOutput)
          ..add(TerminalLine(
            content: event.chunk,
            isStderr: event.isStderr,
            timestamp: DateTime.now(),
          ));
        // حد أقصى 2000 سطر للأداء
        final trimmed = newLines.length > 2000
            ? newLines.sublist(newLines.length - 2000)
            : newLines;
        state = state.copyWith(
          terminalOutput: trimmed,
          isRunningCommand: true,
        );
      } else if (event is TerminalCommandFinishedEvent) {
        state = state.copyWith(
          isRunningCommand: false,
          lastExitCode: event.exitCode,
        );
      }
    });
  }

  Future<void> _loadRecentProjects() async {
    try {
      final recent = await ProjectManager.instance.getRecentProjects();
      state = state.copyWith(recentProjects: recent);
    } catch (_) {}
  }

  // ── Public Actions ────────────────────────────────────────────────────────

  Future<void> openProject(String rootPath) async {
    // مسح الترمينال عند فتح مشروع جديد
    state = state.copyWith(
      terminalOutput: [],
      pendingChanges: [],
      clearLastExitCode: true,
    );
    await ProjectManager.instance.openProject(rootPath);
  }

  void closeProject() {
    ProjectManager.instance.closeProject();
  }

  void applyChange(String changeId) {
    ProjectManager.instance.applyChange(changeId);
  }

  void rejectChange(String changeId) {
    ProjectManager.instance.rejectChange(changeId);
  }

  void applyAllChanges() {
    ProjectManager.instance.applyAllChanges();
  }

  void clearTerminal() {
    state = state.copyWith(terminalOutput: [], clearLastExitCode: true);
  }

  void toggleTerminalPanel([bool? visible]) {
    state = state.copyWith(
      isTerminalPanelVisible: visible ?? !state.isTerminalPanelVisible,
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final projectProvider =
    StateNotifierProvider<ProjectController, ProjectState>((ref) {
  return ProjectController();
});

final activeProjectProvider = Provider<Project?>((ref) {
  return ref.watch(projectProvider).activeProject;
});

final pendingChangesProvider = Provider<List<PendingFileChange>>((ref) {
  return ref.watch(projectProvider).pendingChanges;
});

final showTerminalPanelProvider = Provider<bool>((ref) {
  final state = ref.watch(projectProvider);
  // عرض اللوحة عند وجود مشروع نشط وناتج ترمينال أو تم فتحها صراحة
  return state.activeProject != null &&
      (state.isTerminalPanelVisible ||
          state.isRunningCommand ||
          state.terminalOutput.isNotEmpty);
});
