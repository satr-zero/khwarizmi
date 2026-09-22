import 'dart:async';
import 'dart:convert';

import 'package:khwarizmi/core/security/terminal_security_interceptor.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/projects/domain/entities/project.dart';
import 'package:khwarizmi/features/projects/services/project_file_service.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Project? _getActiveProject() => ProjectManager.instance.activeProject;

String _noProjectError() => jsonEncode({
      'error':
          'لا يوجد مشروع نشط. استخدم زر "فتح مشروع" في الشريط الجانبي لاختيار مجلد مشروع أولاً.',
    });

// ══════════════════════════════════════════════════════════════════════════════
// propose_file_change
// ══════════════════════════════════════════════════════════════════════════════

/// اقتراح تعديل ملف — قلب آلية الـ Diff والموافقة.
///
/// **لا تكتب على القرص مباشرةً أبدًا.**
/// تنتظر موافقة المستخدم الصريحة على الـ Diff قبل أي كتابة.
class ProposeFileChangeTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'propose_file_change',
        description:
            'اقترح إنشاء أو تعديل ملف داخل المشروع النشط. '
            'سيُعرض الـ Diff للمستخدم وتنتظر موافقته الصريحة قبل أي كتابة على القرص. '
            'المسار يجب أن يكون داخل مجلد المشروع النشط فقط.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'path': {
              'type': 'STRING',
              'description': 'مسار الملف نسبةً لجذر المشروع (مثال: lib/main.dart).',
            },
            'new_content': {
              'type': 'STRING',
              'description': 'المحتوى الجديد الكامل للملف.',
            },
          },
          'required': ['path', 'new_content'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final project = _getActiveProject();
    if (project == null) return _noProjectError();

    final path = arguments['path']?.toString();
    final newContent = arguments['new_content']?.toString();

    if (path == null || path.trim().isEmpty) {
      return jsonEncode({'error': 'مسار الملف (path) مطلوب'});
    }
    if (newContent == null) {
      return jsonEncode({'error': 'محتوى الملف (new_content) مطلوب'});
    }

    // إنشاء التعديل المعلَّق
    final proposeResult = await ProjectManager.instance.proposePendingChange(
      path: path.trim(),
      newContent: newContent,
    );

    final resultMap = jsonDecode(proposeResult) as Map<String, dynamic>;
    if (resultMap.containsKey('error')) return proposeResult;

    final changeId = resultMap['change_id'] as String;

    // الحلقة تنتظر قرار المستخدم
    final approved = await ProjectManager.instance.waitForChangeDecision(changeId);

    if (approved) {
      return jsonEncode({
        'status': 'change_applied',
        'file': resultMap['file'],
        'message': 'تم تطبيق التعديل وحفظ الملف على القرص بنجاح.',
      });
    } else {
      return jsonEncode({
        'status': 'change_rejected',
        'file': resultMap['file'],
        'message': 'رفض المستخدم التعديل — لم يتغير الملف على القرص.',
      });
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// run_terminal_command
// ══════════════════════════════════════════════════════════════════════════════

/// تنفيذ أمر PowerShell في مجلد المشروع النشط.
///
/// - يمر الأمر عبر [TerminalSecurityInterceptor] أولاً (كود، لا نص فقط)
/// - الأوامر الخطيرة تتوقف لتأكيد صريح
/// - الناتج يُبث حيًا لـ LiveTerminalPanel
/// - مهلة 120 ثانية
class RunTerminalCommandTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'run_terminal_command',
        description:
            'نفّذ أمر PowerShell في مجلد جذر المشروع النشط. '
            'الناتج يُبث حيًا لواجهة الترمينال المدمجة. '
            'مهلة قصوى 120 ثانية. '
            'الأوامر الخطيرة تتطلب تأكيد المستخدم تلقائياً. '
            'مثال: flutter pub get, flutter test, dart analyze',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'command': {
              'type': 'STRING',
              'description': 'الأمر المطلوب تنفيذه.',
            },
          },
          'required': ['command'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final project = _getActiveProject();
    if (project == null) return _noProjectError();

    final command = arguments['command']?.toString();
    if (command == null || command.trim().isEmpty) {
      return jsonEncode({'error': 'الأمر (command) مطلوب'});
    }

    final cmd = command.trim();

    // فحص أمان الأمر
    final interception = TerminalSecurityInterceptor.check(
      command: cmd,
      projectRootPath: project.rootPath,
    );

    if (interception is RejectedCommand) {
      return jsonEncode({
        'error': 'SECURITY_REJECTED',
        'message': interception.reason,
      });
    }

    if (interception is RequiresConfirmation) {
      final approved = await _requestTerminalConfirmation(interception, cmd);
      if (!approved) {
        return jsonEncode({
          'status': 'command_rejected_by_user',
          'message': 'رفض المستخدم تنفيذ الأمر — لم يُنفَّذ شيء على القرص.',
        });
      }
    }

    return ProjectManager.instance.runTerminalCommand(cmd);
  }

  Future<bool> _requestTerminalConfirmation(
    RequiresConfirmation interception,
    String command,
  ) async {
    final completer = Completer<bool>();

    ProjectManager.instance.emitEvent(
      TerminalSecurityConfirmationEvent(
        command: command,
        reason: interception.reason,
        category: interception.category,
        onDecision: (approved) {
          if (!completer.isCompleted) completer.complete(approved);
        },
      ),
    );

    return completer.future;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// read_project_file
// ══════════════════════════════════════════════════════════════════════════════

/// قراءة محتوى ملف من المشروع النشط — للتحليل والفهم.
class ReadProjectFileTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'read_project_file',
        description:
            'اقرأ محتوى ملف نصي من المشروع النشط. '
            'المسار داخل مجلد المشروع فقط. '
            'استخدم هذه الأداة لفهم الكود قبل اقتراح أي تعديلات.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'path': {
              'type': 'STRING',
              'description': 'مسار الملف نسبةً لجذر المشروع (مثال: lib/main.dart).',
            },
          },
          'required': ['path'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final project = _getActiveProject();
    if (project == null) return _noProjectError();

    final path = arguments['path']?.toString();
    if (path == null || path.trim().isEmpty) {
      return jsonEncode({'error': 'مسار الملف (path) مطلوب'});
    }

    return ProjectFileService.readProjectFile(project, path.trim());
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// list_project_files
// ══════════════════════════════════════════════════════════════════════════════

/// استعراض هيكل ملفات المشروع النشط.
class ListProjectFilesTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'list_project_files',
        description:
            'استعرض قائمة الملفات والمجلدات داخل المشروع النشط. '
            'اترك المسار فارغًا لاستعراض جذر المشروع.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'path': {
              'type': 'STRING',
              'description': 'مسار المجلد (اختياري، الافتراضي: جذر المشروع).',
            },
          },
          'required': [],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final project = _getActiveProject();
    if (project == null) return _noProjectError();

    final path = arguments['path']?.toString();
    return ProjectFileService.listProjectFiles(project, path);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// refresh_project_map
// ══════════════════════════════════════════════════════════════════════════════

/// إعادة توليد خريطة المشروع المضغوطة وتخزينها.
///
/// يستدعيها النموذج حين يشك أن الخريطة المحقونة في السياق قديمة،
/// أو بعد تعديلات جوهرية على بنية المشروع (إضافة حزم، تغيير pubspec.yaml).
class RefreshProjectMapTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'refresh_project_map',
        description:
            'أعد توليد خريطة المشروع المضغوطة وحدّثها في قاعدة البيانات. '
            'استخدم هذه الأداة إن كانت معلومات بنية المشروع في سياقك تبدو قديمة '
            'أو بعد إضافة حزم أو ملفات جديدة مهمة.',
        parameters: {
          'type': 'OBJECT',
          'properties': {},
          'required': [],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final project = _getActiveProject();
    if (project == null) return _noProjectError();

    try {
      await ProjectManager.instance.generateAndSaveProjectMap();
      final map = ProjectManager.instance.cachedProjectMap;
      return jsonEncode({
        'status': 'map_refreshed',
        'project': project.name,
        'map_length': map?.length ?? 0,
        'message': 'تم تحديث خريطة المشروع بنجاح.',
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل تحديث خريطة المشروع: $e'});
    }
  }
}

