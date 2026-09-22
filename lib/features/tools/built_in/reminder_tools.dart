import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/scheduler/services/scheduler_service.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

class ScheduleReminderTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'schedule_reminder',
    description: 'Schedules a real reminder or alarm on Windows. Dispatches native notifications via Windows Action Center.',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'title': {
          'type': 'STRING',
          'description': 'The reminder text or task name to notify the user about.'
        },
        'scheduled_time': {
          'type': 'STRING',
          'description': 'Target time formatted as ISO 8601 string (e.g. 2026-09-06T18:30:00) or relative offset like "+15m", "+2h", "+1d".'
        },
        'description': {
          'type': 'STRING',
          'description': 'Optional extra details or instructions.'
        },
        'recurrence': {
          'type': 'STRING',
          'description': 'Recurrence rule: "once", "daily", or "weekly". Default is "once".'
        }
      },
      'required': ['title', 'scheduled_time']
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final title = arguments['title'] as String?;
      final timeStr = arguments['scheduled_time'] as String?;

      if (title == null || title.trim().isEmpty) {
        return jsonEncode({'status': 'error', 'error': 'الحقل المطلوب "title" مفقود أو فارغ'});
      }
      if (timeStr == null || timeStr.trim().isEmpty) {
        return jsonEncode({'status': 'error', 'error': 'الحقل المطلوب "scheduled_time" مفقود أو فارغ'});
      }

      final recurrence = (arguments['recurrence'] as String?) ?? 'once';
      final description = arguments['description'] as String?;

      DateTime? targetTime;

      // Support relative time strings like "+10m", "+2h", "15m"
      final relMatch = RegExp(
        r'^\+?(\d+)\s*(m|min|minute|minutes|h|hour|hours|d|day|days)$',
        caseSensitive: false,
      ).firstMatch(timeStr.trim());

      if (relMatch != null) {
        final amount = int.parse(relMatch.group(1)!);
        final unit = relMatch.group(2)!.toLowerCase();

        if (unit.startsWith('m')) {
          targetTime = DateTime.now().add(Duration(minutes: amount));
        } else if (unit.startsWith('h')) {
          targetTime = DateTime.now().add(Duration(hours: amount));
        } else if (unit.startsWith('d')) {
          targetTime = DateTime.now().add(Duration(days: amount));
        }
      } else {
        // Parse ISO string
        targetTime = DateTime.tryParse(timeStr.trim());
      }

      if (targetTime == null) {
        return jsonEncode({
          'status': 'error',
          'error': 'صيغة الوقت غير صالحة. استخدم ISO 8601 (مثال: 2026-09-06T18:30:00) أو إزاحة نسبية (مثال: +30m).',
        });
      }

      final reminder = await SchedulerService.instance.scheduleReminder(
        title: title.trim(),
        description: description,
        scheduledTime: targetTime,
        recurrence: recurrence,
      );

      final formatter = DateFormat('yyyy-MM-dd HH:mm');
      return jsonEncode({
        'status': 'success',
        'message': 'تم جدولة التذكير بنجاح.',
        'reminder_id': reminder.id,
        'title': reminder.title,
        'scheduled_for': formatter.format(targetTime),
        'recurrence': reminder.recurrence,
      });
    } catch (e) {
      return jsonEncode({'status': 'error', 'error': 'فشل جدولة التذكير: $e'});
    }
  }
}

class ListRemindersTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'list_reminders',
    description: 'Lists all pending, scheduled, and active reminders on Windows.',
    parameters: {
      'type': 'OBJECT',
      'properties': {},
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final reminders = await SchedulerService.instance.getActiveReminders();
      final formatter = DateFormat('yyyy-MM-dd HH:mm');

      final list = reminders.map((r) {
        return {
          'id': r.id,
          'title': r.title,
          'description': r.description,
          'scheduled_time': formatter.format(r.scheduledTime),
          'recurrence': r.recurrence,
        };
      }).toList();

      return jsonEncode({
        'status': 'success',
        'active_count': list.length,
        'reminders': list,
      });
    } catch (e) {
      return jsonEncode({'status': 'error', 'error': 'فشل جلب قائمة التذكيرات: $e'});
    }
  }
}

class CancelReminderTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'cancel_reminder',
    description: 'Cancels or deletes a scheduled reminder by its ID.',
    parameters: {
      'type': 'OBJECT',
      'properties': {
        'id': {
          'type': 'STRING',
          'description': 'The reminder ID to cancel.'
        }
      },
      'required': ['id']
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    try {
      final id = arguments['id'] as String?;
      if (id == null || id.trim().isEmpty) {
        return jsonEncode({'status': 'error', 'error': 'معرّف التذكير (id) مطلوب'});
      }

      await SchedulerService.instance.cancelReminder(id.trim());
      return jsonEncode({
        'status': 'success',
        'message': 'تم إلغاء التذكير بنجاح.',
      });
    } catch (e) {
      return jsonEncode({'status': 'error', 'error': 'فشل إلغاء التذكير: $e'});
    }
  }
}
