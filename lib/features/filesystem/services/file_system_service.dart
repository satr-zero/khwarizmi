import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/core/security/secure_storage_service.dart';

/// Sandboxed File System Service for Khwarizmi AI Agent.
///
/// Enforces path restrictions: by default all file operations are restricted to
/// `%USERPROFILE%\Documents\Khwarizmi\`, with an optional user-selected directory
/// configured in Settings.
///
/// Any attempt to escape the allowed directory via path traversal (`..` or external
/// paths) is strictly rejected with a clear JSON error.
class FileSystemService {
  static final FileSystemService instance = FileSystemService._internal();
  FileSystemService._internal();

  /// Gets the default sandboxed root directory.
  static String get defaultAllowedDirectory {
    final userProfile = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return p.canonicalize(p.join(userProfile, 'Documents', 'Khwarizmi'));
  }

  /// Retrieves the active allowed directory (user-configured or default).
  Future<String> getAllowedDirectory() async {
    final customDir = await SecureStorageService.getAllowedFilesDirectory();
    if (customDir != null && customDir.trim().isNotEmpty) {
      return p.canonicalize(customDir.trim());
    }
    return defaultAllowedDirectory;
  }

  /// Sets a new allowed directory configured explicitly by the user.
  Future<void> setAllowedDirectory(String directoryPath) async {
    final canonical = p.canonicalize(directoryPath.trim());
    await SecureStorageService.saveAllowedFilesDirectory(canonical);
    final dir = Directory(canonical);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Validates whether [requestedPath] is safely inside [allowedDir].
  ///
  /// Prevents any path traversal attempts (e.g. `..\..\Windows`).
  bool isPathAllowed(String requestedPath, String allowedDir) {
    final canonicalAllowed = p.canonicalize(allowedDir);
    final resolvedPath = p.isAbsolute(requestedPath)
        ? p.canonicalize(requestedPath)
        : p.canonicalize(p.join(canonicalAllowed, requestedPath));

    // Must be equal to allowed directory or reside as a child inside it
    if (resolvedPath == canonicalAllowed) return true;
    final prefix = canonicalAllowed.endsWith(p.separator)
        ? canonicalAllowed
        : '$canonicalAllowed${p.separator}';
    return resolvedPath.startsWith(prefix);
  }

  /// Resolves [requestedPath] within the allowed directory and validates sandbox safety.
  ///
  /// Returns the canonical path if valid, or null if outside the sandbox.
  Future<String?> resolveAndValidatePath(String requestedPath) async {
    final allowedDir = await getAllowedDirectory();
    final canonicalAllowed = p.canonicalize(allowedDir);
    final resolvedPath = p.isAbsolute(requestedPath)
        ? p.canonicalize(requestedPath)
        : p.canonicalize(p.join(canonicalAllowed, requestedPath));

    if (isPathAllowed(resolvedPath, canonicalAllowed)) {
      return resolvedPath;
    }
    return null;
  }

  /// Writes text [content] to [filePath].
  ///
  /// Rejects any attempt to write outside the allowed directory.
  Future<String> writeFile(String filePath, String content) async {
    final validPath = await resolveAndValidatePath(filePath);
    if (validPath == null) {
      return jsonEncode({'error': 'الوصول مرفوض خارج المجلد المسموح به'});
    }

    try {
      final file = File(validPath);
      await file.parent.create(recursive: true);
      final bytes = utf8.encode(content);
      await file.writeAsBytes(bytes, flush: true);

      return jsonEncode({
        'status': 'success',
        'message': 'تم حفظ الملف بنجاح',
        'path': validPath,
        'bytes_written': bytes.length,
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل كتابة الملف: $e'});
    }
  }

  /// Reads text content from [filePath].
  ///
  /// Rejects any attempt to read outside the allowed directory.
  Future<String> readFile(String filePath) async {
    final validPath = await resolveAndValidatePath(filePath);
    if (validPath == null) {
      return jsonEncode({'error': 'الوصول مرفوض خارج المجلد المسموح به'});
    }

    try {
      final file = File(validPath);
      if (!await file.exists()) {
        return jsonEncode({'error': 'الملف غير موجود'});
      }

      final content = await file.readAsString();
      return jsonEncode({
        'status': 'success',
        'path': validPath,
        'content': content,
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل قراءة الملف: $e'});
    }
  }
}
