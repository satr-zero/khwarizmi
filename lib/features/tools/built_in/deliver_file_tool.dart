import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/filesystem/services/file_system_service.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

/// أداة تسليم الملفات للمستخدم كبطاقات تفاعلية جاهزة للمعاينة والتحميل.
class DeliverFileTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'deliver_file',
        description:
            'يُنشئ ويُسلّم ملفاً للمستخدم ليظهر فوراً في المحادثة كبطاقة ملف تفاعلية قابلة للمعاينة في اللوحة الجانبية والتحميل. '
            'استخدم هذه الأداة دائماً وبلا تردد عندما يطلب المستخدم: إرسال ملف، إنشاء ملف، كتابة كود في ملف، حفظ تقرير في ملف، إلخ.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'path': {
              'type': 'STRING',
              'description': 'اسم الملف أو مساره النسبي (مثال: welcome.md، audit_report.md، notes.txt).',
            },
            'content': {
              'type': 'STRING',
              'description': 'محتوى الملف الكامل المراد تسليمه للمستخدم.',
            },
            'title': {
              'type': 'STRING',
              'description': 'عنوان وصفي قصير للملف يظهر في البطاقة (اختياري).',
            },
          },
          'required': ['path', 'content'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final rawPath = arguments['path']?.toString();
    final content = arguments['content']?.toString();
    final title = arguments['title']?.toString();

    if (rawPath == null || rawPath.trim().isEmpty) {
      return jsonEncode({'error': 'اسم أو مسار الملف (path) مطلوب'});
    }
    if (content == null) {
      return jsonEncode({'error': 'محتوى الملف (content) مطلوب'});
    }

    final trimmedPath = rawPath.trim();
    final fileName = p.basename(trimmedPath);

    try {
      final activeProject = ProjectManager.instance.activeProject;
      String fullPath;

      if (activeProject != null) {
        // إذا كان هناك مشروع نشط، نحفظه داخل مجلد المشروع
        fullPath = p.isAbsolute(trimmedPath)
            ? trimmedPath
            : p.normalize(p.join(activeProject.rootPath, trimmedPath));
        final file = File(fullPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(content, flush: true);
      } else {
        // بدون مشروع نشط، نحفظه في مجلد خوارزمي للمستندات
        final resJson = await FileSystemService.instance.writeFile(trimmedPath, content);
        final decoded = jsonDecode(resJson);
        if (decoded is Map && decoded.containsKey('path')) {
          fullPath = decoded['path'].toString();
        } else {
          fullPath = p.join(FileSystemService.defaultAllowedDirectory, trimmedPath);
        }
      }

      final bytes = utf8.encode(content).length;

      return jsonEncode({
        'status': 'delivered',
        'file': fileName,
        'path': fullPath,
        'title': title ?? fileName,
        'bytes': bytes,
        'message': 'تم تسليم الملف بنجاح',
      });
    } catch (e) {
      return jsonEncode({'error': 'فشل حفظ وتسليم الملف: $e'});
    }
  }
}
