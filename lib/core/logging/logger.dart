/// نظام Logging موحد — خوارزمي
///
/// يوفر:
/// - مستويات تسجيل موحدة (TRACE → CRITICAL)
/// - إدخال منظم (LogEntry) مع correlationId وسياق غني
/// - Singleton Logger مع مصرفين (TerminalSink, FileSink)
/// - API بسيط: log.info('msg', meta: {...})

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'terminal_sink.dart';
import 'file_sink.dart';
import 'logging_config.dart';

import 'package:uuid/uuid.dart';

export 'file_sink.dart' show FileSink;
export 'logging_config.dart' show LoggingConfig;
export 'logging_mixin.dart' show LoggingMixin, LoggingExtension;
export 'terminal_sink.dart' show TerminalSink;

/// مستويات التسجيل — متطابقة مع معايير syslog/RFC5424
enum LogLevel {
  /// تفصيل شديد — لكل chunk وحدث داخلي (مطورين فقط)
  trace(0, 'TRACE', '\x1B[90m'), // رمادي فاتح

  /// معلومات تشخيصية — تدفق الأحداث، محاولات، أدوات
  debug(1, 'DEBUG', '\x1B[36m'), // سماوي

  /// معلومات عامة — بداية/نهاية عمليات، نجاح
  info(2, 'INFO', '\x1B[32m'), // أخضر

  /// تحذير — شيء غير متوقع لكن قابل للاستمرار
  warn(3, 'WARN', '\x1B[33m'), // أصفر

  /// خطأ — فشل عملية، استثناء ملتقط
  error(4, 'ERROR', '\x1B[31m'), // أحمر

  /// حرج — فشل نظامي، فقدان بيانات، إيقاف
  critical(5, 'CRITICAL', '\x1B[91m'); // أحمر فاتح

  const LogLevel(this.value, this.name, this.ansiColor);

  final int value;
  final String name;
  final String ansiColor;

  static LogLevel fromString(String s) {
    return LogLevel.values.firstWhere(
      (l) => l.name.toLowerCase() == s.toLowerCase(),
      orElse: () => LogLevel.info,
    );
  }

  bool get isAtLeastInfo => value >= LogLevel.info.value;
}

/// إدخال تسجيل واحد — قابل للتسلسل JSONL
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.context,
    required this.message,
    this.correlationId,
    this.taskId,
    this.turnId,
    this.provider,
    this.model,
    this.meta,
    this.stackTrace,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String context; // اسم المكون: 'Provider.sendMessage', 'ToolRegistry.executeTool', إلخ
  final String message;
  final String? correlationId; // يربط السجلات لنفس الطلب/الحلقة
  final String? taskId; // معرف مهمة مستقلة إن وجد
  final String? turnId; // معرف دورة محادثة إن وجد
  final String? provider; // مزود AI: 'gemini', 'claude', إلخ
  final String? model; // اسم النموذج: 'gemini-3.8-flash'
  final Map<String, dynamic>? meta; // بيانات إضافية مرنة
  final StackTrace? stackTrace; // للـ error/critical

  /// يصنع نسخة مع حقول محدثة
  LogEntry copyWith({
    DateTime? timestamp,
    LogLevel? level,
    String? context,
    String? message,
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    StackTrace? stackTrace,
  }) {
    return LogEntry(
      timestamp: timestamp ?? this.timestamp,
      level: level ?? this.level,
      context: context ?? this.context,
      message: message ?? this.message,
      correlationId: correlationId ?? this.correlationId,
      taskId: taskId ?? this.taskId,
      turnId: turnId ?? this.turnId,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      meta: meta ?? this.meta,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }

  /// يسلسل إلى JSONL (سطر واحد)
  String toJsonLine() {
    final map = <String, dynamic>{
      'ts': timestamp.toIso8601String(),
      'lvl': level.name,
      'ctx': context,
      'msg': message,
    };
    if (correlationId != null) map['corr'] = correlationId;
    if (taskId != null) map['task'] = taskId;
    if (turnId != null) map['turn'] = turnId;
    if (provider != null) map['prov'] = provider;
    if (model != null) map['model'] = model;
    if (meta != null && meta!.isNotEmpty) map['meta'] = meta;
    if (stackTrace != null) map['stack'] = stackTrace.toString();
    return jsonEncode(map);
  }

  /// ينشئ من JSONL
  static LogEntry fromJsonLine(String line) {
    final map = jsonDecode(line) as Map<String, dynamic>;
    return LogEntry(
      timestamp: DateTime.parse(map['ts'] as String),
      level: LogLevel.fromString(map['lvl'] as String),
      context: map['ctx'] as String,
      message: map['msg'] as String,
      correlationId: map['corr'] as String?,
      taskId: map['task'] as String?,
      turnId: map['turn'] as String?,
      provider: map['prov'] as String?,
      model: map['model'] as String?,
      meta: map['meta'] as Map<String, dynamic>?,
      stackTrace: map['stack'] != null
          ? StackTrace.fromString(map['stack'] as String)
          : null,
    );
  }

  @override
  String toString() => toJsonLine();
}

