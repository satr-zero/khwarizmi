import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';
import 'package:khwarizmi/features/scheduler/domain/entities/reminder_item.dart';
import 'package:khwarizmi/features/scheduler/services/notification_service.dart';
import 'package:khwarizmi/features/scheduler/services/scheduler_service.dart';

class RemindersViewerDialog extends StatefulWidget {
  const RemindersViewerDialog({super.key});

  @override
  State<RemindersViewerDialog> createState() => _RemindersViewerDialogState();
}

class _RemindersViewerDialogState extends State<RemindersViewerDialog> {
  List<ReminderItem> _reminders = [];
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final reminders = await SchedulerService.instance.getAllReminders();
    if (mounted) setState(() => _reminders = reminders);
  }

  Future<void> _showAddReminderDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int minutesOffset = 10;
    String recurrence = 'once';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('إضافة تذكير مجدول'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        hintText: 'مثال: موعد اجتماع الفريق، أخذ الدواء...',
                        labelText: 'عنوان التذكير',
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ملاحظات إضافية (اختياري)...',
                        labelText: 'التفاصيل',
                      ),
                    ),
                    const SizedBox(height: DesignTokens.space12),
                    Row(
                      children: [
                        const Text('الوقت المستهدف:', style: TextStyle(fontSize: DesignTokens.fontSizeSm)),
                        const SizedBox(width: DesignTokens.space8),
                        DropdownButton<int>(
                          value: minutesOffset,
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('بعد دقيقة واحدة (اختبار)')),
                            DropdownMenuItem(value: 5, child: Text('بعد 5 دقائق')),
                            DropdownMenuItem(value: 10, child: Text('بعد 10 دقائق')),
                            DropdownMenuItem(value: 30, child: Text('بعد 30 دقيقة')),
                            DropdownMenuItem(value: 60, child: Text('بعد ساعة')),
                            DropdownMenuItem(value: 1440, child: Text('غداً في نفس الوقت')),
                          ],
                          onChanged: (val) {
                            if (val != null) setModalState(() => minutesOffset = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.space12),
                    Row(
                      children: [
                        const Text('التكرار:', style: TextStyle(fontSize: DesignTokens.fontSizeSm)),
                        const SizedBox(width: DesignTokens.space8),
                        DropdownButton<String>(
                          value: recurrence,
                          items: const [
                            DropdownMenuItem(value: 'once', child: Text('مرة واحدة فقط')),
                            DropdownMenuItem(value: 'daily', child: Text('يوميًا')),
                            DropdownMenuItem(value: 'weekly', child: Text('أسبوعيًا')),
                          ],
                          onChanged: (val) {
                            if (val != null) setModalState(() => recurrence = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;

                    final scheduledTime = DateTime.now().add(Duration(minutes: minutesOffset));
                    await SchedulerService.instance.scheduleReminder(
                      title: title,
                      scheduledTime: scheduledTime,
                      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                      recurrence: recurrence,
                    );

                    if (ctx.mounted) Navigator.of(ctx).pop();
                    await _loadReminders();
                  },
                  child: const Text('جدولة التذكير'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondaryTextColor = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final dateFormat = DateFormat('yyyy-MM-dd – HH:mm');

    return Dialog(
      child: Container(
        width: 680,
        height: 580,
        padding: const EdgeInsets.all(DesignTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(Icons.notifications_none_rounded, size: 20, color: primaryTextColor),
                const SizedBox(width: DesignTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الجدولة والتنبيهات',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeLg,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      Text(
                        'نظام تنبيهات وإشعارات سطح المكتب المدمجة',
                        style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DesignTokens.space8),
                OutlinedButton(
                  onPressed: () async {
                    await NotificationService.showNotification(
                      title: 'إشعار تجريبي من خوارزمي',
                      body: 'نظام إشعارات Windows متصل ويعمل بكفاءة.',
                    );
                  },
                  child: const Text('إشعار تجريبي', style: TextStyle(fontSize: DesignTokens.fontSizeXs)),
                ),
                const SizedBox(width: DesignTokens.space8),
                ElevatedButton(
                  onPressed: _showAddReminderDialog,
                  child: const Text('جدولة تذكير', style: TextStyle(fontSize: DesignTokens.fontSizeXs)),
                ),
                const SizedBox(width: DesignTokens.space4),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: secondaryTextColor, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space12),
            Divider(height: DesignTokens.hairline, thickness: DesignTokens.hairline, color: borderColor),
            const SizedBox(height: DesignTokens.space8),

            // Subtitle Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'التذكيرات المسجلة: ${_reminders.length}',
                  style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                ),
                Text(
                  'يمكن الجدولة تلقائياً عبر المحادثة',
                  style: TextStyle(fontSize: DesignTokens.fontSizeXs, color: secondaryTextColor),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space8),

            // Clean list with hairline dividers
            Expanded(
              child: _reminders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alarm_off_outlined, size: 40, color: secondaryTextColor),
                          const SizedBox(height: DesignTokens.space8),
                          Text(
                            'لا توجد تذكيرات مجدولة حالياً',
                            style: TextStyle(color: primaryTextColor, fontSize: DesignTokens.fontSizeSm),
                          ),
                          const SizedBox(height: DesignTokens.space4),
                          Text(
                            'اطلب من خوارزمي: "ذكرني بعد ربع ساعة بالاجتماع".',
                            style: TextStyle(color: secondaryTextColor, fontSize: DesignTokens.fontSizeXs),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _reminders.length,
                      separatorBuilder: (context, index) => Divider(
                        height: DesignTokens.hairline,
                        thickness: DesignTokens.hairline,
                        color: borderColor,
                      ),
                      itemBuilder: (context, index) {
                        final r = _reminders[index];
                        final isPast = r.scheduledTime.isBefore(DateTime.now());
                        final isExpanded = _expandedIds.contains(r.id);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedIds.remove(r.id);
                              } else {
                                _expandedIds.add(r.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: DesignTokens.space12,
                              horizontal: DesignTokens.space8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // State outline icon
                                Icon(
                                  r.isCompleted
                                      ? Icons.check_circle_outline_rounded
                                      : (isPast ? Icons.access_time_rounded : Icons.alarm_rounded),
                                  color: r.isCompleted ? secondaryTextColor : primaryTextColor,
                                  size: 18,
                                ),
                                const SizedBox(width: DesignTokens.space12),

                                // Title and schedule info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              r.title,
                                              style: TextStyle(
                                                fontSize: DesignTokens.fontSizeSm,
                                                fontWeight: r.isCompleted ? FontWeight.w400 : FontWeight.w600,
                                                color: r.isCompleted ? secondaryTextColor : primaryTextColor,
                                                decoration: r.isCompleted ? TextDecoration.lineThrough : null,
                                              ),
                                            ),
                                          ),
                                          if (r.recurrence != 'once') ...[
                                            const SizedBox(width: DesignTokens.space8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark ? DesignTokens.hoverDark : DesignTokens.hoverLight,
                                                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                                              ),
                                              child: Text(
                                                r.recurrence == 'daily' ? 'يوميًا' : 'أسبوعيًا',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: secondaryTextColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: DesignTokens.space8),
                                          Text(
                                            dateFormat.format(r.scheduledTime),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (r.description != null && r.description!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          r.description!,
                                          style: TextStyle(
                                            fontSize: DesignTokens.fontSizeXs,
                                            color: secondaryTextColor,
                                          ),
                                          maxLines: isExpanded ? null : 1,
                                          overflow: isExpanded ? null : TextOverflow.ellipsis,
                                        ),
                                      ],
                                      if (isExpanded) ...[
                                        const SizedBox(height: DesignTokens.space8),
                                        Text(
                                          'الحالة: ${r.isCompleted ? 'مكتمل' : (isPast ? 'فات موعده' : 'قادم')}  |  المعرّف: ${r.id}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontFamily: DesignTokens.fontFamilyMono,
                                            fontFamilyFallback: DesignTokens.monoFallbacks,
                                            color: secondaryTextColor,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Actions
                                if (!r.isCompleted)
                                  IconButton(
                                    icon: Icon(Icons.check_rounded, size: 16, color: secondaryTextColor),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'تعليم كمكتمل',
                                    onPressed: () async {
                                      await ReminderDatabase.markCompleted(r.id);
                                      await _loadReminders();
                                    },
                                  ),
                                IconButton(
                                  icon: Icon(Icons.close_rounded, size: 14, color: secondaryTextColor),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'حذف',
                                  onPressed: () async {
                                    await SchedulerService.instance.cancelReminder(r.id);
                                    await _loadReminders();
                                  },
                                ),
                              ],
                            ),
                          ),
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
