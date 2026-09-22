import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:khwarizmi/features/scheduler/data/reminder_database.dart';
import 'package:khwarizmi/features/scheduler/domain/entities/reminder_item.dart';
import 'package:khwarizmi/features/scheduler/services/notification_service.dart';

class SchedulerService {
  static final SchedulerService instance = SchedulerService._();
  SchedulerService._();

  static const _uuid = Uuid();
  Timer? _pollingTimer;
  bool _isRunning = false;

  /// Starts the scheduler background engine.
  /// Checks for missed reminders upon startup, then polls every 15 seconds.
  void start() {
    if (_isRunning) return;

    _isRunning = true;

    // Check missed reminders first, then check current due items
    checkMissedRemindersOnBoot().then((_) {
      _checkDueReminders();
    });

    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkDueReminders();
    });

    debugPrint('[SchedulerService] Background scheduler engine started.');
  }

  /// Stops the background scheduler
  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isRunning = false;
    debugPrint('[SchedulerService] Background scheduler engine stopped.');
  }

  /// Checks for missed reminders at startup.
  /// Fires immediate notifications with clear phrasing indicating they were missed.
  Future<void> checkMissedRemindersOnBoot() async {
    try {
      final now = DateTime.now();
      final missed = await ReminderDatabase.getMissedReminders(now);

      final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

      for (final reminder in missed) {
        final formattedTime = timeFormatter.format(reminder.scheduledTime);
        final desc = (reminder.description != null && reminder.description!.trim().isNotEmpty)
            ? '\n${reminder.description!.trim()}'
            : '';

        // 1. Fire clear missed notification
        await NotificationService.showNotification(
          identifier: 'missed_${reminder.id}',
          title: '⚠️ تذكير فائت من خوارزمي',
          body: 'تذكير فائت: ${reminder.title} — كان مجدولًا الساعة $formattedTime$desc',
        );

        // 2. Apply recurrence or mark completed
        if (reminder.recurrence == 'daily') {
          var nextTime = reminder.scheduledTime.add(const Duration(days: 1));
          while (nextTime.isBefore(now)) {
            nextTime = nextTime.add(const Duration(days: 1));
          }
          await ReminderDatabase.reschedule(reminder.id, nextTime);
        } else if (reminder.recurrence == 'weekly') {
          var nextTime = reminder.scheduledTime.add(const Duration(days: 7));
          while (nextTime.isBefore(now)) {
            nextTime = nextTime.add(const Duration(days: 7));
          }
          await ReminderDatabase.reschedule(reminder.id, nextTime);
        } else {
          await ReminderDatabase.markCompleted(reminder.id);
        }
      }
    } catch (e) {
      debugPrint('[SchedulerService] Error checking missed reminders on boot: $e');
    }
  }

  /// Checks SQLite for any reminders that have reached their scheduled time
  Future<void> _checkDueReminders() async {
    try {
      final now = DateTime.now();
      final dueItems = await ReminderDatabase.getDueReminders(now);

      for (final reminder in dueItems) {
        // 1. Fire real Windows Notification
        await NotificationService.showNotification(
          identifier: reminder.id,
          title: '⏰ تذكير من خوارزمي',
          body: reminder.title +
              (reminder.description != null && reminder.description!.isNotEmpty
                  ? '\n${reminder.description}'
                  : ''),
        );

        // 2. Handle recurrence
        if (reminder.recurrence == 'daily') {
          final nextTime = reminder.scheduledTime.add(const Duration(days: 1));
          await ReminderDatabase.reschedule(reminder.id, nextTime);
        } else if (reminder.recurrence == 'weekly') {
          final nextTime = reminder.scheduledTime.add(const Duration(days: 7));
          await ReminderDatabase.reschedule(reminder.id, nextTime);
        } else {
          await ReminderDatabase.markCompleted(reminder.id);
        }
      }
    } catch (e) {
      debugPrint('[SchedulerService] Error polling due reminders: $e');
    }
  }

  /// Schedules a new reminder
  Future<ReminderItem> scheduleReminder({
    required String title,
    String? description,
    required DateTime scheduledTime,
    String recurrence = 'once',
  }) async {
    final item = ReminderItem(
      id: _uuid.v4(),
      title: title.trim(),
      description: description?.trim(),
      scheduledTime: scheduledTime,
      recurrence: recurrence.trim().toLowerCase(),
      isCompleted: false,
      createdAt: DateTime.now(),
    );

    await ReminderDatabase.insertReminder(item);
    return item;
  }

  /// Lists all active reminders
  Future<List<ReminderItem>> getActiveReminders() async {
    return ReminderDatabase.getActiveReminders();
  }

  /// Lists all reminders (history)
  Future<List<ReminderItem>> getAllReminders() async {
    return ReminderDatabase.getAllReminders();
  }

  /// Cancels / deletes a reminder
  Future<void> cancelReminder(String id) async {
    await ReminderDatabase.deleteReminder(id);
  }
}
