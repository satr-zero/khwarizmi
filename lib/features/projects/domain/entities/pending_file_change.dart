/// كيان التعديل المعلَّق على ملف داخل المشروع — المرحلة 9.
///
/// يُنشأ بواسطة `propose_file_change` ويبقى معلَّقًا حتى يوافق المستخدم
/// أو يرفض صراحةً. **لا يُكتب أي شيء على القرص قبل الموافقة.**
class PendingFileChange {
  final String id;

  /// المسار المطلق المحسوم والمتحقق منه (داخل rootPath).
  final String absolutePath;

  /// المحتوى الحالي للملف على القرص — null إن كان ملفًا جديدًا.
  final String? existingContent;

  /// المحتوى المقترح من النموذج.
  final String proposedContent;

  /// سطور الـ Diff المحسوبة مسبقًا للعرض.
  final List<DiffLine> diffLines;

  final DateTime createdAt;

  const PendingFileChange({
    required this.id,
    required this.absolutePath,
    required this.proposedContent,
    required this.diffLines,
    required this.createdAt,
    this.existingContent,
  });

  /// هل هذا ملف جديد (لا يوجد على القرص بعد)؟
  bool get isNewFile => existingContent == null;

  /// اسم الملف فقط (بدون المسار الكامل).
  String get fileName => absolutePath.split(RegExp(r'[/\\]')).last;
}

/// نوع سطر في الـ Diff.
enum DiffLineType {
  added,     // سطر مضاف (يظهر بخلفية فاتحة تُشير للإضافة)
  removed,   // سطر محذوف (يظهر بخلفية داكنة تُشير للحذف)
  context,   // سطر سياق (غير متأثر — يُعرض للفهم فقط)
}

/// سطر واحد في نتيجة الـ Diff.
class DiffLine {
  final DiffLineType type;
  final String content;
  final int? oldLineNumber;
  final int? newLineNumber;

  const DiffLine({
    required this.type,
    required this.content,
    this.oldLineNumber,
    this.newLineNumber,
  });
}
