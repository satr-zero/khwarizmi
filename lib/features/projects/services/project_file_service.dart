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

  /// الحد الأقصى لعدد الأسطر في القراءة الكاملة لتجنب إغراق السياق
  static const int maxLinesFullRead = 400;

  // ── قراءة ─────────────────────────────────────────────────────────────────

  /// يقرأ محتوى ملف نصي داخل المشروع.
  ///
  /// يدعم القراءة الجزئية بالأسطر لتجنب إغراق سياق النموذج:
  /// - [startLine]: سطر البداية (1-indexed، اختياري)
  /// - [lineCount]: عدد الأسطر المطلوب قراءتها (اختياري، افتراضي 200)
  ///
  /// يُرجع JSON: `{"content": "...", "total_lines": N, "shown_lines": "X-Y"}` أو `{"error": "..."}`.
  static Future<String> readProjectFile(
    Project project,
    String path, {
    int? startLine,
    int? lineCount,
  }) async {
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
          'error':
              'حجم الملف (${(size / 1024).toStringAsFixed(1)} KB) يتجاوز الحد الأقصى المسموح به (500 KB). '
              'استخدم start_line وline_count لقراءة أجزاء محددة.',
          'size': size,
          'maxSize': maxFileSizeBytes,
          'hint': 'مثال: {"path": "$path", "start_line": 1, "line_count": 200}',
        });
      }

      final content = await file.readAsString(encoding: utf8);
      final allLines = content.split('\n');
      final totalLines = allLines.length;

      // ── قراءة جزئية إذا طُلبت أسطر محددة ─────────────────────────────
      if (startLine != null || lineCount != null) {
        final start = ((startLine ?? 1) - 1).clamp(0, totalLines - 1);
        final count = (lineCount ?? 200).clamp(1, 500);
        final end = (start + count).clamp(start, totalLines);
        final selectedLines = allLines.sublist(start, end);
        return jsonEncode({
          'content': selectedLines.join('\n'),
          'path': absolutePath,
          'total_lines': totalLines,
          'shown_lines': '${start + 1}-$end',
          'has_more': end < totalLines,
          'next_start_line': end < totalLines ? end + 1 : null,
        });
      }

      // ── قراءة كاملة — تنبيه إذا كان الملف طويلاً جداً ────────────────
      if (totalLines > maxLinesFullRead) {
        // نقرأ أول 400 سطر تلقائياً ونُعلم النموذج بوجود المزيد
        final preview = allLines.take(maxLinesFullRead).join('\n');
        return jsonEncode({
          'content': preview,
          'path': absolutePath,
          'total_lines': totalLines,
          'shown_lines': '1-$maxLinesFullRead',
          'has_more': true,
          'next_start_line': maxLinesFullRead + 1,
          'warning':
              'الملف يحتوي $totalLines سطراً — عرضت أول $maxLinesFullRead سطراً. '
              'استخدم start_line وline_count لقراءة الأجزاء المتبقية.',
        });
      }

      return jsonEncode({
        'content': content,
        'path': absolutePath,
        'total_lines': totalLines,
        'shown_lines': '1-$totalLines',
        'has_more': false,
      });
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

  // ── بحث في كود المشروع (search_project_code) ────────────────────────────────

  static const Set<String> _searchIgnoredDirs = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.idea',
    '.vscode',
    '.gradle',
    'Pods',
    '.system_generated',
    'target',
    '.next',
    '.nuxt',
    'ephemeral',
    '.fvm',
    '.svn',
    '.hg',
  };

  static const Set<String> _binaryExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.bmp', '.svg',
    '.mp4', '.mov', '.avi', '.mkv', '.mp3', '.wav', '.flac',
    '.zip', '.tar', '.gz', '.7z', '.rar', '.pdf',
    '.exe', '.dll', '.so', '.dylib', '.class', '.jar', '.apk', '.aab', '.ipa',
    '.ttf', '.otf', '.woff', '.woff2', '.eot',
    '.bin', '.dat', '.db', '.sqlite', '.sqlite3',
    '.lock',
  };

  /// يبحث عن نص أو رمز (اسم دالة، كلاس، متغير) أو تعبير نمطي (regex) عبر ملفات المشروع.
  ///
  /// يُرجع JSON يتضمن مسار الملف ورقم السطر وسياق السطر فقط (دون تحميل الملف كاملاً).
  static Future<String> searchProjectCode(
    Project project, {
    required String query,
    String searchType = 'literal',
    String? relativePath,
    int maxResults = 50,
  }) async {
    if (query.trim().isEmpty) {
      return jsonEncode({'error': 'نص البحث (query) مطلوب'});
    }

    final targetPath = relativePath?.trim().isNotEmpty == true
        ? relativePath!
        : '.';

    final validation = resolveAndValidatePath(project, targetPath);
    if (validation is InvalidPath) {
      return jsonEncode({'error': validation.reason});
    }

    final targetAbsolutePath = (validation as ValidPath).absolutePath;

    // تجهيز محرك البحث المطابق
    final RegExp matcher;
    try {
      switch (searchType.toLowerCase()) {
        case 'regex':
          matcher = RegExp(query, caseSensitive: false);
          break;
        case 'symbol':
          final escaped = RegExp.escape(query.trim());
          matcher = RegExp('\\b$escaped\\b', caseSensitive: false);
          break;
        case 'literal':
        default:
          final escaped = RegExp.escape(query);
          matcher = RegExp(escaped, caseSensitive: false);
          break;
      }
    } catch (e) {
      return jsonEncode({'error': 'نمط البحث غير صالح: $e'});
    }

    final rootNorm = p.normalize(project.rootPath);
    final matches = <Map<String, dynamic>>[];
    bool isTruncated = false;

    try {
      final targetType = await FileSystemEntity.type(targetAbsolutePath);
      if (targetType == FileSystemEntityType.notFound) {
        return jsonEncode({'error': 'المسار المحدد غير موجود: $targetPath'});
      }

      final filesToScan = <File>[];

      if (targetType == FileSystemEntityType.file) {
        filesToScan.add(File(targetAbsolutePath));
      } else {
        // فحص تكراري للمجلد مع استبعاد المجلدات المهملة فوراً
        final dir = Directory(targetAbsolutePath);
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;

          final entityPath = entity.path;
          final segments = p.split(p.relative(entityPath, from: rootNorm));

          // استبعاد إذا كان داخل أي مجلد مهمل
          if (segments.any((seg) => _searchIgnoredDirs.contains(seg))) {
            continue;
          }

          // استبعاد الملفات الثنائية
          final ext = p.extension(entityPath).toLowerCase();
          if (_binaryExtensions.contains(ext)) {
            continue;
          }

          filesToScan.add(entity);
        }
      }

      // فرز الملفات لضمان نتائج متسقة
      filesToScan.sort((a, b) => a.path.compareTo(b.path));

      for (final file in filesToScan) {
        if (matches.length >= maxResults) {
          isTruncated = true;
          break;
        }

        try {
          final stat = await file.stat();
          if (stat.size > maxFileSizeBytes) continue;

          final content = await file.readAsString(encoding: const Utf8Codec(allowMalformed: true));
          final lines = content.split('\n');

          for (int i = 0; i < lines.length; i++) {
            final lineText = lines[i];
            if (matcher.hasMatch(lineText)) {
              final lineNum = i + 1; // 1-indexed
              final startCtx = (lineNum - 2).clamp(1, lines.length);
              final endCtx = (lineNum + 2).clamp(1, lines.length);

              final contextLines = <String>[];
              for (int c = startCtx; c <= endCtx; c++) {
                final prefix = c == lineNum ? '> ' : '  ';
                final numPad = '$c'.padLeft(4, ' ');
                contextLines.add('$numPad$prefix${lines[c - 1]}');
              }

              final relPath = p.relative(file.path, from: rootNorm).replaceAll(r'\', '/');

              matches.add({
                'file': relPath,
                'line': lineNum,
                'line_content': lineText.trim(),
                'context_start': startCtx,
                'context_end': endCtx,
                'context': contextLines.join('\n'),
              });

              if (matches.length >= maxResults) {
                isTruncated = true;
                break;
              }
            }
          }
        } catch (_) {
          // تجاوز أي ملف يفشل قراءته (تشفير غير مدعوم، قفل ملفات، إلخ)
          continue;
        }
      }

      return jsonEncode({
        'query': query,
        'search_type': searchType,
        'count': matches.length,
        'truncated': isTruncated,
        'matches': matches,
      });
    } catch (e) {
      return jsonEncode({'error': 'حدث خطأ أثناء البحث في الكود: $e'});
    }
  }
}
