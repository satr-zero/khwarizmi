import 'dart:async';

/// استثناء يُرمى داخل تنفيذ الأداة عندما يُلغى التنفيذ عمداً
/// (مثلاً زر الإيقاف في المحادثة أو إلغاء مهمة مستقلة).
class ToolCancelledException implements Exception {
  final String reason;
  const ToolCancelledException([this.reason = 'cancelled']);

  @override
  String toString() => 'ToolCancelledException: $reason';
}

/// رمز إلغاء يمرَّر عبر [ToolRegistry.executeTool] للأدوات القابلة للإلغاء.
///
/// إصلاح 10: زر الإيقاف وإلغاء المهمة كانا يقطعان بث الأحداث فقط بينما
/// استدعاء الأداة الجاري (مثل أمر ترمينال طويل) يبقى قيد التنفيذ حتى
/// نهايته. هذا الرمز يتيح للأدوات تسجيل معالجات تنظيف (مثل قتل العملية)
/// تُستدعى فور الإلغاء، ويكشف [isCancelled] للفحص الدوري داخل الحلقات.
class ToolCancellationToken {
  final Completer<String> _completer = Completer<String>();
  final List<void Function(String reason)> _onCancelHandlers = [];
  bool _cancelled = false;
  String _reason = '';

  /// هل أُلغي التنفيذ؟
  bool get isCancelled => _cancelled;

  /// سبب الإلغاء (فارغ إن لم يُلغَ).
  String get reason => _reason;

  /// مستقبل يكتمل بسبب الإلغاء — لا يكتمل أبداً إن لم يُلغَ.
  Future<String> get whenCancelled => _completer.future;

  /// تسجيل معالج يُشغَّل عند الإلغاء مرة واحدة.
  /// إن كان الرمز ملغى أصلاً يُشغَّل المعالج فوراً (يعالج سباق الإلغاء
  /// أثناء بدء التنفيذ).
  void onCancel(void Function(String reason) handler) {
    if (_cancelled) {
      handler(_reason);
      return;
    }
    _onCancelHandlers.add(handler);
  }

  /// الإلغاء — يعمل مرة واحدة فقط، يشغّل كل المعالجات المسجلة ويكمل
  /// [whenCancelled]. الاستدعاءات اللاحقة تُتجاهل.
  void cancel([String reason = 'cancelled']) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    final handlers = List<void Function(String reason)>.of(_onCancelHandlers);
    _onCancelHandlers.clear();
    for (final handler in handlers) {
      try {
        handler(reason);
      } catch (_) {}
    }
    _completer.complete(reason);
  }

  /// يرمي [ToolCancelledException] إن كان الرمز ملغى — للاستخدام الدوري
  /// داخل حلقات تنفيذ الأداة الطويلة.
  void throwIfCancelled() {
    if (_cancelled) throw ToolCancelledException(_reason);
  }
}
