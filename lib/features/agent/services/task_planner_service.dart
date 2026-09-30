import 'dart:convert';

import 'package:khwarizmi/core/execution/execution_types.dart';
import 'package:khwarizmi/core/execution/retry_policy.dart';
import 'package:khwarizmi/core/execution/stream_collector.dart';
import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:khwarizmi/features/providers/data/provider_registry.dart';
import 'package:uuid/uuid.dart';

/// خدمة التخطيط (Planner Node) — المرحلة الأولى من نمط Plan-and-Execute.
///
/// تعمل الآن على خط التنفيذ الموحّد: [StreamCollector] (بلا سباق إلغاء/اكتمال)
/// + [RetryExecutor] (بلا سكوت أبدي) — لا تتجمد أبداً ولا تفشل صامتة.
class TaskPlannerService {
  static const _uuid = Uuid();
  static const int maxSubTasks = 20;

  static final _log = Logger.instance;

  /// يولّد خطة عبر بث المزوّد مع مهلة سماح وإعادة محاولة حتمية.
  ///
  /// يرجع [TaskPlan] — عند أي فشل نهائي تُرجع خطة احتياطية أحادية الخطوة
  /// (لا يُوقف الفشل التخطيطي المهمة كلها؛ التنفيذ الموحّد يكمل بالهدف مباشرة).
  static Future<TaskPlan> generatePlan({
    required String taskId,
    required String goal,
    required String providerId,
    required String modelName,
    required String apiKey,
  }) async {
    final cid = _log.newCorrelationId();
    _log.info(
      'TaskPlannerService',
      'Generating plan',
      correlationId: cid,
      meta: {'goal': goal, 'provider': providerId, 'model': modelName},
    );

    try {
      final provider = ProviderRegistry.getProvider(providerId);

      const systemPrompt = '''
أنت مخطط ذكاء اصطناعي متخصص في تفكيك المهام البرمجية والهندسية المعقدة إلى خطوات فرعية ذرية وواضحة (Plan-and-Execute).
مهمتك: تحليل الهدف المطلوب وتقسيمه إلى قائمة مرتبة من المهام الفرعية الدقيقة بلغة عربية واضحة ومباشرة.

قواعد التخطيط الإلزامية:
1. استخراج القرارات المعمارية المفصلية: أي قرار معماري حاسم (مثل: مكان إنشاء الواجهة، إنشاء حزمة منفصلة، تفضيل تقنية معينة) يجب استخراجه صراحة وصياغته كسطر صريح في ملخص الخطة (planSummary) أو كخطوة مستقلة، وألا يبقى مدفوناً في التفكير الداخلي فقط.
2. كل مهمة فرعية (Subtask) يجب أن تكون ذرية ومحددة (مثال: "قراءة بنية المشروع"، "كتابة واجهة التحويل"، "إضافة زر التنزيل").
3. المهام يجب أن تكون مرتبة منطقياً ومتسلسلة دون تداخل.
4. صياغة الخطوات للمستخدم: يجب أن تكون أوصاف المهام مكتوبة بصيغة مفهومة للمستخدم النهائي، وتُعرض باللغة العربية المباشرة.
5. الحد الأقصى للمهام الفرعية: 20 مهمة.

أجب فقط بـ JSON صالح بالشكل التالي دون نصوص إضافية:
{
  "planSummary": "ملخص الخطة والقرار المعماري المعتمد",
  "architecturalDecision": "القرار المعماري إن وجد (اختياري)",
  "tasks": [
    {"description": "وصف المهمة الفرعية"}
  ]
}
''';

      final history = [
        ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.user,
          content: 'الهدف المطلوب تفكيكه:\n\n$goal',
          timestamp: DateTime.now(),
        ),
      ];

      final collector = StreamCollector(
        correlationId: cid,
        context: 'TaskPlannerService',
      );
      final retry = RetryExecutor(context: 'TaskPlannerService');

      final outcome = await retry.execute<StreamCollectionResult>(
        policy: RetryPolicy.apiStream,
        correlationId: cid,
        operation: (attempt) async {
          final result = await collector.collect(
            provider.sendMessage(
              history: history,
              availableTools: const [],
              systemPrompt: systemPrompt,
              apiKey: apiKey,
              modelName: modelName,
            ),
          );
          if (result.completed && result.hasUsableContent) {
            return RetryOutcome(value: result, attempts: attempt);
          }
          return RetryOutcome(
            failure:
                result.failure ??
                const ExecutionFailure(
                  code: ExecutionFailureCode.emptyResponse,
                  detail: 'Planner returned no usable content',
                  isRetryable: true,
                ),
            attempts: attempt,
          );
        },
      );

      if (!outcome.succeeded) {
        _log.warn(
          'TaskPlannerService',
          'Planning failed after retries — using fallback single-step plan',
          correlationId: cid,
          meta: {
            'attempts': outcome.attempts,
            'code': outcome.failure?.code.name,
          },
        );
        return _fallbackPlan(taskId, goal);
      }

      final rawResponse = outcome.value!.text.trim();
      if (rawResponse.isEmpty) {
        return _fallbackPlan(taskId, goal);
      }

      final rawJson = _extractJson(rawResponse);
      if (rawJson == null) {
        _log.warn(
          'TaskPlannerService',
          'Planner response not valid JSON — using fallback plan',
          correlationId: cid,
        );
        return _fallbackPlan(taskId, goal);
      }

      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      final rawSummary = decoded['planSummary'] as String?;
      final archDecision = decoded['architecturalDecision'] as String?;
      final summary =
          (rawSummary != null &&
              archDecision != null &&
              archDecision.trim().isNotEmpty)
          ? '$rawSummary\n\n📌 قرار معماري: ${archDecision.trim()}'
          : (rawSummary ?? archDecision);

      // إصلاح مفتاح JSON: الـ prompt يطلب "tasks" — كان الكود القديم يقرأ
      // "taskList" فلا يطابق الرد أبداً ويسقط دائماً للخطة الاحتياطية.
      final rawTasks = decoded['tasks'] as List<dynamic>?;
      if (rawTasks == null || rawTasks.isEmpty) {
        return _fallbackPlan(taskId, goal);
      }

      final subTasks = rawTasks.take(maxSubTasks).toList().asMap().entries.map((
        entry,
      ) {
        final desc =
            (entry.value as Map<String, dynamic>)['description'] as String? ??
            '';
        return SubTask(id: _uuid.v4(), index: entry.key, description: desc);
      }).toList();

      _log.info(
        'TaskPlannerService',
        'Plan generated',
        correlationId: cid,
        meta: {'subTasks': subTasks.length, 'summary': summary ?? ''},
      );

      return TaskPlan(
        taskId: taskId,
        goal: goal,
        taskList: subTasks,
        createdAt: DateTime.now(),
        planSummary: summary,
      );
    } catch (e, st) {
      _log.error(
        'TaskPlannerService',
        'Unexpected planning error — using fallback plan',
        correlationId: cid,
        stackTrace: st,
        meta: {'error': e.toString()},
      );
      return _fallbackPlan(taskId, goal);
    }
  }

  static String? _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) return null;
    try {
      jsonDecode(raw.substring(start, end + 1));
      return raw.substring(start, end + 1);
    } catch (_) {
      return null;
    }
  }

  static TaskPlan _fallbackPlan(String taskId, String goal) {
    return TaskPlan(
      taskId: taskId,
      goal: goal,
      taskList: [SubTask(id: _uuid.v4(), index: 0, description: goal)],
      createdAt: DateTime.now(),
      planSummary: 'خطة مباشرة',
    );
  }
}
