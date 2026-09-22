import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/projects/data/project_database.dart';
import 'package:khwarizmi/features/projects/domain/entities/pending_file_change.dart';
import 'package:khwarizmi/features/projects/domain/entities/project.dart';
import 'package:khwarizmi/features/projects/services/diff_service.dart';
import 'package:khwarizmi/features/projects/services/project_file_service.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// حدث صادر من [ProjectManager] للواجهة.
abstract class ProjectEvent {
  const ProjectEvent();
}

class ProjectChangedEvent extends ProjectEvent {
  final Project? project;
  const ProjectChangedEvent(this.project);
}

class PendingChangeAddedEvent extends ProjectEvent {
  final PendingFileChange change;
  const PendingChangeAddedEvent(this.change);
}

class PendingChangeResolvedEvent extends ProjectEvent {
  final String changeId;
  final bool applied;
  const PendingChangeResolvedEvent(this.changeId, {required this.applied});
}

class TerminalOutputEvent extends ProjectEvent {
  final String chunk;
  final bool isStderr;
  const TerminalOutputEvent(this.chunk, {this.isStderr = false});
}

class TerminalCommandFinishedEvent extends ProjectEvent {
  final int exitCode;
  const TerminalCommandFinishedEvent(this.exitCode);
}

/// حدث طلب تأكيد أمر ترمينال خطر من المستخدم.
class TerminalSecurityConfirmationEvent extends ProjectEvent {
  final String command;
  final String reason;
  final String category;
  final void Function(bool approved) onDecision;

  const TerminalSecurityConfirmationEvent({
    required this.command,
    required this.reason,
    required this.category,
    required this.onDecision,
  });
}

/// مدير المشاريع النشطة — Singleton مركزي للمرحلة 9.
///
/// - يُدير المشروع النشط الحالي
/// - يُدير قائمة التعديلات المعلَّقة (PendingFileChange)
/// - يُنفّذ أوامر الترمينال ويبث ناتجها حيًا
/// - يتواصل مع الواجهة عبر [eventStream]
class ProjectManager {
  static final ProjectManager instance = ProjectManager._();
  ProjectManager._();

  static const _uuid = Uuid();

  // ── State ──────────────────────────────────────────────────────────────────

  Project? _activeProject;
  Project? get activeProject => _activeProject;

  String? _cachedProjectMap;
  String? get cachedProjectMap => _cachedProjectMap;

  final List<PendingFileChange> _pendingChanges = [];
  List<PendingFileChange> get pendingChanges => List.unmodifiable(_pendingChanges);

  Process? _activeProcess;
  bool get isRunningCommand => _activeProcess != null;

  // ── Events ─────────────────────────────────────────────────────────────────

  final _eventController = StreamController<ProjectEvent>.broadcast();
  Stream<ProjectEvent> get eventStream => _eventController.stream;

  void _emit(ProjectEvent event) => _eventController.add(event);

  /// يُصدر حدثًا عامًا — يُستخدم من أدوات النموذج لطلب تأكيد ترمينال.
  void emitEvent(ProjectEvent event) => _emit(event);

  // ── Project Management ────────────────────────────────────────────────────

  /// يفتح مجلدًا كمشروع نشط.
  ///
  /// - يُنشئ/يُحدّث سجل المشروع في قاعدة البيانات
  /// - يُرجع [Project] المحدّث
  Future<Project> openProject(String rootPath) async {
    final name = p.basename(rootPath);
    final project = await ProjectDatabase.upsertProject(
      rootPath: rootPath,
      name: name,
    );
    _activeProject = project;
    // توليد أو جلب خريطة المشروع
    unawaited(getProjectMap().catchError((e) {
      debugPrint('[ProjectManager] Failed to build project map on open: $e');
      return null;
    }));
    _emit(ProjectChangedEvent(project));
    debugPrint('[ProjectManager] Opened project: ${project.name} @ ${project.rootPath}');
    return project;
  }

  /// يُغلق المشروع النشط الحالي.
  void closeProject() {
    _activeProject = null;
    _cachedProjectMap = null;
    _pendingChanges.clear();
    _emit(const ProjectChangedEvent(null));
  }

