/// يمثل مهارة نصية إرشادية (Text Skill) تُحقن للنموذج عند الطلب لتوجيه أسلوبه.
class TextSkill {
  /// الاسم الفريد للمهارة
  final String name;

  /// وصف موجز جداً (سطر واحد) يشرح متى تُستخدَم هذه المهارة
  final String description;

  /// المحتوى الإرشادي الكامل بتنسيق Markdown
  final String content;

  /// المسار الكامل للمجلد الحاوي للمهارة
  final String folderPath;

  /// المسار الكامل لملف SKILL.md
  final String filePath;

  /// هل المهارة مفعّلة ومتاحة في الفهرس الخفيف للنموذج؟
  final bool isEnabled;

  const TextSkill({
    required this.name,
    required this.description,
    required this.content,
    required this.folderPath,
    required this.filePath,
    this.isEnabled = true,
  });

  /// إنشاء كائن [TextSkill] من محتوى ملف SKILL.md
  /// الملف يتكون من YAML frontmatter بين `---` و `---` يتبعه محتوى Markdown
  factory TextSkill.fromFileContent(
    String rawContent, {
    required String folderPath,
    required String filePath,
    bool isEnabled = true,
  }) {
    final trimmed = rawContent.trim();
    if (!trimmed.startsWith('---')) {
      throw const FormatException('SKILL.md must start with YAML frontmatter delimiter "---".');
    }

    final secondDelimiterIndex = trimmed.indexOf('---', 3);
    if (secondDelimiterIndex == -1) {
      throw const FormatException('SKILL.md is missing closing frontmatter delimiter "---".');
    }

    final frontmatterBlock = trimmed.substring(3, secondDelimiterIndex).trim();
    final bodyContent = trimmed.substring(secondDelimiterIndex + 3).trim();

    String? name;
    String? description;

    for (final line in frontmatterBlock.split('\n')) {
      final lineTrimmed = line.trim();
      if (lineTrimmed.startsWith('name:')) {
        name = lineTrimmed.substring(5).trim();
        // إزالة علامات الاقتباس إن وُجدت
        if ((name.startsWith('"') && name.endsWith('"')) || (name.startsWith("'") && name.endsWith("'"))) {
          name = name.substring(1, name.length - 1).trim();
        }
      } else if (lineTrimmed.startsWith('description:')) {
        description = lineTrimmed.substring(12).trim();
        if ((description.startsWith('"') && description.endsWith('"')) ||
            (description.startsWith("'") && description.endsWith("'"))) {
          description = description.substring(1, description.length - 1).trim();
        }
      }
    }

    if (name == null || name.isEmpty) {
      throw const FormatException('SKILL.md frontmatter requires a non-empty "name" field.');
    }

    if (description == null || description.isEmpty) {
      throw const FormatException('SKILL.md frontmatter requires a non-empty "description" field.');
    }

    return TextSkill(
      name: name,
      description: description,
      content: bodyContent,
      folderPath: folderPath,
      filePath: filePath,
      isEnabled: isEnabled,
    );
  }

  TextSkill copyWith({
    String? name,
    String? description,
    String? content,
    String? folderPath,
    String? filePath,
    bool? isEnabled,
  }) {
    return TextSkill(
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      folderPath: folderPath ?? this.folderPath,
      filePath: filePath ?? this.filePath,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  @override
  String toString() => 'TextSkill(name: $name, isEnabled: $isEnabled)';
}
