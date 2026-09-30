class ReminderItem {
  final String id;
  final String title;
  final String? description;
  final DateTime scheduledTime;
  final String recurrence; // 'once', 'daily', 'weekly'
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? completedAt;

  const ReminderItem({
    required this.id,
    required this.title,
    this.description,
    required this.scheduledTime,
    this.recurrence = 'once',
    this.isCompleted = false,
    required this.createdAt,
    this.completedAt,
  });

  ReminderItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? scheduledTime,
    String? recurrence,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return ReminderItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      recurrence: recurrence ?? this.recurrence,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'scheduled_time': scheduledTime.millisecondsSinceEpoch,
      'recurrence': recurrence,
      'is_completed': isCompleted ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
    };
  }

  factory ReminderItem.fromMap(Map<String, dynamic> map) {
    return ReminderItem(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      scheduledTime: DateTime.fromMillisecondsSinceEpoch(map['scheduled_time'] as int),
      recurrence: (map['recurrence'] as String?) ?? 'once',
      isCompleted: (map['is_completed'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      completedAt: map['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int)
          : null,
    );
  }
}
