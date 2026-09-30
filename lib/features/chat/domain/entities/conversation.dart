/// كيان المحادثة في سجل المحادثات (Chat History)
class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? activeCodingMode; // للنمط البرمجي النشط (مخزن كاسم enum)

  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.activeCodingMode,
  });

  Conversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? activeCodingMode,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      activeCodingMode: activeCodingMode ?? this.activeCodingMode,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'active_coding_mode': activeCodingMode,
  };

  factory Conversation.fromMap(Map<String, dynamic> map) => Conversation(
    id: map['id'] as String,
    title: map['title'] as String? ?? 'محادثة جديدة',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['created_at'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['updated_at'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
    activeCodingMode: map['active_coding_mode'] as String?,
  );

  Map<String, dynamic> toJson() => toMap();

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      Conversation.fromMap(json);
}
