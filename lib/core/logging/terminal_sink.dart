/// مصرف التيرمنال — يطبع السجلات بألوان ANSI وتنسيق جميل
library khwarizmi.core.logging;

import 'dart:io';

import 'logger.dart';

/// مصرف يكتب إلى stdout/stderr مع ألوان وتنسيق
class TerminalSink implements LogSink {
  TerminalSink({
    required this.minLevel,
    this.useColors = true,
    this.useJsonLines = false,
    this.includeMicroseconds = true,
  });

  @override
  final LogLevel minLevel;

  final bool useColors;
  final bool useJsonLines;
  final bool includeMicroseconds;

  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _dim = '\x1B[2m';

  // ألوان المستويات (تطابق LogLevel.ansiColor)
  static const _levelColors = {
    LogLevel.trace: '\x1B[90m', // رمادي فاتح
    LogLevel.debug: '\x1B[36m', // سماوي
    LogLevel.info: '\x1B[32m', // أخضر
    LogLevel.warn: '\x1B[33m', // أصفر
    LogLevel.error: '\x1B[31m', // أحمر
    LogLevel.critical: '\x1B[91m', // أحمر فاتح
  };

  @override
  void write(LogEntry entry) {
    if (useJsonLines) {
      _writeJsonLine(entry);
    } else {
      _writeFormatted(entry);
    }
  }

  void _writeJsonLine(LogEntry entry) {
    final line = entry.toJsonLine();
    _printToConsole(line, entry.level);
  }

  void _writeFormatted(LogEntry entry) {
    final buffer = StringBuffer();

    // الطابع الزمني
    final ts = entry.timestamp;
    final timeStr = includeMicroseconds
        ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}.${ts.millisecond.toString().padLeft(3, '0')}'
        : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';

    // المستوى مع لون
    final levelColor = useColors ? _levelColors[entry.level]! : '';
    final levelStr = '${levelColor}${entry.level.name.padRight(5)}$_reset';

    // السياق
    final contextStr = '${_dim}$_bold${entry.context}$_reset';

    // رسالة
    final messageStr = entry.message;

    // حقول اختيارية (corr, task, turn, prov, model)
    final extras = <String>[];
    if (entry.correlationId != null) extras.add('corr:${entry.correlationId}');
    if (entry.taskId != null) extras.add('task:${entry.taskId}');
    if (entry.turnId != null) extras.add('turn:${entry.turnId}');
    if (entry.provider != null) extras.add('prov:${entry.provider}');
    if (entry.model != null) extras.add('model:${entry.model}');
    if (entry.meta != null && entry.meta!.isNotEmpty) {
      extras.add('meta:${_formatMeta(entry.meta!)}');
    }

    final extraStr = extras.isNotEmpty ? ' [${extras.join(' ')}]' : '';

    buffer.write('[$levelStr] $timeStr $contextStr $messageStr$extraStr');

    // Stack trace للأخطاء الحرجة
    if (entry.stackTrace != null &&
        (entry.level == LogLevel.error || entry.level == LogLevel.critical)) {
      buffer.write('\n${_dim}$_reset${entry.stackTrace}');
    }

    _printToConsole(buffer.toString(), entry.level);
  }

  String _formatMeta(Map<String, dynamic> meta) {
    // تنسيق مختصر للـ meta
    final parts = <String>[];
    meta.forEach((k, v) {
      final vs = v.toString();
      parts.add('$k=${vs.length > 40 ? '${vs.substring(0, 40)}...' : vs}');
    });
    return '{${parts.join(', ')}}';
  }

  void _printToConsole(String line, LogLevel level) {
    // error/critical إلى stderr، الباقي إلى stdout
    if (level == LogLevel.error || level == LogLevel.critical) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }
  }

  @override
  Future<void> close() async {
    // لا شيء للإغلاق للتيرمنال
  }
}
