import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/features/projects/domain/entities/project.dart';

/// نتيجة التحقق من المسار.
sealed class PathValidationResult {
  const PathValidationResult();
}

class ValidPath extends PathValidationResult {
  final String absolutePath;
  const ValidPath(this.absolutePath);
}

class InvalidPath extends PathValidationResult {
  final String reason;
  const InvalidPath(this.reason);
}

/// خدمة قراءة وكتابة ملفات المشروع — مقيَّدة حصرًا بـ [project.rootPath].
///
/// **مبدأ الأمان المركزي:**
/// - لا يُقرأ أو يُكتب أي مسار خارج [project.rootPath] — بغض النظر عن
///   طالب العملية (النموذج، المستخدم، أي طرف آخر).
/// - أي محاولة وصول خارج الجذر تُرفض فورًا بخطأ واضح.
class ProjectFileService {
  ProjectFileService._();

  // ── التحقق من المسار ──────────────────────────────────────────────────────

  /// يحسم المسار (نسبي أو مطلق) ويتحقق أنه داخل [project.rootPath].
  ///
  /// يرفض:
  /// - أي مسار مطلق لا يبدأ بـ [project.rootPath]
  /// - أي مسار يحتوي `..` يتخطى الجذر
  /// - المسارات الفارغة
  static PathValidationResult resolveAndValidatePath(
    Project project,
    String path,
  ) {
    if (path.trim().isEmpty) {
      return const InvalidPath('المسار فارغ');
    }

    final root = p.normalize(project.rootPath);

    // تحسيم المسار: نسبي → مطلق بالنسبة للجذر
    final String resolved;
    if (p.isAbsolute(path)) {
      resolved = p.normalize(path);
    } else {
      resolved = p.normalize(p.join(root, path));
    }

    // التحقق من الاحتواء
    // نستخدم مقارنة lowercase على Windows (نظام ملفات case-insensitive)
    final normalizedRoot = root.toLowerCase();
    final normalizedResolved = resolved.toLowerCase();

    if (!normalizedResolved.startsWith(normalizedRoot)) {
      return InvalidPath(
        'محاولة وصول لمسار خارج مجلد المشروع مرفوضة — '
        'المسار المطلوب: "$resolved" خارج جذر المشروع: "$root"',
      );
    }

    // حماية إضافية: منع path traversal حتى لو بدا المسار داخل الجذر
    if (path.contains('..')) {
      final segments = resolved.split(RegExp(r'[/\\]'));
      if (segments.any((s) => s == '..')) {
        return const InvalidPath('path traversal بـ (..) غير مسموح');
      }
    }

    return ValidPath(resolved);
  }

  /// الحد الأقصى لحجم الملف المسموح بقراءته مباشرة (500 كيلوبايت)
  static const int maxFileSizeBytes = 500 * 1024;

  // ── قراءة ─────────────────────────────────────────────────────────────────

  /// يقرأ محتوى ملف نصي داخل المشروع.
  ///
  /// يُرجع JSON: `{"content": "..."}` أو `{"error": "..."}`.
  static Future<String> readProjectFile(Project project, String path) async {
    final validation = resolveAndValidatePath(project, path);

    if (validation is InvalidPath) {
      return jsonEncode({'error': validation.reason});
    }

    final absolutePath = (validation as ValidPath).absolutePath;

    try {
      final file = File(absolutePath);
      if (!await file.exists()) {
        return jsonEncode({'error': 'الملف غير موجود: $absolutePath'});
      }
      final size = await file.length();
      if (size > maxFileSizeBytes) {
        return jsonEncode({
          'error': 'حجم الملف (${(size / 1024).toStringAsFixed(1)} KB) يتجاوز الحد الأقصى المسموح به (500 KB)',
          'size': size,
          'maxSize': maxFileSizeBytes,
        });
      }
      final content = await file.readAsString(encoding: utf8);
      return jsonEncode({'content': content, 'path': absolutePath});
    } catch (e) {
      debugPrint('[ProjectFileService] readProjectFile error: $e');
      return jsonEncode({'error': 'خطأ في قراءة الملف: $e'});
    }
  }

  /// يقرأ المحتوى الحالي للملف مباشرةً (بدون تغليف JSON) — للاستخدام الداخلي.
  static Future<String?> readRawContent(Project project, String path) async {
    final validation = resolveAndValidatePath(project, path);
    if (validation is InvalidPath) return null;

    final absolutePath = (validation as ValidPath).absolutePath;
    try {
      final file = File(absolutePath);
      if (!await file.exists()) return null;
      if (await file.length() > maxFileSizeBytes) return null;
      return await file.readAsString(encoding: utf8);
    } catch (_) {
      return null;
    }
  }

  // ── كتابة (بعد الموافقة فقط) ─────────────────────────────────────────────

  /// يكتب المحتوى على الملف فعليًا على القرص.
  ///
  /// **يُستدعى فقط بعد موافقة صريحة من المستخدم على الـ Diff.**
  ///
  /// يُرجع JSON: `{"success": true, "path": "..."}` أو `{"error": "..."}`.
  static Future<String> writeProjectFile(
    Project project,
    String absolutePath,
    String content,
  ) async {
    // تحقق إضافي قبل الكتابة
    final root = p.normalize(project.rootPath).toLowerCase();
    final normalizedPath = p.normalize(absolutePath).toLowerCase();

    if (!normalizedPath.startsWith(root)) {
      return jsonEncode({
        'error': 'SECURITY: محاولة كتابة خارج مجلد المشروع — مرفوضة',
      });
    }

    try {
      final file = File(absolutePath);

      // إنشاء المجلدات الوسيطة إذا لم تكن موجودة
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      await file.writeAsString(content, encoding: utf8, flush: true);
      debugPrint('[ProjectFileService] Written: $absolutePath');
      return jsonEncode({'success': true, 'path': absolutePath});
    } catch (e) {
      debugPrint('[ProjectFileService] writeProjectFile error: $e');
      return jsonEncode({'error': 'خطأ في كتابة الملف: $e'});
    }
  }

  // ── استعراض الملفات ───────────────────────────────────────────────────────

  /// يُرجع قائمة محتويات مجلد داخل المشروع.
  ///
  /// يُرجع JSON: `{"entries": [...]}` أو `{"error": "..."}`.
  static Future<String> listProjectFiles(
    Project project,
    String? relativePath,
  ) async {
    final targetPath = relativePath?.trim().isNotEmpty == true
        ? relativePath!
        : '.';

    final validation = resolveAndValidatePath(project, targetPath);
    if (validation is InvalidPath) {
      return jsonEncode({'error': validation.reason});
    }

    final absolutePath = (validation as ValidPath).absolutePath;

    try {
      final dir = Directory(absolutePath);
      if (!await dir.exists()) {
        return jsonEncode({'error': 'المجلد غير موجود: $absolutePath'});
      }

      final entries = <Map<String, dynamic>>[];
      await for (final entity in dir.list()) {
        final isDir = entity is Directory;
        final stat = await entity.stat();
        entries.add({
          'name': p.basename(entity.path),
          'type': isDir ? 'directory' : 'file',
          'size': isDir ? null : stat.size,
          'path': entity.path,
        });
      }

      // مجلدات أولاً، ثم ملفات — أبجديًا
      entries.sort((a, b) {
        if (a['type'] != b['type']) {
          return a['type'] == 'directory' ? -1 : 1;
        }
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      return jsonEncode({'entries': entries, 'path': absolutePath});
    } catch (e) {
      return jsonEncode({'error': 'خطأ في استعراض المجلد: $e'});
    }
  }
}