  /// يربط محادثة بالمشروع النشط الحالي.
  Future<void> linkToConversation(String conversationId) async {
    final project = _activeProject;
    if (project == null) return;
    await ProjectDatabase.linkConversationToProject(conversationId, project.id);
  }

  /// يسترد المشروع المرتبط بمحادثة ويُعيّنه نشطًا.
  Future<Project?> restoreProjectForConversation(String conversationId) async {
    final project = await ProjectDatabase.getProjectForConversation(conversationId);
    if (project == null) return null;

    // تحقق أن المجلد لا يزال موجودًا
    if (!await Directory(project.rootPath).exists()) {
      debugPrint('[ProjectManager] Project folder not found: ${project.rootPath}');
      return null;
    }

    _activeProject = project;
    _cachedProjectMap = await ProjectDatabase.getProjectMap(project.id);
    _emit(ProjectChangedEvent(project));
    return project;
  }

  /// يرجع المشاريع الأخيرة من قاعدة البيانات.
  Future<List<Project>> getRecentProjects() => ProjectDatabase.getRecentProjects();

  // ── Pending Changes ───────────────────────────────────────────────────────

  /// يُنشئ تعديلًا معلَّقًا من اقتراح النموذج.
  ///
  /// - يتحقق من المسار
  /// - يقرأ المحتوى الحالي
  /// - يحسب الـ Diff
  /// - يُبلّغ الواجهة
  ///
  /// يُرجع JSON: `{"change_id": "..."}` أو `{"error": "..."}`.
  Future<String> proposePendingChange({
    required String path,
    required String newContent,
  }) async {
    final project = _activeProject;
    if (project == null) {
      return jsonEncode({'error': 'لا يوجد مشروع نشط. افتح مجلد مشروع أولاً.'});
    }

    final validation = ProjectFileService.resolveAndValidatePath(project, path);
    if (validation is InvalidPath) {
      return jsonEncode({'error': validation.reason});
    }

    final absolutePath = (validation as ValidPath).absolutePath;

    // قراءة المحتوى الحالي (null إن كان ملفًا جديدًا)
    final existingContent = await ProjectFileService.readRawContent(project, absolutePath);

    // حساب الـ Diff
    final diffLines = DiffService.computeDiff(
      oldText: existingContent,
      newText: newContent,
    );

    final change = PendingFileChange(
      id: _uuid.v4(),
      absolutePath: absolutePath,
      existingContent: existingContent,
      proposedContent: newContent,
      diffLines: diffLines,
      createdAt: DateTime.now(),
    );

    _pendingChanges.add(change);
    _emit(PendingChangeAddedEvent(change));

    return jsonEncode({'change_id': change.id, 'file': absolutePath});
  }

