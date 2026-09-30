/// إعدادات التسجيل العامة — ملف منفصل للاستيراد النظيف
library khwarizmi.core.logging;

import 'logger.dart';

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
