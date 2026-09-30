import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:khwarizmi/features/agent/presentation/controllers/task_provider.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/chat_controller.dart';

/// أحدث خطة مهام مضمّنة في المحادثة (بطاقة task_plan).
final chatEmbeddedTaskPlanProvider = Provider<TaskPlan?>((ref) {
  final messages = ref.watch(chatProvider).messages;
  for (final m in messages.reversed) {
    final calls = m.toolCalls;
    if (calls == null) continue;
    for (final tc in calls.reversed) {
      if (tc.toolName != 'task_plan') continue;
      try {
        final planData = tc.arguments['plan'];
        if (planData is Map<String, dynamic>) {
          return TaskPlan.fromJson(planData);
        }
        if (planData is Map) {
          return TaskPlan.fromJson(Map<String, dynamic>.from(planData));
        }
        if (tc.result != null && tc.result!.isNotEmpty) {
          final decoded = jsonDecode(tc.result!);
          if (decoded is Map<String, dynamic>) {
            return TaskPlan.fromJson(decoded);
          }
        }
      } catch (_) {}
    }
  }
  return null;
});

/// شريط مهام عصري مدمج فوق منطقة الإدخال — يرتبط حياً بالمحرك والمحادثة.
class LiveTasksHud extends ConsumerStatefulWidget {
  const LiveTasksHud({super.key});

  @override
  ConsumerState<LiveTasksHud> createState() => _LiveTasksHudState();
}

class _LiveTasksHudState extends ConsumerState<LiveTasksHud> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final tasksState = ref.watch(tasksProvider);
    final embeddedPlan = ref.watch(chatEmbeddedTaskPlanProvider);
    final active = tasksState.activeTasks;

    if (active.isEmpty && embeddedPlan == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(
                color: border.withValues(alpha: 0.85),
                width: DesignTokens.hairline,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        DesignTokens.surfaceDark.withValues(alpha: 0.72),
                        DesignTokens.bgDark.withValues(alpha: 0.55),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.82),
                        DesignTokens.surfaceLight.withValues(alpha: 0.65),
                      ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.space12,
                      vertical: DesignTokens.space8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_motion_rounded,
                          size: 16,
                          color: isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade700,
                        ),
                        const SizedBox(width: DesignTokens.space8),
                        Expanded(
                          child: Text(
                            'المهام النشطة (${active.length})',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: DesignTokens.fontSizeSm,
                              color: isDark
                                  ? DesignTokens.textPrimaryDark
                                  : DesignTokens.textPrimaryLight,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.expand_more_rounded
                              : Icons.expand_less_rounded,
                          size: 18,
                          color: isDark
                              ? DesignTokens.textSecondaryDark
                              : DesignTokens.textSecondaryLight,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded) ...[
                  // ── إصلاح جوهري لتخطيط شريط الإدخال ──────────────────────
                  // كانت البطاقة الكاملة للخطة (بكل مهامها الفرعية) تُضمَّن
                  // هنا فتنتفخ منطقة الإدخال إلى ~1000px وتصفر قائمة
                  // الرسائل (RenderFlex overflow). الآن: صفوف المهام النشطة
                  // أولاً (إشارة «هل بدأ التنفيذ»)، وملخص مضغوط للخطة
                  // بدل البطاقة الكاملة، وسقف ارتفاع مع تمرير للأمان.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  ...active.map(
                    (t) => _LiveTaskRow(
                      task: t,
                      // الخطة المطابقة لهذه المهمة (حسب taskId) — لعرض
                      // تقدمها الفعلي بدل عدّاد سقف الخطوات الثابت
                      plan: embeddedPlan?.taskId == t.id ? embeddedPlan : null,
                      isDark: isDark,
                      onCancel: () {
                        ref
                            .read(tasksProvider.notifier)
                            .cancelTask(t.id);
                        // تنظيف حالة البث في الشات إن كانت هذه
                        // هي المهمة النشطة (يمنع التجمد).
                        ref
                            .read(chatProvider.notifier)
                            .handleExternalTaskCancel(t.id);
                      },
                      onResume: t.status == TaskStatus.waitingForUser
                          ? (reply) => ref
                                .read(tasksProvider.notifier)
                                .resumeTask(t.id, reply)
                          : null,
                    ),
                  ),
                          if (embeddedPlan != null)
                            _EmbeddedPlanSummary(
                              plan: embeddedPlan,
                              isDark: isDark,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveTaskRow extends StatelessWidget {
  final Task task;

  /// خطة العمل المرتبطة بهذه المهمة (إن وجدت) — يُعرض تقدمها الفعلي
  /// (X/N خطوة) بدل عدّاد سقف الخطوات الثابت (25) الذي كان يُقرأ خطأً
  /// على أنه "حجم الخطة" وهو ثابت دائماً
  final TaskPlan? plan;
  final bool isDark;
  final VoidCallback onCancel;
  final void Function(String reply)? onResume;

  const _LiveTaskRow({
    required this.task,
    this.plan,
    required this.isDark,
    required this.onCancel,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    // مع خطة مرتبطة: نسبة إنجاز الخطوات الفعلية، وإلا نسبة خطوات المهمة
    final hasPlan = plan != null && plan!.taskId == task.id;
    final ratio = hasPlan ? plan!.completionRatio : task.progressRatio;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space12,
        0,
        DesignTokens.space12,
        DesignTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.goal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: secondary,
                  ),
                ),
              ),
              Text(
                _statusLabel(task.status),
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'إيقاف المهمة',
                onPressed: onCancel,
                icon: Icon(Icons.stop_circle_outlined, color: secondary),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: isDark
                  ? DesignTokens.borderDark
                  : DesignTokens.borderLight,
            ),
          ),
          Text(
            hasPlan
                ? 'خطة العمل: ${plan!.completedCount}/${plan!.taskList.length} خطوة (${(ratio * 100).toInt()}%)'
                : '${(ratio * 100).toInt()}% — ${task.stepCount}/${task.stepCap} خطوة',
            style: TextStyle(fontSize: 10, color: secondary),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(TaskStatus s) {
    switch (s) {
      case TaskStatus.running:
        return 'جاري التنفيذ';
      case TaskStatus.waitingForUser:
        return 'بانتظارك';
      case TaskStatus.pausedAtLimit:
        return 'متوقف مؤقتاً';
      case TaskStatus.completed:
        return 'مكتمل';
      case TaskStatus.failed:
        return 'تعذر';
      case TaskStatus.cancelled:
        return 'ملغى';
    }
  }
}

/// ملخص مضغوط للخطة المضمّنة في المحادثة — سطر واحد + شريط تقدم.
/// البطاقة الكاملة معروضة أصلاً في فقاعة المحادثة؛ تكرارها هنا كان
/// يفجّر تخطيط منطقة الإدخال.
class _EmbeddedPlanSummary extends StatelessWidget {
  final TaskPlan plan;
  final bool isDark;

  const _EmbeddedPlanSummary({required this.plan, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final ratio = plan.completionRatio;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.space12,
        0,
        DesignTokens.space12,
        DesignTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 14,
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
              ),
              const SizedBox(width: DesignTokens.space4),
              Expanded(
                child: Text(
                  'خطة العمل: ${plan.completedCount}/${plan.taskList.length} خطوة مكتملة'
                  '${plan.failedCount > 0 ? ' (${plan.failedCount} فشلت)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: isDark
                  ? DesignTokens.borderDark
                  : DesignTokens.borderLight,
            ),
          ),
        ],
      ),
    );
  }
}