/// مصرف تسجيل — واجهة لكتابة السجلات
abstract class LogSink {
  /// يكتب إدخال — يجب أن يكون غير مانع (non-blocking)
  void write(LogEntry entry);

  /// يغلق المصف — flush أي مخازن مؤقتة
  Future<void> close();

  /// مستوى أدنى يسجله هذا المصف
  LogLevel get minLevel;
}

/// إعدادات التسجيل العامة
class LoggingConfig {
  const LoggingConfig({
    this.minLevel = LogLevel.debug,
    this.enableTerminal = true,
    this.enableFile = false,
    this.filePath,
    this.maxFileSizeBytes = 10 * 1024 * 1024, // 10 MB
    this.maxFiles = 7,
    this.useJsonLines = true,
    this.useColors = true,
    this.includeMicroseconds = true,
  });

  /// أدنى مستوى يسجل (ما دونه يُتجاهل)
  final LogLevel minLevel;

  /// تفعيل مصرف التيرمنال
  final bool enableTerminal;

  /// تفعيل مصرف الملفات
  final bool enableFile;

  /// مسار ملف السجل (افتراضي: Documents/Khwarizmi/logs/khwarizmi-YYYYMMDD.log)
  final String? filePath;

  /// الحد الأقصى لحجم ملف واحد قبل التدوير
  final int maxFileSizeBytes;

  /// عدد الملفات المحتفظ بها (التدوير اليومي)
  final int maxFiles;

  /// استخدام تنسيق JSONL (true) أم نصي ملون (false)
  final bool useJsonLines;

  /// استخدام ألوان ANSI في التيرمنال
  final bool useColors;

  /// تضمين مايكروثواني في الطابع الزمني النصي
  final bool includeMicroseconds;

  LoggingConfig copyWith({
    LogLevel? minLevel,
    bool? enableTerminal,
    bool? enableFile,
    String? filePath,
    int? maxFileSizeBytes,
    int? maxFiles,
    bool? useJsonLines,
    bool? useColors,
    bool? includeMicroseconds,
  }) {
    return LoggingConfig(
      minLevel: minLevel ?? this.minLevel,
      enableTerminal: enableTerminal ?? this.enableTerminal,
      enableFile: enableFile ?? this.enableFile,
      filePath: filePath ?? this.filePath,
      maxFileSizeBytes: maxFileSizeBytes ?? this.maxFileSizeBytes,
      maxFiles: maxFiles ?? this.maxFiles,
      useJsonLines: useJsonLines ?? this.useJsonLines,
      useColors: useColors ?? this.useColors,
      includeMicroseconds: includeMicroseconds ?? this.includeMicroseconds,
    );
  }
}

/// مسجل موحد — Singleton مع مصرفين
class Logger {
  Logger._();

  static final Logger _instance = Logger._();
  static Logger get instance => _instance;

  static const _uuid = Uuid();

  LoggingConfig _config = const LoggingConfig();
  final List<LogSink> _sinks = [];
  final _controller = StreamController<LogEntry>.broadcast();
  bool _initialized = false;
  String? _sessionCorrelationId;