  /// ينتظر قرار المستخدم (موافقة/رفض) على تعديل معلَّق.
  ///
  /// يُرجع `true` عند الموافقة، و `false` عند الرفض أو انتهاء المهلة (الافتراضي 30 ثانية لتفادي التعليق).
  Future<bool> waitForChangeDecision(
    String changeId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<bool>();
    _pendingDecisions[changeId] = completer;

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingDecisions.remove(changeId);
          // مهلة منتهية — رفض تلقائي لتفادي التعليق غير المنتهي
          _pendingChanges.removeWhere((c) => c.id == changeId);
          _emit(PendingChangeResolvedEvent(changeId, applied: false));
          return false;
        },
      );
    } catch (_) {
      _pendingDecisions.remove(changeId);
      return false;
    }
  }

  final Map<String, Completer<bool>> _pendingDecisions = {};

  /// يُطبّق تعديلًا معلَّقًا (كتابة على القرص).
  Future<void> applyChange(String changeId) async {
    final project = _activeProject;
    if (project == null) return;

    final idx = _pendingChanges.indexWhere((c) => c.id == changeId);
    if (idx == -1) return;

    final change = _pendingChanges[idx];
    _pendingChanges.removeAt(idx);

    await ProjectFileService.writeProjectFile(
      project,
      change.absolutePath,
      change.proposedContent,
    );

    _emit(PendingChangeResolvedEvent(changeId, applied: true));
    _pendingDecisions[changeId]?.complete(true);
    _pendingDecisions.remove(changeId);
  }

  /// يرفض تعديلًا معلَّقًا (لا يُكتب شيء على القرص).
  void rejectChange(String changeId) {
    _pendingChanges.removeWhere((c) => c.id == changeId);
    _emit(PendingChangeResolvedEvent(changeId, applied: false));
    _pendingDecisions[changeId]?.complete(false);
    _pendingDecisions.remove(changeId);
  }

  /// يُطبّق جميع التعديلات المعلَّقة دفعةً واحدة (تطبيق الكل).
  Future<void> applyAllChanges() async {
    final ids = _pendingChanges.map((c) => c.id).toList();
    for (final id in ids) {
      await applyChange(id);
    }
  }

  // ── Terminal Execution ────────────────────────────────────────────────────

  /// يُنفّذ أمر PowerShell في مجلد المشروع النشط.
  ///
  /// يبث الناتج (stdout/stderr) حيًا عبر [eventStream].
  /// مهلة قصوى: 120 ثانية.
  ///
  /// يُرجع JSON: `{"exit_code": 0, "output": "..."}` أو `{"error": "..."}`.
  Future<String> runTerminalCommand(String command) async {
    final project = _activeProject;
    if (project == null) {
      return jsonEncode({'error': 'لا يوجد مشروع نشط.'});
    }

    if (_activeProcess != null) {
      return jsonEncode({'error': 'يوجد أمر آخر قيد التنفيذ. انتظر اكتماله أولاً.'});
    }

    final output = StringBuffer();

    try {
      debugPrint('[ProjectManager] Running: $command');

      _activeProcess = await Process.start(
        'powershell.exe',
        ['-NoProfile', '-Command', command],
        workingDirectory: project.rootPath,
        runInShell: false,
      );

      final process = _activeProcess!;

      // بث stdout حيًا
      process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
        output.write(chunk);
        _emit(TerminalOutputEvent(chunk));
      });

      // بث stderr حيًا
      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
        output.write(chunk);
        _emit(TerminalOutputEvent(chunk, isStderr: true));
      });

      // مهلة 120 ثانية
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          process.kill();
          _emit(const TerminalOutputEvent(
            '\n[خوارزمي] انتهت المهلة القصوى (120 ثانية) — أُنهي الأمر قسرًا.\n',
            isStderr: true,
          ));
          return -1;
        },
      );

      _activeProcess = null;
      _emit(TerminalCommandFinishedEvent(exitCode));

      return jsonEncode({
        'exit_code': exitCode,
        'output': output.toString(),
        'success': exitCode == 0,
      });
    } catch (e) {
      _activeProcess = null;
      debugPrint('[ProjectManager] runTerminalCommand error: $e');
      return jsonEncode({'error': 'فشل تنفيذ الأمر: $e'});
    }
  }

  // ── Project Map Generation ───────────────────────────────────────────────

  /// يسترجع خريطة المشروع المحفوظة أو يولدها تلقائيًا إن لم توجد.
  Future<String?> getProjectMap({bool forceRefresh = false}) async {
    final project = _activeProject;
    if (project == null) return null;

    if (!forceRefresh && _cachedProjectMap != null && _cachedProjectMap!.isNotEmpty) {
      debugPrint('[ProjectMap] ✅ Served from memory cache: ${_cachedProjectMap!.length} chars (project: ${project.name})');
      return _cachedProjectMap;
    }

    // محاولة الجلب من قاعدة البيانات
    final saved = await ProjectDatabase.getProjectMap(project.id);
    if (!forceRefresh && saved != null && saved.isNotEmpty) {
      _cachedProjectMap = saved;
      debugPrint('[ProjectMap] ✅ Served from DB: ${saved.length} chars (project: ${project.name})');
      return saved;
    }

    // توليد خريطة جديدة
    return await generateAndSaveProjectMap();
  }

  /// يولد خريطة ملخصة ومضغوطة للمشروع ويحفظها في قاعدة البيانات.
  Future<String> generateAndSaveProjectMap() async {
    final project = _activeProject;
    if (project == null) {
      throw StateError('لا يوجد مشروع نشط لتوليد الخريطة له.');
    }

    final rootDir = Directory(project.rootPath);
    if (!await rootDir.exists()) {
      throw StateError('مجلد المشروع غير موجود: ${project.rootPath}');
    }

    final buffer = StringBuffer();
    buffer.writeln('=== خريطة المشروع: ${project.name} ===');
    buffer.writeln('المسار: ${project.rootPath}');

    // فحص ملفات التكوين والاعتماديات
    final pubspec = File(p.join(project.rootPath, 'pubspec.yaml'));
    final packageJson = File(p.join(project.rootPath, 'package.json'));

    if (await pubspec.exists()) {
      try {
        final content = await pubspec.readAsString();
        buffer.writeln('نوع المشروع: Flutter / Dart');
        final lines = content.split('\n');
        final deps = <String>[];
        bool inDeps = false;
        for (final line in lines) {
          if (line.trim().startsWith('dependencies:')) {
            inDeps = true;
            continue;
          } else if (inDeps &&
              (line.startsWith('dev_dependencies:') ||
                  (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')))) {
            inDeps = false;
          }
          if (inDeps && line.trim().isNotEmpty && !line.trim().startsWith('#')) {
            deps.add(line.trim().split(':').first.trim());
          }
        }
        if (deps.isNotEmpty) {
          buffer.writeln('الحزم الأساسية: ${deps.take(15).join(', ')}');
        }
      } catch (_) {}
    } else if (await packageJson.exists()) {
      try {
        final json = jsonDecode(await packageJson.readAsString()) as Map<String, dynamic>;
        buffer.writeln('نوع المشروع: Node.js / Web');
        final deps = (json['dependencies'] as Map<String, dynamic>?)?.keys.toList() ?? [];
        if (deps.isNotEmpty) {
          buffer.writeln('الحزم الأساسية: ${deps.take(15).join(', ')}');
        }
      } catch (_) {}
    }

    buffer.writeln('\n## بنية الملفات والمجلدات:');
    final tree = await _scanDirectoryTree(rootDir, maxDepth: 2, maxChars: 6500);
    buffer.write(tree);

    final finalMap = buffer.toString();
    _cachedProjectMap = finalMap;
    await ProjectDatabase.saveProjectMap(project.id, finalMap);
    debugPrint('[ProjectMap] 🗺️ Generated & saved: ${finalMap.length} chars (~${(finalMap.length / 4).round()} tokens) for project: ${project.name}');
    debugPrint('[ProjectMap] --- PREVIEW (first 500 chars) ---');
    debugPrint(finalMap.substring(0, finalMap.length.clamp(0, 500)));
    debugPrint('[ProjectMap] --- END PREVIEW ---');
    return finalMap;
  }

  Future<String> _scanDirectoryTree(
    Directory rootDir, {
    required int maxDepth,
    required int maxChars,
  }) async {
    final buffer = StringBuffer();
    final ignoreNames = {
      '.git',
      '.dart_tool',
      'build',
      'node_modules',
      '.idea',
      '.vscode',
      '.gradle',
      'Pods',
      '.system_generated',
      'target',
      '.next',
      '.nuxt',
      'windows/flutter/ephemeral',
      'linux/flutter/ephemeral',
    };

    Future<void> walk(Directory dir, String prefix, int currentDepth) async {
      if (currentDepth > maxDepth || buffer.length >= maxChars) return;
      try {
        final entities = await dir.list().toList();
        entities.sort((a, b) {
          if (a is Directory && b is! Directory) return -1;
          if (a is! Directory && b is Directory) return 1;
          return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
        });

        for (int i = 0; i < entities.length; i++) {
          if (buffer.length >= maxChars) {
            buffer.writeln('$prefix... [تم اختصار بقية الملفات]');
            return;
          }
          final entity = entities[i];
          final name = p.basename(entity.path);
          if ((name.startsWith('.') && name != '.env') || ignoreNames.contains(name)) {
            continue;
          }

          final isLast = i == entities.length - 1;
          final connector = isLast ? '└── ' : '├── ';
          final childPrefix = prefix + (isLast ? '    ' : '│   ');

          if (entity is Directory) {
            buffer.writeln('$prefix$connector$name/');
            await walk(entity, childPrefix, currentDepth + 1);
          } else {
            buffer.writeln('$prefix$connector$name');
          }
        }
      } catch (_) {}
    }

    await walk(rootDir, '', 1);
    return buffer.toString();
  }

  void dispose() {
    _activeProcess?.kill();
    _activeProcess = null;
    _eventController.close();
  }
}
