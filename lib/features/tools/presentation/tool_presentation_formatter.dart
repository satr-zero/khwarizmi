/// يُحوّل أسماء الأدوات التقنية الداخلية إلى نصوص عربية إنسانية واضحة
/// لعرضها في واجهة الشات بدلاً من أسماء الدوال البرمجية.
///
/// مثال: "propose_file_change" → "يعدّل lib/main.dart"
///         "run_terminal_command" → "ينفّذ: flutter pub get"
library;

class ToolPresentationFormatter {
  /// يُرجع اسماً إنسانياً لأداة بناءً على اسمها ومعاملاتها.
  static String getFriendlyToolName(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    switch (toolName) {
      // ── أدوات الملفات ────────────────────────────────────────────────────
      case 'read_project_file':
        final path = arguments['path']?.toString() ?? '';
        final startLineRaw = arguments['start_line'];
        final lineCountRaw = arguments['line_count'];
        final startLine = startLineRaw is num
            ? startLineRaw.toInt()
            : int.tryParse(startLineRaw?.toString() ?? '');
        final lineCount = lineCountRaw is num
            ? lineCountRaw.toInt()
            : int.tryParse(lineCountRaw?.toString() ?? '');
        if (startLine != null) {
          final end = lineCount != null ? (startLine + lineCount - 1) : '...';
          return 'يقرأ $path (أسطر $startLine-$end)';
        }
        return 'يقرأ $path';

      case 'propose_file_change':
        final path = arguments['path']?.toString() ?? '';
        return 'يعدّل $path';

      case 'propose_file_patch':
        final path = arguments['path']?.toString() ?? '';
        final desc = arguments['description']?.toString();
        return desc != null ? 'يُصلح $path: $desc' : 'يُعدّل $path (patch)';

      case 'list_project_files':
        final path = arguments['path']?.toString();
        return path != null && path.isNotEmpty
            ? 'يستعرض مجلد $path'
            : 'يستعرض ملفات المشروع';

      case 'refresh_project_map':
        return 'يُحدّث خريطة المشروع';

      // ── الترمينال ────────────────────────────────────────────────────────
      case 'run_terminal_command':
        final cmd = arguments['command']?.toString() ?? '';
        // عرض أول 40 حرف من الأمر
        final display = cmd.length > 40 ? '${cmd.substring(0, 40)}...' : cmd;
        return 'ينفّذ: $display';

      // ── التصفح والويب ───────────────────────────────────────────────────
      case 'browser_navigate':
      case 'navigate_browser':
        final url = arguments['url']?.toString() ?? '';
        return 'يتصفح $url';

      case 'browser_screenshot':
        return 'يلتقط لقطة شاشة';

      case 'browser_click':
        final selector = arguments['selector']?.toString() ?? '';
        return 'ينقر على $selector';

      case 'browser_type':
        return 'يكتب نصاً في المتصفح';

      case 'browser_search':
        final query = arguments['query']?.toString() ?? '';
        return 'يبحث عن: $query';

      case 'web_search':
        final query = arguments['query']?.toString() ?? '';
        return 'يبحث: $query';

      // ── الذاكرة والمهام ──────────────────────────────────────────────────
      case 'save_memory':
        return 'يحفظ في الذاكرة';

      case 'recall_memory':
        return 'يستدعي الذاكرة';

      case 'report_progress':
        final progress = arguments['progress']?.toString() ?? '';
        return progress.isNotEmpty ? 'التقدم: $progress' : 'يُبلّغ عن تقدم';

      case 'complete_task':
        return 'يُكمل المهمة';

      case 'start_autonomous_task':
        return 'يبدأ مهمة مستقلة';

      case 'resume_task':
        return 'يستأنف المهمة';

      // ── المهارات ─────────────────────────────────────────────────────────
      case 'load_text_skill':
        final name = arguments['skill_name']?.toString() ?? '';
        return 'يحمّل مهارة: $name';

      // ── جدولة التذكيرات ─────────────────────────────────────────────────
      case 'set_reminder':
      case 'create_reminder':
        return 'يضع تذكيراً';

      // ── الافتراضي ────────────────────────────────────────────────────────
      default:
        // تحويل snake_case إلى قراءة إنسانية
        final readable = toolName
            .replaceAll('_', ' ')
            .replaceFirst(RegExp(r'^.'), toolName[0].toUpperCase());
        return readable;
    }
  }
}
