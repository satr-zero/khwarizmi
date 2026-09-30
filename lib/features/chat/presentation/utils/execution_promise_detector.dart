import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';

/// كاشف نمط "الوعد بالتنفيذ دون استدعاء فعلي" (Promise-Without-Execution Detector).
///
/// يرصد الأنماط اللغوية التي تصف تنفيذاً وشيكاً (أفعال المستقبل القريب المقترنة
/// بأفعال تنفيذ مثل "سأقوم بـ/سأنشئ/سأكتب/سأرسل" مقترنة بـ"الآن/مباشرة/فوراً")
/// التي يُطلقها النموذج دون أن يصحبها استدعاء أداة فعلي واحد على الأقل.
abstract final class ExecutionPromiseDetector {
  static const String systemAlertNotice =
      'لاحظنا أن النموذج وعد بالتنفيذ مرتين متتاليتين دون استدعاء أداة فعلية. قد يحتاج توضيحاً إضافياً منك، أو تبديل الموديل المستخدم.';

  // أفعال التنفيذ المباشر (المتكلم بصيغة المستقبل أو الشروع في التنفيذ)
  static final RegExp _arabicActionVerbs = RegExp(
    r'(س[أاإآ]?(قوم\s+ب|نشئ|كتب|رسل|سلم|نفذ|بدأ|بني|عدل|ولد|حضر|جهز)|دعني\s+[أاإآ]?(بدأ|نشئ|كتب|قوم|رسل|جهز))',
    caseSensitive: false,
  );

  // الكلمات الدالة على التنفيذ الوشيك والفوري
  static final RegExp _arabicImminentWords = RegExp(
    r'(ال[آاإأ]ن|مباشرة|فور[اًا]|حال[اًا]|لحظات|دفعة\s+واحدة|في\s+الحال|توّ?[اًا])',
    caseSensitive: false,
  );

  // الأنماط الإنجليزية المكافئة
  // يسمح بظروف الوقت (now, immediately, right away) بين الفعل المساعد والفعل الرئيسي
  static final RegExp _englishActionVerbs = RegExp(
    r'(i(\x27ll|\s+will|\s+am\s+going\s+to)\s+(?:now|immediately|right\s+away|directly|shortly|at\s+once|then|)\s*(create|write|deliver|send|generate|build|start|execute|prepare)|let\s+me\s+(create|write|start|deliver|generate|build|send))',
    caseSensitive: false,
  );

  static final RegExp _englishImminentWords = RegExp(
    r'(now|immediately|right\s+away|directly|shortly|at\s+once)',
    caseSensitive: false,
  );

  /// سياق يدل على تسليم ملف/كود/مشروع (وعود التنفيذ بدون «الآن»).
  static final RegExp _deliverableContext = RegExp(
    r'(ملف|ملفات|كود|مشروع|تطبيق|html|css|js|dart|flutter|'
    r'file|files|code|project|deliver|patch|repo|package)',
    caseSensitive: false,
  );

  /// يفحص ما إذا كان النص يحتوي على صياغة تصف تنفيذاً وشيكاً
  static bool isImminentExecutionPromise(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final hasArabicAction = _arabicActionVerbs.hasMatch(trimmed);
    final hasArabicImminent = _arabicImminentWords.hasMatch(trimmed);
    if (hasArabicAction && hasArabicImminent) return true;

    final hasEnglishAction = _englishActionVerbs.hasMatch(trimmed);
    final hasEnglishImminent = _englishImminentWords.hasMatch(trimmed);
    if (hasEnglishAction && hasEnglishImminent) return true;

    return false;
  }

  /// وعد تنفيذ أوسع: فعل تنفيذ + سياق تسليم، أو صياغة وشيكة صريحة.
  static bool isExecutionPromise(String text) {
    if (isImminentExecutionPromise(text)) return true;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (_arabicActionVerbs.hasMatch(trimmed) &&
        _deliverableContext.hasMatch(trimmed)) {
      return true;
    }
    if (_englishActionVerbs.hasMatch(trimmed) &&
        _deliverableContext.hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  /// يحسب عدد المرات المتتالية التي وعد فيها النموذج بالتنفيذ دون أي استدعاء
  /// أداة فعلي في سجل المحادثة حتى اللحظة.
  ///
  /// يتتبع السجل للخلف: أي استدعاء أداة أو رسالة رد لا تحتوي وعداً بالتنفيذ
  /// تكسر السلسلة وتصفر العدّاد.
  static int countConsecutivePromises(List<ChatMessage> messages) {
    int count = 0;

    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];

      // وجود أداة تم تنفيذها يكسر السلسلة
      if (msg.role == MessageRole.tool) {
        break;
      }

      if (msg.role == MessageRole.assistant) {
        if (msg.content.trim().isEmpty || msg.isStreaming) {
          break;
        }

        final hasToolCalls = msg.toolCalls != null && msg.toolCalls!.isNotEmpty;
        if (hasToolCalls) {
          // استدعى أداة فعلية -> السلسلة انكسرت
          break;
        }

        if (isExecutionPromise(msg.content)) {
          count++;
        } else {
          // رد مساعد لا يحتوي وعداً بالتنفيذ (مثلاً: شرح عادي أو سؤال توضيحي) -> السلسلة انكسرت
          break;
        }
      }

      // رسائل المستخدم أو رسائل النظام السابقة تُتجاوز لمتابعة فحص ردود المساعد
    }

    return count;
  }
}