  /// تيار السجلات — للاشتراك من الواجهة أو الاختبارات
  Stream<LogEntry> get stream => _controller.stream;

  /// إعداد المسجل — يستدعى مرة واحدة عند بدء التطبيق
  Future<void> initialize(LoggingConfig config) async {
    if (_initialized) return;
    _config = config;
    _sessionCorrelationId = _uuid.v4().substring(0, 8);

    if (config.enableTerminal) {
      _sinks.add(
        TerminalSink(
          minLevel: config.minLevel,
          useColors: config.useColors,
          useJsonLines: config.useJsonLines,
          includeMicroseconds: config.includeMicroseconds,
        ),
      );
    }

    if (config.enableFile) {
      final path = config.filePath ?? _defaultLogPath();
      _sinks.add(
        FileSink(
          path: path,
          minLevel: config.minLevel,
          maxFileSizeBytes: config.maxFileSizeBytes,
          maxFiles: config.maxFiles,
        ),
      );
    }

    _initialized = true;
    info(
      'Logger',
      'Logging initialized',
      meta: {
        'sessionCorrelationId': _sessionCorrelationId,
        'config': {
          'minLevel': config.minLevel.name,
          'enableTerminal': config.enableTerminal,
          'enableFile': config.enableFile,
          'useJsonLines': config.useJsonLines,
        },
      },
    );
  }

  String _defaultLogPath() {
    final docsDir = Directory(
      '${Platform.environment['USERPROFILE']}\\Documents\\Khwarizmi\\logs',
    );
    if (!docsDir.existsSync()) {
      docsDir.createSync(recursive: true);
    }
    final dateStr = DateTime.now()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    return '${docsDir.path}\\khwarizmi-$dateStr.log';
  }

  /// يسجل دخول — نقطة الدخول الرئيسية
  void log(
    LogLevel level,
    String context,
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) {
      // Fallback للطباعة المبكرة قبل التهيئة
      _fallbackPrint(level, context, message);
      return;
    }
    if (level.value < _config.minLevel.value) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      context: context,
      message: message,
      correlationId: correlationId ?? _sessionCorrelationId,
      taskId: taskId,
      turnId: turnId,
      provider: provider,
      model: model,
      meta: meta,
      stackTrace: stackTrace,
    );

    for (final sink in _sinks) {
      if (level.value >= sink.minLevel.value) {
        sink.write(entry);
      }
    }
    _controller.add(entry);
  }

  void _fallbackPrint(LogLevel level, String context, String message) {
    final prefix = level.ansiColor + level.name.padRight(8) + '\x1B[0m';
    print('$prefix [$context] $message');
  }

  // ── اختصارات مريحة ──

  void trace(
    String context,
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log(
    LogLevel.trace,
    context,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void debug(
    String context,
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log(
    LogLevel.debug,
    context,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void info(
    String context,
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log(
    LogLevel.info,
    context,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void warn(
    String context,
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log(
    LogLevel.warn,
    context,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void error(
    String context,
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.error,
    context,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
    stackTrace: stackTrace,
  );

  void critical(
    String context,
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.critical,
    context,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
    stackTrace: stackTrace,
  );

  /// يولد correlationId جديد لحلقة/طلب جديد
  String newCorrelationId() => _uuid.v4().substring(0, 8);

  /// يغير المستوى الأدنى ديناميكياً (حياً)
  void setMinLevel(LogLevel level) {
    _config = _config.copyWith(minLevel: level);
    for (final sink in _sinks) {
      // لا يمكن تغيير minLevel للمصف بعد الإنشاء — يُعاد إنشاؤه في إعادة تهيئة كاملة
    }
    info('Logger', 'Min level changed to ${level.name}');
  }

  /// يغلق المسجل وينظف الموارد
  Future<void> shutdown() async {
    await _controller.close();
    for (final sink in _sinks) {
      await sink.close();
    }
    _sinks.clear();
    _initialized = false;
  }
}
