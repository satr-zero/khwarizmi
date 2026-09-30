/// Mixin لإضافة قدرة التسجيل لأي كلاس بسهولة
///
/// الاستخدام:
/// ```dart
/// class MyService with LoggingMixin {
///   void doSomething() {
///     log.info('MyService', 'Starting operation');
///     try {
///       // ...
///       log.debug('MyService', 'Step completed', meta: {'step': 1});
///     } catch (e, st) {
///       log.error('MyService', 'Failed', error: e, stackTrace: st);
///     }
///   }
/// }
/// ```
library khwarizmi.core.logging;

import 'logger.dart';

/// Mixin يوفر خاصية `log` للوصول السريع للمسجل
mixin LoggingMixin {
  /// مسجل مخصص لهذا الكائن — يستخدم اسم الكلاس كسياق افتراضي
  Logger get log => Logger.instance;

  /// اسم السياق الافتراضي — يمكن تجاوزه في الكلاس الفرعي
  String get loggingContext => runtimeType.toString();

  /// اختصارات مع سياق تلقائي
  void logTrace(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.trace(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logDebug(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.debug(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logInfo(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.info(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logWarn(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.warn(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logError(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    Object? error,
    StackTrace? stackTrace,
  }) => log.error(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
    stackTrace: stackTrace,
  );

  void logCritical(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    Object? error,
    StackTrace? stackTrace,
  }) => log.critical(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
    stackTrace: stackTrace,
  );
}

/// امتداد على Object لتسجيل سريع دون Mixin
extension LoggingExtension on Object {
  Logger get log => Logger.instance;

  String get loggingContext => runtimeType.toString();

  void logTrace(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.trace(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logDebug(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.debug(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logInfo(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.info(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logWarn(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
  }) => log.warn(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
  );

  void logError(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    Object? error,
    StackTrace? stackTrace,
  }) => log.error(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
    stackTrace: stackTrace,
  );

  void logCritical(
    String message, {
    String? correlationId,
    String? taskId,
    String? turnId,
    String? provider,
    String? model,
    Map<String, dynamic>? meta,
    Object? error,
    StackTrace? stackTrace,
  }) => log.critical(
    loggingContext,
    message,
    correlationId: correlationId,
    taskId: taskId,
    turnId: turnId,
    provider: provider,
    model: model,
    meta: meta,
    stackTrace: stackTrace,
  );
}
