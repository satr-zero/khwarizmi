/// كيان المشروع النشط — المرحلة 9.
///
/// مسار [rootPath] هو الجذر المقيَّد الذي تعمل داخله كل أدوات المشروع.
class Project {
  final String id;
  final String name;
  final String rootPath; // مسار مجلد المشروع الجذر على القرص
  final DateTime createdAt;
  final DateTime lastOpenedAt;
  final String? projectMap;

  Project({
    required this.id,
    required this.name,
    required this.rootPath,
    DateTime? createdAt,
    required this.lastOpenedAt,
    this.projectMap,
  }) : createdAt = createdAt ?? lastOpenedAt;

  Project copyWith({
    String? id,
    String? name,
    String? rootPath,
    DateTime? createdAt,
    DateTime? lastOpenedAt,
    String? projectMap,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      createdAt: createdAt ?? this.createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      projectMap: projectMap ?? this.projectMap,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'root_path': rootPath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'last_opened_at': lastOpenedAt.millisecondsSinceEpoch,
        if (projectMap != null) 'project_map': projectMap,
      };

  factory Project.fromMap(Map<String, dynamic> map) => Project(
        id: map['id'] as String,
        name: map['name'] as String,
        rootPath: map['root_path'] as String,
        createdAt: map['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch((map['created_at'] as num).toInt())
            : DateTime.fromMillisecondsSinceEpoch((map['last_opened_at'] as num).toInt()),
        lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['last_opened_at'] as num).toInt(),
        ),
        projectMap: map['project_map'] as String?,
      );

  @override
  String toString() => 'Project(id: $id, name: $name, rootPath: $rootPath)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Project && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
