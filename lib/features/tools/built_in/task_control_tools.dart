import 'dart:convert';

import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

/// أدوات التحكم الخاصة بمحرك التنفيذ المستقل.
///
/// هذه الأدوات تظهر للنموذج ضمن قائمة الأدوات المتاحة أثناء المهام المستقلة،
/// لكنها لا تُنفَّذ عبر [ToolRegistry] العادي — بل يعترضها [TaskExecutionEngine]
/// مباشرة ويعالجها بمنطق خاص (إيقاف الحلقة، إرسال إشعار، إنهاء المهمة).

// ─────────────────────────────────────────────────────────────────────────────
// ask_user — يوقف الحلقة وينتظر رد المستخدم
// ─────────────────────────────────────────────────────────────────────────────

class AskUserTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'ask_user',
    description:
        'أوقِف التنفيذ المستقل فوراً واسأل المستخدم سؤالاً محدداً تحتاج إجابته لاستكمال المهمة. '
        'استخدم هذه الأداة فقط عندما تكون هناك معلومة ناقصة بشكل حقيقي تمنع الاستمرار. '
        'عند وصول رد المستخدم، ستُستأنَف المهمة تلقائياً من نفس النقطة.',
    parameters: {
      'type': 'object',
      'properties': {
        'question': {
          'type': 'string',
          'description': 'السؤال الواضح والمحدد الذي تحتاج إجابته من المستخدم.',
        },
        'options': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'قائمة خيارات محددة للمستخدم للاختيار منها إن وُجدت.',
        },
        'default_option': {
          'type': 'string',
          'description': 'الخيار الافتراضي المقترح في حال انقضاء مهلة الـ 30 ثانية (للأسئلة غير الحرجة فقط).',
        },
        'critical': {
          'type': 'boolean',
          'description': 'حدد true إذا كان السؤال يتعلق بقرار حرج، أمان، حذف، أو إجراء لا رجعة فيه، ولا يجوز تجاوزه تلقائياً.',
        },
      },
      'required': ['question'],
    },
    isControlTool: true,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    // لن يُستدعى مباشرةً — يُعترض من TaskExecutionEngine
    final question = arguments['question'] as String? ?? '';
    return jsonEncode({'control': 'ask_user', 'question': question});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// report_progress — تحديث حالة غير مُوقِف
// ─────────────────────────────────────────────────────────────────────────────

class ReportProgressTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'report_progress',
    description:
        'أرسِل تحديث حالة اختيارياً للمستخدم دون إيقاف التنفيذ المستقل. '
        'استخدمه بعد إتمام خطوة مهمة لإبقاء المستخدم على اطلاع أثناء عملك. '
        'لا تستخدمه بشكل مفرط — مرة أو مرتين لكل مهمة كافية.',
    parameters: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description': 'رسالة تقدم موجزة تصف ما أنجزته حتى الآن.',
        },
      },
      'required': ['message'],
    },
    isControlTool: true,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    // لن يُستدعى مباشرةً — يُعترض من TaskExecutionEngine
    final message = arguments['message'] as String? ?? '';
    return jsonEncode({'control': 'report_progress', 'message': message});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// complete_task — ينهي المهمة رسمياً
// ─────────────────────────────────────────────────────────────────────────────

class CompleteTaskTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'complete_task',
    description:
        'أنهِ المهمة المستقلة رسمياً عندما تكون قد أتممت الهدف بالكامل. '
        'قدم ملخصاً شاملاً واضحاً لكل ما أنجزته والنتائج التي توصلت إليها. '
        'هذه الأداة تُطلق إشعار Windows للمستخدم إن كانت النافذة مصغرة. '
        // إصلاح 02: داخل خطة معتمدة (مهام فرعية) لا تستدعِ هذه الأداة —
        // أنهِ المهمة الفرعية بملخص نصي خالص دون أدوات، وإتمام الخطة
        // يُدار تلقائياً بعد اكتمال جميع المهام الفرعية.
        'ملاحظة: عند العمل ضمن خطة معتمدة (مهمة فرعية) لا تستدعِها — '
        'أنهِ المهمة الفرعية بملخص نصي فقط دون أي أداة.',
    parameters: {
      'type': 'object',
      'properties': {
        'summary': {
          'type': 'string',
          'description':
              'تقرير نهائي شامل يتضمن: ما تم إنجازه، النتائج الرئيسية، '
              'وأي توصيات أو خطوات تالية مقترحة.',
        },
      },
      'required': ['summary'],
    },
    isControlTool: true,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    // لن يُستدعى مباشرةً — يُعترض من TaskExecutionEngine
    final summary = arguments['summary'] as String? ?? '';
    return jsonEncode({'control': 'complete_task', 'summary': summary});
  }
}
