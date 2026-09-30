import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';

/// Represents a deliverable file attached or generated during an assistant turn.
class FileAttachmentInfo {
  final String path;
  final String fileName;
  final String fileType;
  final int? sizeBytes;
  final String? content;

  const FileAttachmentInfo({
    required this.path,
    required this.fileName,
    required this.fileType,
    this.sizeBytes,
    this.content,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'fileName': fileName,
    'fileType': fileType,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (content != null) 'content': content,
  };

  factory FileAttachmentInfo.fromJson(Map<String, dynamic> json) => FileAttachmentInfo(
    path: json['path'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
    fileType: json['fileType'] as String? ?? 'FILE',
    sizeBytes: json['sizeBytes'] as int?,
    content: json['content'] as String?,
  );

  /// يستخرج معلومات الملفات المُنشأة حصراً (write_file, deliver_file, send_file).
  ///
  /// ملاحظة: أدوات تعديل الملفات (propose_file_change, propose_file_patch)
  /// مستثناة عمداً حتى لا يظهر كرت تحميل عند التعديل، بل يُعرض الـ Diff فقط.
  static FileAttachmentInfo? fromToolCall(ToolCallInfo toolCall) {
    final name = toolCall.toolName;
    if (name != 'deliver_file' &&
        name != 'write_file' &&
        name != 'send_file') {
      return null;
    }

    final rawPath = toolCall.arguments['path']?.toString();
    if (rawPath == null || rawPath.trim().isEmpty) return null;

    final trimmedPath = rawPath.trim();
    final fileName = p.basename(trimmedPath);
    final ext = p.extension(fileName).replaceAll('.', '').toUpperCase();
    final fileType = ext.isNotEmpty ? ext : 'FILE';
    final content = toolCall.arguments['content']?.toString() ??
        toolCall.arguments['new_content']?.toString();

    // Check if result returned a canonical/full path
    String resolvedPath = trimmedPath;
    if (toolCall.result != null && toolCall.result!.isNotEmpty) {
      try {
        final decoded = jsonDecode(toolCall.result!);
        if (decoded is Map<String, dynamic>) {
          final resPath = decoded['path']?.toString() ?? decoded['file']?.toString();
          if (resPath != null && resPath.isNotEmpty) {
            resolvedPath = resPath;
          }
        }
      } catch (_) {}
    }

    int? sizeBytes;
    if (content != null) {
      sizeBytes = utf8.encode(content).length;
    }

    return FileAttachmentInfo(
      path: resolvedPath,
      fileName: fileName,
      fileType: fileType,
      sizeBytes: sizeBytes,
      content: content,
    );
  }
}
