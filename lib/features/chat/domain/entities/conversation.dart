
/// كيان المحادثة في سجل المحادثات (Chat History)
class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  Conversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory Conversation.fromMap(Map<String, dynamic> map) => Conversation(
    id: map['id'] as String,
    title: map['title'] as String? ?? 'محادثة جديدة',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );

  Map<String, dynamic> toJson() => toMap();

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      Conversation.fromMap(json);
}
