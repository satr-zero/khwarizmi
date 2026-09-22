import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/skills/services/text_skill_service.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

/// أداة تحميل وقراءة الدليل الإرشادي الكامل لمهارة نصية (Text Skill) عند الحاجة فقط.
class LoadTextSkillTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'load_text_skill',
        description:
            'تحميل وقراءة دليل التعليمات الكامل لمهارة نصية إرشادية بالاسم، عندما يتبين من الفهرس الخفيف في السياق أن المهارة مرتبطة بطلب المستخدم.',
        parameters: {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description':
                  'اسم المهارة النصية المطلوب قراءة إرشاداتها الكاملة (اختر الاسم بدقة من قائمة المهارات النصية المتاحة في السياق).'
            }
          },
          'required': ['name']
        },
        isControlTool: false,
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final name = arguments['name'];
    if (name == null || name is! String || name.trim().isEmpty) {
      return '{"error": "يجب تحديد اسم المهارة النصية (name)."}';
    }
    return await TextSkillService.instance.loadSkillContent(name.trim());
  }
}
