import 'package:flutter/material.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';

/// بطاقة تفاعلية عصرية وأنيقة لعرض خطة العمل والمهام الفرعية الذرية (TaskPlan Card)
/// تدعم عرض التقدم الحقيقي وأزرار اعتماد الخطة أو إلغائها.
class TaskPlanCard extends StatelessWidget {
  final TaskPlan plan;
  final bool isAwaitingApproval;
  final VoidCallback? onApprove;
  final VoidCallback? onCancel;

  const TaskPlanCard({
    super.key,
    required this.plan,
    this.isAwaitingApproval = false,
    this.onApprove,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final completedCount = plan.completedCount;
    final totalCount = plan.taskList.length;
    final ratio = plan.completionRatio;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: DesignTokens.space8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: isAwaitingApproval
              ? (isDark ? Colors.blue.shade700 : Colors.blue.shade300)
              : border,
          width: isAwaitingApproval ? 1.5 : DesignTokens.hairline,
        ),
        boxShadow: isAwaitingApproval
            ? [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: isDark ? 0.2 : 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(DesignTokens.space12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(DesignTokens.space4),
                  decoration: BoxDecoration(
                    color: isDark ? DesignTokens.bgDark : DesignTokens.surfaceInputLight,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: DesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.planSummary?.isNotEmpty == true
                            ? plan.planSummary!
                            : 'خطة العمل (Plan-and-Execute)',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeBase,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAwaitingApproval
                            ? 'تم إعداد الخطة وتنتظر اعتمادك للبدء'
                            : '$completedCount من أصل $totalCount مهام فرعية مكتملة (${(ratio * 100).toInt()}%)',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isAwaitingApproval && totalCount > 0)
                  _buildProgressBadge(ratio, isDark),
              ],
            ),
          ),

          // ── Progress Bar ────────────────────────────────────────────────────
          if (!isAwaitingApproval && totalCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 4,
                  backgroundColor: isDark
                      ? DesignTokens.borderDark
                      : DesignTokens.surfaceInputLight,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    plan.isFullyCompleted
                        ? (isDark ? DesignTokens.statusSuccessDark : DesignTokens.statusSuccessLight)
                        : (isDark ? Colors.blue.shade400 : Colors.blue.shade600),
                  ),
                ),
              ),
            ),

          const SizedBox(height: DesignTokens.space8),

          // ── Sub-tasks List ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space12),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: plan.taskList.length,
              separatorBuilder: (_, _) => const SizedBox(height: DesignTokens.space4),
              itemBuilder: (ctx, i) {
                final subTask = plan.taskList[i];
                return _SubTaskItem(
                  subTask: subTask,
                  displayIndex: i + 1,
                  isDark: isDark,
                  primary: primary,
                  secondary: secondary,
                );
              },
            ),
          ),

          // ── Awaiting Approval Action Banner ─────────────────────────────────
          if (isAwaitingApproval) ...[
            const SizedBox(height: DesignTokens.space12),
            Container(
              padding: const EdgeInsets.all(DesignTokens.space12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blue.withValues(alpha: 0.12)
                    : Colors.blue.withValues(alpha: 0.06),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.blue.shade900 : Colors.blue.shade100,
                    width: DesignTokens.hairline,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(DesignTokens.radiusMd),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                      ),
                      const SizedBox(width: DesignTokens.space4),
                      Expanded(
                        child: Text(
                          'تفضل بمراجعة الخطوات أعلاه. هل تعتمد الخطة للبدء في تنفيذها؟',
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeSm,
                            fontWeight: FontWeight.w500,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.space12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onCancel != null)
                        OutlinedButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(Icons.close_rounded, size: 14),
                          label: const Text('إلغاء المهمة'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: secondary,
                            side: BorderSide(color: border),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      const SizedBox(width: DesignTokens.space8),
                      if (onApprove != null)
                        ElevatedButton.icon(
                          onPressed: onApprove,
                          icon: const Icon(Icons.code_rounded, size: 16),
                          label: const Text('تنفيذ بوضع الكود'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.blue.shade700
                                : Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: DesignTokens.space12),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBadge(double ratio, bool isDark) {
    final isDone = ratio >= 1.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDone
            ? (isDark ? Colors.green.withValues(alpha: 0.2) : Colors.green.shade50)
            : (isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : Icons.sync_rounded,
            size: 13,
            color: isDone
                ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                : (isDark ? Colors.blue.shade300 : Colors.blue.shade700),
          ),
          const SizedBox(width: 4),
          Text(
            isDone ? 'مكتملة بالكامل' : '${(ratio * 100).toInt()}%',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              fontWeight: FontWeight.w600,
              color: isDone
                  ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                  : (isDark ? Colors.blue.shade300 : Colors.blue.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTaskItem extends StatelessWidget {
  final SubTask subTask;
  final int displayIndex;
  final bool isDark;
  final Color primary;
  final Color secondary;

  const _SubTaskItem({
    required this.subTask,
    required this.displayIndex,
    required this.isDark,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final status = subTask.status;

    Color iconColor;
    Widget statusWidget;

    switch (status) {
      case SubTaskStatus.pending:
        iconColor = secondary;
        statusWidget = Icon(
          Icons.radio_button_unchecked_rounded,
          size: 14,
          color: iconColor,
        );
        break;
      case SubTaskStatus.inProgress:
        iconColor = isDark ? Colors.blue.shade400 : Colors.blue.shade600;
        statusWidget = SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
          ),
        );
        break;
      case SubTaskStatus.completed:
        iconColor = isDark ? Colors.green.shade400 : Colors.green.shade600;
        statusWidget = Icon(
          Icons.check_circle_rounded,
          size: 15,
          color: iconColor,
        );
        break;
      case SubTaskStatus.failed:
        iconColor = isDark ? Colors.red.shade400 : Colors.red.shade600;
        statusWidget = Icon(
          Icons.error_outline_rounded,
          size: 15,
          color: iconColor,
        );
        break;
      case SubTaskStatus.skipped:
        iconColor = secondary;
        statusWidget = Icon(
          Icons.remove_circle_outline_rounded,
          size: 14,
          color: iconColor,
        );
        break;
    }

    final isCurrent = status == SubTaskStatus.inProgress;
    final isDone = status == SubTaskStatus.completed;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space8,
        vertical: DesignTokens.space4,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? (isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.shade50)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: statusWidget,
          ),
          const SizedBox(width: DesignTokens.space8),
          Text(
            '$displayIndex.',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeSm,
              fontWeight: FontWeight.w600,
              color: isCurrent ? primary : secondary,
              fontFamily: DesignTokens.fontFamilyMono,
            ),
          ),
          const SizedBox(width: DesignTokens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subTask.description,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSm,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone
                        ? secondary
                        : (isCurrent ? primary : primary),
                  ),
                ),
                if (subTask.retryCount > 0 && status != SubTaskStatus.completed) ...[
                  const SizedBox(height: 2),
                  Text(
                    'إعادة المحاولة ${subTask.retryCount}/${subTask.maxRetries} (Exponential Backoff)',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeXs,
                      color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                    ),
                  ),
                ],
                if (subTask.errorMessage != null && status == SubTaskStatus.failed) ...[
                  const SizedBox(height: 2),
                  Text(
                    'الخطأ: ${subTask.errorMessage}',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeXs,
                      color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                    ),
                  ),
                ],
                if (subTask.result != null && subTask.result!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'النتيجة: ${subTask.result}',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeXs,
                      color: secondary,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
