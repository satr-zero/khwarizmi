import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/presentation/controllers/task_provider.dart';
import 'package:khwarizmi/features/agent/services/task_execution_engine.dart';

/// لوحة مراقبة وسجل المهام المستقلة — تُعرض كـ Dialog منفصل من الشريط الجانبي
class TasksPanelDialog extends ConsumerStatefulWidget {
  const TasksPanelDialog({super.key});

  @override
  ConsumerState<TasksPanelDialog> createState() => _TasksPanelDialogState();
}

class _TasksPanelDialogState extends ConsumerState<TasksPanelDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tasksState = ref.watch(tasksProvider);

    final bg = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(color: border, width: DesignTokens.hairline),
      ),
      child: SizedBox(
        width: 680,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.space16,
                vertical: DesignTokens.space12,
              ),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  bottom: BorderSide(color: border, width: DesignTokens.hairline),
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(DesignTokens.radiusLg),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.electric_bolt_rounded, size: 16, color: primary),
                  const SizedBox(width: DesignTokens.space8),
                  Text(
                    'سجل ومراقبة المهام المستقلة',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: DesignTokens.fontSizeBase,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  if (tasksState.activeTasks.isNotEmpty)
                    _StatusBadge(
                      label: '${tasksState.activeTasks.length} نشط',
                      isDark: isDark,
                    ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 16, color: secondary),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
            ),

            // ── قائمة المهام ─────────────────────────────────────────────
            Expanded(
              child: tasksState.tasks.isEmpty
                  ? _EmptyState(isDark: isDark)
                  : ListView.separated(
                      padding: const EdgeInsets.all(DesignTokens.space12),
                      itemCount: tasksState.tasks.length,
                      separatorBuilder: (_, index) =>
                          Divider(height: 1, color: border),
                      itemBuilder: (ctx, i) {
                        return _TaskCard(
                          task: tasksState.tasks[i],
                          isDark: isDark,
                          onCancel: () => ref
                              .read(tasksProvider.notifier)
                              .cancelTask(tasksState.tasks[i].id),
                          onExtend: () => ref
                              .read(tasksProvider.notifier)
                              .extendTask(tasksState.tasks[i].id),
                          onReply: (reply) => ref
                              .read(tasksProvider.notifier)
                              .resumeTask(tasksState.tasks[i].id, reply),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TaskCard
// ─────────────────────────────────────────────────────────────────────────────

class _TaskCard extends StatefulWidget {
  final Task task;
  final bool isDark;
  final VoidCallback onCancel;
  final VoidCallback onExtend;
  final void Function(String reply) onReply;

  const _TaskCard({
    required this.task,
    required this.isDark,
    required this.onCancel,
    required this.onExtend,
    required this.onReply,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _expanded = false;
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final primary =
        widget.isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary =
        widget.isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final border =
        widget.isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surface =
        widget.isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row ───────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusIcon(status: t.status, isDark: widget.isDark),
              const SizedBox(width: DesignTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.goal,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeSm,
                        fontWeight: FontWeight.w500,
                        color: primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: DesignTokens.space4),
                    Row(
                      children: [
                        Text(
                          _statusLabel(t.status),
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(width: DesignTokens.space8),
                        // ── عداد الخطوات ─────────────────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.space8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? DesignTokens.surfaceInputDark
                                : DesignTokens.surfaceInputLight,
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusSm),
                            border: Border.all(color: border, width: DesignTokens.hairline),
                          ),
                          child: Text(
                            '${t.stepCount}/${t.stepCap} خطوة',
                            style: TextStyle(
                              fontSize: DesignTokens.fontSizeXs,
                              fontFamily: DesignTokens.fontFamilyMono,
                              color: secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.space8),
                        Text(
                          DateFormat('HH:mm').format(t.createdAt),
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── أزرار الإجراءات ──────────────────────────────────────
              if (t.status == TaskStatus.running ||
                  t.status == TaskStatus.waitingForUser)
                IconButton(
                  icon: Icon(Icons.stop_circle_outlined, size: 16, color: secondary),
                  tooltip: 'إلغاء المهمة',
                  onPressed: widget.onCancel,
                ),

              // زر توسيع سجل الخطوات
              if (t.stepsLog.isNotEmpty)
                IconButton(
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: secondary,
                  ),
                  tooltip: _expanded ? 'إخفاء السجل' : 'عرض السجل',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
            ],
          ),

          // ── شريط تقدم ────────────────────────────────────────────────
          if (t.status == TaskStatus.running || t.status == TaskStatus.pausedAtLimit) ...[
            const SizedBox(height: DesignTokens.space4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: t.status == TaskStatus.running ? null : t.progressRatio,
                backgroundColor: border,
                color: primary,
                minHeight: 2,
              ),
            ),
          ],

          // ── سؤال معلق ────────────────────────────────────────────────
          if (t.status == TaskStatus.waitingForUser && t.pendingQuestion != null) ...[
            const SizedBox(height: DesignTokens.space8),
            Container(
              padding: const EdgeInsets.all(DesignTokens.space12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: border, width: DesignTokens.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '❓ ${t.pendingQuestion}',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: primary),
                          decoration: InputDecoration(
                            hintText: 'ردّك هنا...',
                            hintStyle: TextStyle(color: secondary),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.space8,
                              vertical: DesignTokens.space8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                              borderSide: BorderSide(color: border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                              borderSide: BorderSide(color: border),
                            ),
                          ),
                          onSubmitted: (v) => _submitReply(),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      OutlinedButton(
                        onPressed: _submitReply,
                        child: const Text('إرسال'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ── زر تمديد المهمة عند السقف ─────────────────────────────────
          if (t.status == TaskStatus.pausedAtLimit) ...[
            const SizedBox(height: DesignTokens.space8),
            Container(
              padding: const EdgeInsets.all(DesignTokens.space12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: border, width: DesignTokens.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⏸️ وصلت المهمة للحد الأقصى (${t.stepCap} خطوة) دون إتمام.',
                    style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: primary),
                  ),
                  const SizedBox(height: DesignTokens.space8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: Text('اكمل ${TaskExecutionEngine.defaultStepCap} خطوة إضافية'),
                        onPressed: widget.onExtend,
                      ),
                      const SizedBox(width: DesignTokens.space8),
                      TextButton(
                        onPressed: widget.onCancel,
                        child: const Text('إلغاء'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ── ملخص الإتمام ──────────────────────────────────────────────
          if (t.status == TaskStatus.completed && t.completionSummary != null) ...[
            const SizedBox(height: DesignTokens.space8),
            Container(
              padding: const EdgeInsets.all(DesignTokens.space12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: border, width: DesignTokens.hairline),
              ),
              child: Text(
                t.completionSummary!,
                style: TextStyle(fontSize: DesignTokens.fontSizeSm, color: secondary),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          // ── رسالة الخطأ ───────────────────────────────────────────────
          if (t.status == TaskStatus.failed && t.errorMessage != null) ...[
            const SizedBox(height: DesignTokens.space8),
            Text(
              '⚠️ ${t.errorMessage}',
              style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondary),
            ),
          ],

          // ── سجل الخطوات (قابل للتوسعة) ───────────────────────────────
          if (_expanded && t.stepsLog.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.space8),
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                border: Border.all(color: border, width: DesignTokens.hairline),
              ),
              child: Column(
                children: t.stepsLog
                    .map((step) => _StepLogRow(
                          step: step,
                          isDark: widget.isDark,
                          primary: primary,
                          secondary: secondary,
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _submitReply() {
    final reply = _replyController.text.trim();
    if (reply.isEmpty) return;
    widget.onReply(reply);
    _replyController.clear();
  }

  String _statusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.running: return 'قيد التنفيذ...';
      case TaskStatus.waitingForUser: return 'بانتظار ردك';
      case TaskStatus.completed: return 'مكتملة ✓';
      case TaskStatus.failed: return 'فشلت';
      case TaskStatus.cancelled: return 'ملغاة';
      case TaskStatus.pausedAtLimit: return 'موقوفة عند الحد';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StepLogRow
// ─────────────────────────────────────────────────────────────────────────────

class _StepLogRow extends StatelessWidget {
  final TaskStepLog step;
  final bool isDark;
  final Color primary;
  final Color secondary;

  const _StepLogRow({
    required this.step,
    required this.isDark,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final border =
        isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space12,
        vertical: DesignTokens.space8,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: DesignTokens.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${step.stepIndex}',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              fontFamily: DesignTokens.fontFamilyMono,
              color: secondary,
            ),
          ),
          const SizedBox(width: DesignTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.action,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: primary,
                  ),
                ),
                if (step.toolResult != null)
                  Text(
                    step.toolResult!,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeXs,
                      color: secondary,
                      fontFamily: DesignTokens.fontFamilyMono,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            DateFormat('HH:mm:ss').format(step.timestamp),
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _StatusIcon extends StatefulWidget {
  final TaskStatus status;
  final bool isDark;

  const _StatusIcon({required this.status, required this.isDark});

  @override
  State<_StatusIcon> createState() => _StatusIconState();
}

class _StatusIconState extends State<_StatusIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    switch (widget.status) {
      case TaskStatus.running:
        return RotationTransition(
          turns: _ctrl,
          child: Icon(Icons.refresh_rounded, size: 16, color: color),
        );
      case TaskStatus.waitingForUser:
        return Icon(Icons.question_mark_rounded, size: 16, color: color);
      case TaskStatus.completed:
        return Icon(Icons.check_circle_outline_rounded, size: 16, color: color);
      case TaskStatus.failed:
        return Icon(Icons.error_outline_rounded, size: 16, color: color);
      case TaskStatus.cancelled:
        return Icon(Icons.cancel_outlined, size: 16, color: color);
      case TaskStatus.pausedAtLimit:
        return Icon(Icons.pause_circle_outline_rounded, size: 16, color: color);
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool isDark;

  const _StatusBadge({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? DesignTokens.surfaceInputDark : DesignTokens.surfaceInputLight,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: isDark ? DesignTokens.borderDark : DesignTokens.borderLight,
          width: DesignTokens.hairline,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: DesignTokens.fontSizeXs,
          color: isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final secondary =
        isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.electric_bolt_rounded, size: 28, color: secondary),
          const SizedBox(height: DesignTokens.space8),
          Text(
            'لا توجد مهام مستقلة بعد',
            style: TextStyle(color: secondary, fontSize: DesignTokens.fontSizeSm),
          ),
          const SizedBox(height: DesignTokens.space4),
          Text(
            'اكتب هدفك أعلاه وخوارزمي ينفذه بنفسه',
            style: TextStyle(color: secondary, fontSize: DesignTokens.fontSizeXs),
          ),
        ],
      ),
    );
  }
}

