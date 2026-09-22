import 'dart:convert';
import 'package:path/path.dart' as p;

/// Utilities for presenting tool executions to users in clean, natural language.
abstract final class ToolPresentationFormatter {
  /// Returns a user-friendly Arabic phrase describing the tool action,
  /// avoiding raw technical function names.
  static String getFriendlyToolName(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    switch (toolName) {
      // ── Coding & Project Tools ──────────────────────────────────────────────
      case 'read_project_file':
        final path = arguments['path'] as String?;
        if (path != null && path.isNotEmpty) {
          return 'يقرأ: $path';
        }
        return 'يقرأ ملفًا من المشروع...';

      case 'list_project_files':
        final path = arguments['path'] as String?;
        if (path != null && path.isNotEmpty) {
          return 'يستعرض: $path';
        }
        return 'يستعرض ملفات المشروع...';

      case 'propose_file_change':
        final path = arguments['path'] as String?;
        if (path != null && path.isNotEmpty) {
          return 'يجهّز تعديلًا: $path';
        }
        return 'يجهّز تعديلًا على ملف...';

      case 'run_terminal_command':
        final cmd = arguments['command'] as String?;
        if (cmd != null && cmd.isNotEmpty) {
          final trimmed = cmd.length > 30 ? '${cmd.substring(0, 30)}...' : cmd;
          return 'ينفّذ: $trimmed';
        }
        return 'ينفّذ أمرًا في الترمينال...';

      case 'refresh_project_map':
        return 'يحدّث خريطة المشروع';

      // ── Web & Browser Tools ────────────────────────────────────────────────
      case 'web_search':
        final query = arguments['query'] as String?;
        if (query != null && query.isNotEmpty) {
          final trimmed = query.length > 35 ? '${query.substring(0, 35)}...' : query;
          return 'يبحث في الويب عن "$trimmed"';
        }
        return 'يبحث في الويب...';

      case 'fetch_url':
      case 'browse_url':
        final url = arguments['url'] as String?;
        if (url != null && url.isNotEmpty) {
          try {
            final host = Uri.parse(url).host;
            return 'يفتح: ${host.isNotEmpty ? host : url}';
          } catch (_) {
            return 'يفتح الرابط: $url';
          }
        }
        return 'يفتح صفحة ويب...';

      case 'scroll_page':
        final dir = arguments['direction'] as String? ?? 'down';
        final dirAr = dir == 'up' ? 'للأعلى' : 'للأسفل';
        return 'يتمرر في الصفحة ($dirAr)';

      case 'inspect_visual_page':
        return 'يفحص الصفحة بصريًا';

      case 'click_element':
        final selector = arguments['selector'] as String?;
        if (selector != null && selector.isNotEmpty) {
          return 'ينقر على: $selector';
        }
        return 'ينقر على عنصر في الصفحة';

      case 'fill_input':
        final selector = arguments['selector'] as String?;
        if (selector != null && selector.isNotEmpty) {
          return 'يكتب في: $selector';
        }
        return 'يُدخل نصًا في حقل';

      case 'download_file':
        final url = arguments['url'] as String?;
        if (url != null && url.isNotEmpty) {
          return 'يحمّل: ${p.basename(url)}';
        }
        return 'يحمّل الملف...';

      // ── Memory & Reminders ─────────────────────────────────────────────────
      case 'save_memory':
      case 'store_memory':
        return 'يحفظ معلومة بالذاكرة الدائمة';

      case 'search_memory':
        final query = arguments['query'] as String?;
        if (query != null && query.isNotEmpty) {
          final trimmed = query.length > 35 ? '${query.substring(0, 35)}...' : query;
          return 'يبحث بالذاكرة الدائمة عن "$trimmed"';
        }
        return 'يبحث بالذاكرة الدائمة...';

      case 'delete_memory':
        return 'يحذف معلومة من الذاكرة';

      case 'schedule_reminder':
        final title = arguments['title'] as String?;
        if (title != null && title.isNotEmpty) {
          return 'يجدول تذكيرًا: "$title"';
        }
        return 'يجدول تذكيرًا جديدًا...';

      case 'cancel_reminder':
        return 'يلغي تذكيرًا مجدولاً';

      case 'list_reminders':
        return 'يستعرض التذكيرات المجدولة';

      // ── System & Autonomous Tasks ──────────────────────────────────────────
      case 'get_current_datetime':
      case 'system_time':
        return 'يجلب الوقت الحالي';

      case 'start_autonomous_task':
        return 'يبدأ مهمة مستقلة';

      case 'resume_task':
        return 'يستأنف المهمة';

      case 'load_text_skill':
        final skillName = arguments['skill_name'] as String?;
        if (skillName != null && skillName.isNotEmpty) {
          return 'يحمّل مهارة: $skillName';
        }
        return 'يحمّل إرشادات مهارة';

      case 'complete_task':
        return 'يُنهي المهمة المستقلة';

      case 'report_progress':
        return 'يقدّم تقريرًا عن التقدم';

      case 'ask_user':
        return 'يسأل المستخدم للتوضيح';

      case 'file_system':
      case 'read_file':
      case 'write_file':
        final path = arguments['path'] as String?;
        if (path != null && path.isNotEmpty) {
          return 'يتعامل مع ملف: $path';
        }
        return 'يتعامل مع نظام الملفات...';

      default:
        return 'ينفّذ أداة: $toolName';
    }
  }

