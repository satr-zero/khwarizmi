/// توجيه تلقائي للمهام المعقدة نحو التخطيط/التنفيذ المستقل.
abstract final class TaskComplexityRouter {
  static final RegExp _highComplexity = RegExp(
    r'(مشروع\s+(كامل|ضخم|كبير)|تطبيق\s+(كامل|flutter|ويب)|'
    r'full\s+project|entire\s+codebase|multiple\s+files|'
    r'(\d+\s*\+?\s*ملف)| scaffold|from\s+scratch|'
    r'بناء\s+من\s+الصفر|هيكل\s+كامل|'
    r'لعبة|game|ملف\s+html|html\s+file|single\s+file|one\s+file|'
    r'canvas|webgl|three\.js|phaser|pixi)',
    caseSensitive: false,
  );

  static bool shouldRouteToAutonomousTask(String userText) {
    final t = userText.trim();
    if (t.length < 40) return false;
    return _highComplexity.hasMatch(t);
  }

  /// Returns a brief reason for why the text was classified as complex
  static String getComplexityReason(String userText) {
    final t = userText.trim();
    if (t.length < 40) return 'نص قصير';
    final matches = _highComplexity
        .allMatches(t)
        .map((m) => m.group(0))
        .whereType<String>()
        .toList();
    if (matches.isNotEmpty)
      return 'الكلمات المفتاحية: ${matches.take(3).join(", ")}';
    return 'لا يتطابق مع نمط التعقيد';
  }

  static const String systemPromptAddendum = '''

[توجيه تعقيد — مهمة كبيرة]:
يبدو أن طلب المستخدم يتجاوز خطوة واحدة بسيطة. لتجنب «الشلل التحليلي» والوعود بلا تنفيذ:
- إن كان الهدف يتطلب عدة ملفات أو مشروعاً كاملاً، **فضّل** استدعاء start_autonomous_task(goal=...) لبناء خطة وتنفيذ مستقل.
- لا تكتب خطة طويلة كنص فقط دون أداة؛ إما start_autonomous_task أو أداة ملف/تعديل فورية.
''';
}
