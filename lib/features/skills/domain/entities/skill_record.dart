import 'skill_manifest.dart';

/// يمثل سجل الـ Skill المخزن في قاعدة البيانات مع حالته الحالية.
class SkillRecord {
  final SkillManifest manifest;

  /// هل تم اعتماد وموافقة المستخدم صراحة على هذا الـ Skill؟
  final bool isApproved;

  /// هل الـ Skill مفعّل حالياً ومتاح للنموذج؟
  final bool isEnabled;

  /// رسالة آخر خطأ (مثلاً عند انهيار العملية الفرعية مرتين متتاليتين)
  final String? lastError;

  final DateTime createdAt;
  final DateTime updatedAt;

  const SkillRecord({
    required this.manifest,
    this.isApproved = false,
    this.isEnabled = false,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  SkillRecord copyWith({
    SkillManifest? manifest,
    bool? isApproved,
    bool? isEnabled,
    String? lastError,
    DateTime? updatedAt,
  }) {
    return SkillRecord(
      manifest: manifest ?? this.manifest,
      isApproved: isApproved ?? this.isApproved,
      isEnabled: isEnabled ?? this.isEnabled,
      lastError: lastError,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() =>
      'SkillRecord(name: ${manifest.name}, approved: $isApproved, enabled: $isEnabled)';
}
