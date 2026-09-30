import 'dart:async';
import 'dart:convert';

import 'package:khwarizmi/core/security/terminal_security_interceptor.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/projects/domain/entities/project.dart';
import 'package:khwarizmi/features/projects/services/project_file_service.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Project? _getActiveProject() => ProjectManager.instance.activeProject;

String _noProjectError() => jsonEncode({
  'error': 'لا يوجد مشروع نشط. استخدم زر "فتح مشروع" في الشريط الجانبي لاختيار مجلد مشروع أولاً.',
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
    final approved = await ProjectManager.instance.waitForChangeDecision(
      changeId,
    );

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
// propose_file_patch (Search & Replace — أفضل للملفات الكبيرة)
// ══════════════════════════════════════════════════════════════════════════════

/// تعديل جزئي لملف موجود عبر البحث والاستبدال — أسرع وأأمن من propose_file_change.
///
/// **الفائدة:** لا يحتاج إرسال محتوى الملف كاملاً للنموذج — يُرسل فقط
/// المقطع المراد تغييره، مما يوفر التوكنات ويتجنب Upstream Timeout.
class ProposeFilePatchTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'propose_file_patch',
    description:
        'عدّل جزءاً محدداً من ملف موجود عبر البحث والاستبدال الدقيق. '
        'أفضل من propose_file_change للملفات الكبيرة لأنك لا تحتاج لإرسال الملف كاملاً. '
        'ابحث عن نص فريد (search_text) وأبدله بالنص الجديد (replace_text). '
        'تأكد أن search_text موجود حرفياً في الملف وفريد (غير مكرر).',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'path': {
          'type': 'STRING',
          'description': 'مسار الملف نسبةً لجذر المشروع.',
        },
        'search_text': {
          'type': 'STRING',
          'description':
              'النص الحرفي الفريد المراد البحث عنه واستبداله. '
              'يجب أن يكون محدداً بما يكفي لتمييز الموضع (4+ أسطر على الأقل).',
        },
        'replace_text': {
          'type': 'STRING',
          'description': 'النص البديل الجديد.',
        },
        'description': {
          'type': 'STRING',
          'description': 'وصف مختصر للتعديل (مثال: "إصلاح overflow في Row").',
        },
      },
      'required': ['path', 'search_text', 'replace_text'],
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final project = _getActiveProject();
    if (project == null) return _noProjectError();

    final path = arguments['path']?.toString();
    final searchText = arguments['search_text']?.toString();
    final replaceText = arguments['replace_text']?.toString();

    if (path == null || path.trim().isEmpty) {
      return jsonEncode({'error': 'مسار الملف (path) مطلوب'});
    }
    if (searchText == null || searchText.isEmpty) {
      return jsonEncode({'error': 'نص البحث (search_text) مطلوب'});
    }
    if (replaceText == null) {
      return jsonEncode({'error': 'نص الاستبدال (replace_text) مطلوب'});
    }

    // قراءة الملف الحالي
    final currentRaw = await ProjectFileService.readRawContent(
      project,
      path.trim(),
    );
    if (currentRaw == null) {
      return jsonEncode({'error': 'الملف غير موجود أو لا يمكن قراءته: $path'});
    }

    // التحقق من وجود النص المطلوب
    final occurrences = searchText.allMatches(currentRaw).length;
    if (occurrences == 0) {
      return jsonEncode({
        'error': 'لم يُعثر على النص المطلوب في الملف.',
        'hint': 'تأكد أن search_text مطابق تماماً للنص في الملف (بما في ذلك المسافات والأسطر).',
      });
    }
    if (occurrences > 1) {
      return jsonEncode({
        'error': 'النص المطلوب موجود $occurrences مرات — يجب أن يكون فريداً.',
        'hint': 'أضف المزيد من السياق حول النص لتمييزه عن التكرارات الأخرى.',
      });
    }

    // تطبيق الاستبدال
    final newContent = currentRaw.replaceFirst(searchText, replaceText);

    // اقتراح التعديل عبر Diff نظامي
    final proposeResult = await ProjectManager.instance.proposePendingChange(
      path: path.trim(),
      newContent: newContent,
    );

    final resultMap = jsonDecode(proposeResult) as Map<String, dynamic>;
    if (resultMap.containsKey('error')) return proposeResult;

    final changeId = resultMap['change_id'] as String;
    final approved = await ProjectManager.instance.waitForChangeDecision(
      changeId,
    );

    if (approved) {
      return jsonEncode({
        'status': 'patch_applied',
        'file': resultMap['file'],
        'description':
            arguments['description'] ?? 'تعديل جزئي عبر Search & Replace',
        'message': 'تم تطبيق التعديل وحفظ الملف على القرص بنجاح.',
      });
    } else {
      return jsonEncode({
        'status': 'patch_rejected',
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
    // إصلاح 06: مهلة تنفيذ الأداة يجب أن تتسع للمهلة الداخلية للأمر
    // (120 ثانية) — كانت المهلة الخارجية 60 ثابتة فتُقتل الأوامر
    // الطويلة (flutter test مثلاً) قبل نصف مدتها.
    timeoutSeconds: 150,
    description:
        'نفّذ أمر PowerShell في مجلد جذر المشروع النشط. '
        'الناتج يُبث حيًا لواجهة الترمينال المدمجة. '
        'مهلة قصوى 120 ثانية. '
        'الأوامر الخطيرة تتطلب تأكيد المستخدم تلقائياً. '
        'مثال: flutter pub get, flutter test, dart analyze',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'command': {'type': 'STRING', 'description': 'الأمر المطلوب تنفيذه.'},
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

    // إصلاح 10: تمرير رمز الإلغاء المسجل في ToolRegistry لهذا التنفيذ —
    // يتيح لزر الإيقاف/إلغاء المهمة قتل الأمر الجاري فعلياً.
    return ProjectManager.instance.runTerminalCommand(
      cmd,
      cancellationToken: ToolRegistry.activeTokenFor('run_terminal_command'),
    );
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
/// تدعم القراءة الجزئية بالأسطر لتجنب إغراق سياق النموذج بملفات ضخمة.
class ReadProjectFileTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'read_project_file',
    description:
        'اقرأ محتوى ملف نصي من المشروع النشط. '
        'المسار داخل مجلد المشروع فقط. '
        'للملفات الكبيرة استخدم start_line وline_count لقراءة أجزاء محددة (مثل Zoo Code). '
        'مثال: قراءة الأسطر 130-429 من ملف كبير بدلاً من قراءته كاملاً.',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'path': {
          'type': 'STRING',
          'description': 'مسار الملف نسبةً لجذر المشروع (مثال: lib/main.dart).',
        },
        'start_line': {
          'type': 'INTEGER',
          'description': 'رقم السطر الأول للقراءة (1-indexed، اختياري — إذا لم يُحدد يُقرأ من البداية).',
        },
        'line_count': {
          'type': 'INTEGER',
          'description':
              'عدد الأسطر المطلوب قراءتها (اختياري، افتراضي 200، أقصى 500).',
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

    final startLine = arguments['start_line'] is int
        ? arguments['start_line'] as int
        : int.tryParse(arguments['start_line']?.toString() ?? '');
    final lineCount = arguments['line_count'] is int
        ? arguments['line_count'] as int
        : int.tryParse(arguments['line_count']?.toString() ?? '');

    return ProjectFileService.readProjectFile(
      project,
      path.trim(),
      startLine: startLine,
      lineCount: lineCount,
    );
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
    parameters: {'type': 'OBJECT', 'properties': {}, 'required': []},
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

// ══════════════════════════════════════════════════════════════════════════════
// search_project_code
// ══════════════════════════════════════════════════════════════════════════════

/// البحث في كود المشروع عن نص أو رمز برمجي أو تعبير نمطي.
///
/// يُرجع قائمة بمواقع النتائج (اسم الملف، رقم السطر، وسطر السياق فقط)
/// دون الحاجة لقراءة ملفات كاملة، مما يوفر التوكنات وزمن التنفيذ بشكل جذري.
class SearchProjectCodeTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'search_project_code',
    description:
        'ابحث عن نص أو رمز برمجي (اسم دالة، كلاس، متغير) أو تعبير نمطي (regex) عبر ملفات كود المشروع النشط. '
        'يُرجع قائمة بالنتائج تتضمن مسار الملف ورقم السطر وسياق السطر فقط (دون تحميل الملف كاملاً). '
        'استخدم هذه الأداة أولاً لمعرفة أين يظهر الرمز في المشروع بدلاً من تخمين الملفات وقراءتها كاملة.',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'query': {
          'type': 'STRING',
          'description': 'النص أو الرمز المراد البحث عنه عبر المشروع.',
        },
        'search_type': {
          'type': 'STRING',
          'description': 'نوع البحث: "literal" (بحث نصي، الافتراضي)، أو "symbol" (اسم رمز برمجي كدالة أو كلاس مع حدود الكلمة)، أو "regex" (تعبير نمطي).',
        },
        'path': {
          'type': 'STRING',
          'description': 'مسار مجلد أو ملف محدد لتضييق نطاق البحث (نسبةً لجذر المشروع، اختياري، الافتراضي هو كامل المشروع).',
        },
        'max_results': {
          'type': 'INTEGER',
          'description': 'الحد الأقصى لعدد النتائج (اختياري، الافتراضي 50).',
        },
      },
      'required': ['query'],
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final project = _getActiveProject();
    if (project == null) return _noProjectError();

    final query = arguments['query']?.toString();
    if (query == null || query.trim().isEmpty) {
      return jsonEncode({'error': 'نص البحث (query) مطلوب'});
    }

    final searchType = arguments['search_type']?.toString() ?? 'literal';
    final path = arguments['path']?.toString();
    final maxResults = arguments['max_results'] is int
        ? arguments['max_results'] as int
        : int.tryParse(arguments['max_results']?.toString() ?? '') ?? 50;

    return ProjectFileService.searchProjectCode(
      project,
      query: query.trim(),
      searchType: searchType,
      relativePath: path,
      maxResults: maxResults,
    );
  }
}
