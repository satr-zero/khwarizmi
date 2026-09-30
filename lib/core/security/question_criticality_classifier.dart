import 'package:khwarizmi/core/security/terminal_security_interceptor.dart';

/// جدول وقاعدة تصنيف صريحة للأسئلة: حرج (Critical) مقابل غير حرج (Non-Critical).
///
/// الأسئلة الحرجة:
/// - أي تأكيد خطر أو لا رجعة فيه (حذف ملف، تنفيذ أمر مدمّر، override، عمليات أمنية)
/// - تنتظر رد المستخدم دائماً دون حد زمني ولا تُصعَّد تلقائياً أبداً.
///
/// الأسئلة غير الحرجة:
/// - خيارات تفضيلية (مكتبات، تصاميم، تسمية ملفات، خيارات هندسية قابلة للتعديل)
/// - تدعم مهلة الـ 30 ثانية والتصعيد التلقائي في السلسلة التلقائية.
class QuestionCriticalityClassifier {
  QuestionCriticalityClassifier._();

  /// الكلمات والأنماط الدالة على عمليات حرجة قطعاً
  static const List<String> _criticalKeywords = [
    'حذف',
    'delete',
    'remove',
    'drop',
    'format',
    'تدمير',
    'إلغاء لا رجعة فيه',
    'reset --hard',
    'force',
    'push --force',
    'override',
    'استبدال كلي',
    '🔒',
    'تأكيد مطلوب',
    'تحذير أمني',
    'security',
    'credential',
    'password',
    'secret',
    'key',
  ];

  /// التحقق الصريح مما إذا كان السؤال حرجاً
  static bool isCritical({
    required String question,
    bool? explicitTag,
    Map<String, dynamic>? arguments,
  }) {
    // 1. إذا كان السؤال يحمل tag صريح
    if (explicitTag != null) {
      return explicitTag;
    }

    if (arguments != null) {
      if (arguments['critical'] == true || arguments['is_critical'] == true) {
        return true;
      }
      if (arguments['critical'] == false || arguments['is_critical'] == false) {
        return false;
      }
    }

    // 2. التحقق من نصوص الأمان الصادرة عن TerminalSecurityInterceptor أو BrowserSecurityInterceptor
    final qLower = question.toLowerCase();
    for (final kw in _criticalKeywords) {
      if (qLower.contains(kw)) {
        return true;
      }
    }

    // 3. التحقق من أمر الترمينال إن وُجد في المعاملات
    if (arguments != null && arguments.containsKey('command')) {
      final cmd = arguments['command']?.toString() ?? '';
      final check = TerminalSecurityInterceptor.check(
        command: cmd,
        projectRootPath: '',
      );
      if (check is RequiresConfirmation || check is RejectedCommand) {
        return true;
      }
    }

    return false;
  }
}
