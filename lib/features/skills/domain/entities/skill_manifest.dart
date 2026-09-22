import 'dart:convert';

/// يمثل الـ Manifest التعريفي لـ Skill خارجي وفق مواصفات المرحلة 8.
class SkillManifest {
  /// اسم الأداة الفريد المستخدم من النموذج (Tool name)
  final String name;

  /// الاسم المعروض للمستخدم في الواجهة
  final String displayName;

  /// وصف وظيفي واضح يُستخدَم كتوصيف للأداة للنموذج نفسه
  final String description;

  /// الرابط المحلي لاستدعاء الأداة (HTTP local endpoint)
  final String endpoint;

  /// مواصفة المدخلات (JSON Schema القياسي)
  final Map<String, dynamic> inputSchema;

  /// الصلاحيات المطلوبة (مثل: network, filesystem, browser)
  final List<String> permissions;

  /// إصدار الـ Skill
  final String version;

  /// أمر التشغيل التلقائي للعملية الفرعية (اختياري، مثلاً: "python weather_skill.py")
  final String? startCommand;

  /// المسار الكامل للمجلد الحاوي للـ Skill على القرص
  final String folderPath;

  const SkillManifest({
    required this.name,
    required this.displayName,
    required this.description,
    required this.endpoint,
    required this.inputSchema,
    this.permissions = const [],
    this.version = '1.0.0',
    this.startCommand,
    required this.folderPath,
  });

  /// إنشاء كائن [SkillManifest] من JSON مع التحقق الصارم من الحقول الإلزامية.
  /// يرمي [FormatException] إذا كان هناك أي حقل إلزامي ناقص أو غير صالح.
  factory SkillManifest.fromJson(
    Map<String, dynamic> json, {
    required String folderPath,
  }) {
    // 1. التحقق من name
    final rawName = json['name'];
    if (rawName == null || rawName is! String || rawName.trim().isEmpty) {
      throw const FormatException('Skill manifest requires a non-empty string "name".');
    }
    final name = rawName.trim();

    // 2. التحقق من display_name
    final rawDisplayName = json['display_name'];
    if (rawDisplayName == null || rawDisplayName is! String || rawDisplayName.trim().isEmpty) {
      throw const FormatException('Skill manifest requires a non-empty string "display_name".');
    }
    final displayName = rawDisplayName.trim();

    // 3. التحقق من description
    final rawDesc = json['description'];
    if (rawDesc == null || rawDesc is! String || rawDesc.trim().isEmpty) {
      throw const FormatException('Skill manifest requires a non-empty string "description".');
    }
    final description = rawDesc.trim();

    // 4. التحقق من endpoint
    final rawEndpoint = json['endpoint'];
    if (rawEndpoint == null || rawEndpoint is! String || rawEndpoint.trim().isEmpty) {
      throw const FormatException('Skill manifest requires a non-empty string "endpoint".');
    }
    final endpoint = rawEndpoint.trim();
    final parsedUri = Uri.tryParse(endpoint);
    if (parsedUri == null || !parsedUri.hasScheme || !parsedUri.hasAuthority) {
      throw FormatException('Invalid endpoint URL in manifest: "$endpoint"');
    }

    // 5. التحقق من input_schema
    final rawSchema = json['input_schema'];
    if (rawSchema == null || rawSchema is! Map) {
      throw const FormatException('Skill manifest requires an "input_schema" object.');
    }
    final inputSchema = Map<String, dynamic>.from(rawSchema);

    // 6. الصلاحيات (اختياري - قائمة نصوص)
    final permissions = <String>[];
    if (json['permissions'] is List) {
      for (final p in json['permissions'] as List) {
        if (p is String && p.trim().isNotEmpty) {
          permissions.add(p.trim().toLowerCase());
        }
      }
    }

    // 7. الإصدار (افتراضي: 1.0.0)
    final version = (json['version'] is String && (json['version'] as String).trim().isNotEmpty)
        ? (json['version'] as String).trim()
        : '1.0.0';

    // 8. أمر التشغيل (اختياري)
    final String? startCommand = (json['start_command'] is String && (json['start_command'] as String).trim().isNotEmpty)
        ? (json['start_command'] as String).trim()
        : null;

    return SkillManifest(
      name: name,
      displayName: displayName,
      description: description,
      endpoint: endpoint,
      inputSchema: inputSchema,
      permissions: permissions,
      version: version,
      startCommand: startCommand,
      folderPath: folderPath,
    );
  }

  /// إنشاء من نص JSON
  factory SkillManifest.fromRawJson(String rawJson, {required String folderPath}) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Skill manifest root must be a JSON object.');
    }
    return SkillManifest.fromJson(decoded, folderPath: folderPath);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'display_name': displayName,
      'description': description,
      'endpoint': endpoint,
      'input_schema': inputSchema,
      'permissions': permissions,
      'version': version,
      if (startCommand != null) 'start_command': startCommand,
      'folder_path': folderPath,
    };
  }

  @override
  String toString() => 'SkillManifest(name: $name, version: $version, endpoint: $endpoint)';
}
