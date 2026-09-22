import 'dart:convert';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

/// أداة تمكّن النموذج من اتخاذ القرار بنفسه لبدء مهمة مستقلة متعددة الخطوات
class StartAutonomousTaskTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'start_autonomous_task',
    description:
        'استدعِ هذه الأداة عندما تقرر أن طلب المستخدم يمثل هدفاً مركباً يتطلب تنفيذاً مستقلاً '
        'متعدد الخطوات (مثل: البحث المعمق، تصفح مواقع متعددة، تنزيل ملفات أو حفظ تقارير، '
        'أو إجراءات تتابعية). سيتولى محرك التنفيذ المستقل تنفيذ الخطوات تباعاً وعرض بطاقات '
        'الأدوات والتفكير للمستخدم في نفس المحادثة حتى إتمام الهدف.',
    parameters: {
      'type': 'object',
      'properties': {
        'goal': {
          'type': 'string',
          'description': 'الهدف الواضح والدقيق المراد إنجازه بالتفصيل.',
        },
      },
      'required': ['goal'],
    },
    isControlTool: false, // تتاح للشات العادي
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final goal = arguments['goal'] as String? ?? '';
    return jsonEncode({
      'status': 'task_initiated',
      'goal': goal,
    });
  }
}

/// أداة تمكّن النموذج من استئناف مهمة معلقة بسؤال إذا قرر أن المستخدم أجاب عليه
class ResumeTaskTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'resume_task',
    description:
        'استدعِ هذه الأداة فقط عندما تقرر بوعي أن رسالة المستخدم الحالية تمثل رداً أو إجابة '
        'حقيقية على السؤال المعلق لمهمة تنتظر رده (waitingForUser). '
        'إذا كانت رسالة المستخدم تتحدث عن شيء آخر تماماً، لا تستدعِ هذه الأداة وأجب عن سؤاله بشكل طبيعي.',
    parameters: {
      'type': 'object',
      'properties': {
        'taskId': {
          'type': 'string',
          'description': 'معرف المهمة المعلقة المراد استئنافها.',
        },
        'answer': {
          'type': 'string',
          'description': 'رد أو توجيه المستخدم لاستكمال المهمة.',
        },
      },
      'required': ['taskId', 'answer'],
    },
    isControlTool: false, // تتاح للشات العادي
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final taskId = arguments['taskId'] as String? ?? '';
    final answer = arguments['answer'] as String? ?? '';
    return jsonEncode({
      'status': 'task_resumed',
      'taskId': taskId,
      'answer': answer,
    });
  }
}
