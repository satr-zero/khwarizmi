import 'dart:convert';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/filesystem/services/file_system_service.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

/// Tool to write text content to a file inside the sandboxed directory.
class WriteFileTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'write_file',
        description:
            'Creates or overwrites a text file strictly inside Khwarizmi\'s sandboxed directory (%USERPROFILE%\\Documents\\Khwarizmi\\ by default). Any attempt to write outside the allowed folder is strictly rejected.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'path': {
              'type': 'STRING',
              'description': 'File path (e.g., notes.txt, summaries/report.md)',
            },
            'content': {
              'type': 'STRING',
              'description': 'Text content to write into the file',
            },
          },
          'required': ['path', 'content'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path']?.toString();
    final content = arguments['content']?.toString();

    if (path == null || path.trim().isEmpty) {
      return jsonEncode({'error': 'مسار الملف (path) مطلوب'});
    }
    if (content == null) {
      return jsonEncode({'error': 'محتوى الملف (content) مطلوب'});
    }

    return await FileSystemService.instance.writeFile(path.trim(), content);
  }
}

/// Tool to read text content from a file inside the sandboxed directory.
class ReadFileTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'read_file',
        description:
            'Reads a text file strictly from within Khwarizmi\'s sandboxed directory (%USERPROFILE%\\Documents\\Khwarizmi\\ by default). Path traversal or reading outside the allowed directory is rejected.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'path': {
              'type': 'STRING',
              'description': 'File path to read (e.g., notes.txt, report.md)',
            },
          },
          'required': ['path'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path']?.toString();
    if (path == null || path.trim().isEmpty) {
      return jsonEncode({'error': 'مسار الملف (path) مطلوب'});
    }

    return await FileSystemService.instance.readFile(path.trim());
  }
}
