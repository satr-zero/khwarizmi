import 'dart:typed_data';

class MemoryEntry {
  final String id;
  final String content;
  final String category;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final int accessCount;
  final int importance;
  final List<double>? embedding;

  const MemoryEntry({
    required this.id,
    required this.content,
    this.category = 'general',
    required this.createdAt,
    required this.lastAccessedAt,
    this.accessCount = 0,
    this.importance = 1,
    this.embedding,
  });

  MemoryEntry copyWith({
    String? id,
    String? content,
    String? category,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? accessCount,
    int? importance,
    List<double>? embedding,
  }) {
    return MemoryEntry(
      id: id ?? this.id,
      content: content ?? this.content,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
      importance: importance ?? this.importance,
      embedding: embedding ?? this.embedding,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'category': category,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_accessed_at': lastAccessedAt.millisecondsSinceEpoch,
      'access_count': accessCount,
      'importance': importance,
      'embedding': embedding != null ? floatsToBytes(embedding!) : null,
    };
  }

  factory MemoryEntry.fromMap(Map<String, dynamic> map) {
    List<double>? parsedEmbedding;
    final rawBlob = map['embedding'];
    if (rawBlob is Uint8List && rawBlob.isNotEmpty) {
      parsedEmbedding = bytesToFloats(rawBlob);
    }

    return MemoryEntry(
      id: map['id'] as String,
      content: map['content'] as String,
      category: (map['category'] as String?) ?? 'general',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(map['last_accessed_at'] as int),
      accessCount: (map['access_count'] as int?) ?? 0,
      importance: (map['importance'] as int?) ?? 1,
      embedding: parsedEmbedding,
    );
  }

  static Uint8List floatsToBytes(List<double> floats) {
    final floatList = Float32List.fromList(floats);
    return floatList.buffer.asUint8List();
  }

  static List<double> bytesToFloats(Uint8List bytes) {
    final floatList = Float32List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
    return floatList.toList();
  }
}