  /// Parses tool result JSON and returns a 1-line human summary of what occurred.
  static String getFriendlySummary(
    String toolName,
    String? rawResult, {
    String? errorMessage,
  }) {
    if (errorMessage != null && errorMessage.isNotEmpty) {
      final shortReason = errorMessage.length > 60
          ? '${errorMessage.substring(0, 60)}...'
          : errorMessage;
      return 'فشل $toolName — $shortReason';
    }
    if (rawResult == null || rawResult.isEmpty) {
      return 'انتهت الأداة';
    }

    try {
      final decoded = jsonDecode(rawResult);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('error')) {
          final err = decoded['error'].toString();
          final shortErr = err.length > 60 ? '${err.substring(0, 60)}...' : err;
          return 'فشل $toolName — $shortErr';
        }

        switch (toolName) {
          // ── Coding & Project Tools ──────────────────────────────────────────
          case 'read_project_file':
            final path = decoded['path'] as String? ?? '';
            final filename = path.isNotEmpty ? p.basename(path) : 'الملف';
            final lines = decoded['lines_count'] ?? decoded['total_lines'];
            if (lines != null) {
              return 'قرأ $filename — $lines سطرًا';
            }
            final content = decoded['content'] as String?;
            if (content != null) {
              final lineCount = content.split('\n').length;
              return 'قرأ $filename — $lineCount سطرًا';
            }
            return 'قرأ $filename بنجاح';

          case 'list_project_files':
            final count = decoded['count'] ?? (decoded['files'] as List?)?.length;
            if (count != null) {
              return 'وجد $count عنصرًا';
            }
            return 'استعرض قائمة الملفات بنجاح';

          case 'propose_file_change':
            final file = decoded['file'] as String? ?? '';
            final filename = file.isNotEmpty ? p.basename(file) : 'الملف';
            final status = decoded['status'] as String?;
            if (status == 'change_applied') {
              return 'تم تطبيق التعديل على $filename بنجاح';
            } else if (status == 'change_rejected') {
              return 'تم رفض التعديل على $filename من المستخدم';
            }
            return 'اقترح تعديلًا على $filename — بانتظار موافقتك';

          case 'run_terminal_command':
            final status = decoded['status'] as String?;
            final exitCode = decoded['exit_code'] ?? 0;
            final isSuccess = status == 'success' || exitCode == 0;
            return 'نفّذ — ${isSuccess ? 'نجح' : 'فشل'} (رمز $exitCode)';

          case 'refresh_project_map':
            return 'حُدّثت الخريطة بنجاح';

          // ── Web & Browser Tools ────────────────────────────────────────────
          case 'web_search':
            final results = decoded['results'] as List?;
            final count = results?.length ?? 0;
            if (count > 0) {
              return 'وجد $count نتائج بحث مطابقة';
            }
            return 'لم يتم العثور على نتائج بحث مباشرة';

          case 'fetch_url':
          case 'browse_url':
            final title = decoded['title'] as String?;
            if (title != null && title.isNotEmpty) {
              return 'قرأ الصفحة: "$title"';
            }
            return 'قرأ الصفحة';

          case 'scroll_page':
            final dir = decoded['direction'] as String? ?? 'down';
            final dirAr = dir == 'up' ? 'للأعلى' : 'للأسفل';
            return 'تمرّر $dirAr';

          case 'inspect_visual_page':
            return 'تم فحص الصفحة بصريًا بنجاح';

          case 'click_element':
            return 'نقر على العنصر';

          case 'fill_input':
            return 'أدخل النص';

          case 'download_file':
            final path = decoded['saved_to'] ?? decoded['path'] ?? decoded['file'];
            if (path != null) {
              return 'حُمِّل: ${p.basename(path.toString())}';
            }
            return 'تم تحميل الملف بنجاح';

          // ── Memory & Reminders ─────────────────────────────────────────────
          case 'save_memory':
          case 'store_memory':
            return 'تم حفظ المعلومة في الذاكرة الدائمة بنجاح';

          case 'search_memory':
            final results = decoded['results'] as List?;
            final count = results?.length ?? 0;
            if (count > 0) {
              return 'استرجع $count ذكريات سابقة ذات صلة';
            }
            return 'لم يُعثر على ذكريات سابقة مطابقة';

          case 'delete_memory':
            return 'تم حذف المعلومة المحددة من الذاكرة';

          case 'schedule_reminder':
            return 'جُدول التذكير بنجاح';

          case 'cancel_reminder':
            return 'أُلغي التذكير بنجاح';

          case 'list_reminders':
            final count = (decoded['reminders'] as List?)?.length ?? 0;
            return 'استرجع $count تذكيرات مجدولة';

          // ── System & Autonomous Tasks ──────────────────────────────────────
          case 'get_current_datetime':
          case 'system_time':
            final dt = decoded['datetime'] ?? decoded['iso'] ?? decoded['formatted'];
            if (dt != null) {
              return 'الوقت: $dt';
            }
            return 'تم استرجاع الوقت الحالي';

          case 'start_autonomous_task':
            return 'بدأت المهمة';

          case 'load_text_skill':
            return 'حُمّلت إرشادات المهارة';

          case 'complete_task':
            return 'اكتملت المهمة المستقلة';

          case 'report_progress':
            return 'تم تحديث تقرير التقدم';

          case 'ask_user':
            return 'بانتظار إجابة المستخدم';
        }
      }
    } catch (_) {
      // Not JSON or parsing error, fallback
    }

    return 'انتهت الأداة';
  }
}
