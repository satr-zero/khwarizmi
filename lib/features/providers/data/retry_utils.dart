import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';

/// Configuration for exponential backoff retry logic
class RetryConfig {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final double backoffMultiplier;
  final double jitterFactor;
  final Set<int> retryableStatusCodes;
  final Set<String> retryableErrorCodes;

  const RetryConfig({
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.retryableErrorCodes = const {
      'NETWORK_ERROR',
      'TIMEOUT',
      'SOCKET_EXCEPTION',
      'CLIENT_EXCEPTION',
    },
  });

  /// Default config for API providers
  static const RetryConfig defaultApi = RetryConfig();

  /// Config for API streams — ثلاث محاولات مع 10 ثوانٍ انتظار مثل Zoo Code
  static const RetryConfig apiStream = RetryConfig(
    maxRetries: 3,
    baseDelay: Duration(seconds: 10),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 1.5,
    jitterFactor: 0.1,
  );

  /// More aggressive config for local models (Ollama, LM Studio, vLLM)
  static const RetryConfig localModels = RetryConfig(
    maxRetries: 5,
    baseDelay: Duration(milliseconds: 1000),
    maxDelay: Duration(seconds: 60),
    backoffMultiplier: 2.0,
    jitterFactor: 0.2,
  );

  /// Quick config for model fetching
  static const RetryConfig modelFetch = RetryConfig(
    maxRetries: 2,
    baseDelay: Duration(milliseconds: 1000),
    maxDelay: Duration(seconds: 10),
  );
}

/// Result of a retry operation
class RetryResult<T> {
  final T? data;
  final Object? error;
  final int attempts;
  final bool succeeded;

  const RetryResult._({
    this.data,
    this.error,
    required this.attempts,
    required this.succeeded,
  });

  factory RetryResult.success(T data, int attempts) =>
      RetryResult._(data: data, attempts: attempts, succeeded: true);

  factory RetryResult.failure(Object error, int attempts) =>
      RetryResult._(error: error, attempts: attempts, succeeded: false);
}

/// Utility class for executing operations with exponential backoff retry
class RetryUtils {
  static final _log = Logger.instance;

  /// Executes an async operation with exponential backoff retry logic
  static Future<RetryResult<T>> executeWithRetry<T>({
    required Future<T> Function() operation,
    RetryConfig config = RetryConfig.defaultApi,
    void Function(int attempt, Object error)? onRetry,
    bool Function(Object error)? isRetryable,
    String? correlationId,
    String? context,
  }) async {
    Object? lastError;
    int attempt = 0;
    final cid = correlationId ?? Logger.instance.newCorrelationId();
    final ctx = context ?? 'RetryUtils.executeWithRetry';

    while (attempt <= config.maxRetries) {
      try {
        _log.debug(
          ctx,
          'Attempt starting',
          correlationId: cid,
          meta: {'attempt': attempt + 1, 'maxRetries': config.maxRetries},
        );
        final result = await operation();
        _log.info(
          ctx,
          'Attempt succeeded',
          correlationId: cid,
          meta: {'attempt': attempt + 1},
        );
        return RetryResult.success(result, attempt + 1);
      } catch (e) {
        lastError = e;
        attempt++;

        if (attempt > config.maxRetries) {
          _log.error(
            ctx,
            'Max retries exhausted',
            correlationId: cid,
            meta: {'attempts': attempt, 'finalError': e.toString()},
          );
          break;
        }

        // Check if error is retryable
        final shouldRetry =
            isRetryable?.call(e) ?? _isRetryableByDefault(e, config);
        if (!shouldRetry) {
          _log.warn(
            ctx,
            'Error not retryable',
            correlationId: cid,
            meta: {'error': e.toString()},
          );
          break;
        }

        // Calculate delay with exponential backoff and jitter
        final delay = _calculateDelay(attempt, config);

        if (onRetry != null) {
          onRetry(attempt, e);
        }

        _log.warn(
          ctx,
          'Retry scheduled',
          correlationId: cid,
          meta: {
            'attempt': attempt,
            'delayMs': delay.inMilliseconds,
            'error': e.toString(),
          },
        );

        await Future.delayed(delay);
      }
    }

    _log.error(
      ctx,
      'All retries failed',
      correlationId: cid,
      meta: {'attempts': attempt, 'error': lastError.toString()},
    );
    return RetryResult.failure(lastError!, attempt);
  }

  /// Executes a stream operation with retry logic, yielding [AgentRetryEvent]
  /// before each retry so the UI can display a countdown banner like Zoo Code.
  ///
  /// النقطة الحرجة: عند حدوث انقطاع أثناء التدفق نُصدر AgentRetryEvent أولاً
  /// قبل الانتظار، ثم نُعيد بناء الطلب كاملاً مع تاريخ المحادثة المتراكم.
  /// هذا يضمن عدم دمج النص القديم مع الجديد بطريقة مشوهة.
  static Stream<AgentEvent> executeStreamWithRetry({
    required Stream<AgentEvent> Function() streamFactory,
    RetryConfig config = RetryConfig.apiStream,
    void Function(int attempt, Object error)? onRetry,
    bool Function(Object error)? isRetryable,
    String? correlationId,
    String? context,
  }) async* {
    Object? lastError;
    int attempt = 0;
    final cid = correlationId ?? Logger.instance.newCorrelationId();
    final ctx = context ?? 'RetryUtils.executeStreamWithRetry';

    while (attempt <= config.maxRetries) {
      try {
        _log.debug(
          ctx,
          'Stream attempt starting',
          correlationId: cid,
          meta: {'attempt': attempt + 1, 'maxRetries': config.maxRetries},
        );
        final stream = streamFactory();
        bool hasEmitted = false;
        int eventsEmitted = 0;

        await for (final event in stream) {
          hasEmitted = true;
          eventsEmitted++;
          if (eventsEmitted == 1) {
            _log.info(
              ctx,
              'First event received from stream',
              correlationId: cid,
            );
          }
          yield event;
          // إذا كان الحدث AgentDoneEvent، نخرج من الحلقة بنجاح
          if (event is AgentDoneEvent) {
            _log.info(
              ctx,
              'AgentDoneEvent received — stream completed',
              correlationId: cid,
              meta: {'totalEvents': eventsEmitted},
            );
            return;
          }
        }

        // إذا أغلق الـ stream بدون AgentDoneEvent وأصدر شيئاً → نعتبره نجاحاً ناقصاً
        if (hasEmitted) {
          _log.warn(
            ctx,
            'Stream closed without AgentDoneEvent (partial success)',
            correlationId: cid,
            meta: {'totalEvents': eventsEmitted},
          );
          return;
        }
        // إذا لم يصدر شيء إطلاقاً → خطأ قابل للإعادة
        throw Exception('Stream completed without emitting any events');
      } catch (e, st) {
        lastError = e;
        attempt++;

        if (attempt > config.maxRetries) {
          _log.error(
            ctx,
            'Max stream retries exhausted',
            correlationId: cid,
            meta: {'attempts': attempt, 'finalError': e.toString()},
            stackTrace: st,
          );
          break;
        }

        final shouldRetry =
            isRetryable?.call(e) ?? _isRetryableByDefault(e, config);
        if (!shouldRetry) {
          _log.warn(
            ctx,
            'Stream error not retryable',
            correlationId: cid,
            meta: {'error': e.toString()},
          );
          break;
        }

        final delay = _calculateDelay(attempt, config);

        if (onRetry != null) {
          onRetry(attempt, e);
        }

        // نُصدر حدث إعادة المحاولة للواجهة قبل الانتظار
        final reason = _extractHumanReadableReason(e);
        yield AgentRetryEvent(
          attempt: attempt,
          maxAttempts: config.maxRetries,
          delay: delay,
          reason: reason,
        );

        _log.warn(
          ctx,
          'Stream retry scheduled',
          correlationId: cid,
          meta: {
            'attempt': attempt,
            'delayMs': delay.inMilliseconds,
            'error': e.toString(),
            'reason': reason,
          },
        );

        await Future.delayed(delay);
      }
    }

    // كل المحاولات استُنفدت — نُصدر خطأ نهائياً
    _log.error(
      ctx,
      'All stream retries exhausted — throwing final error',
      correlationId: cid,
      meta: {'attempts': attempt, 'error': lastError.toString()},
    );
    throw lastError ?? Exception('Retry exhausted after $attempt attempts');
  }

  /// نسخة قديمة متوافقة للخلف (للـ providers التي لا تستخدم AgentEvent)
  static Stream<T> executeRawStreamWithRetry<T>({
    required Stream<T> Function() streamFactory,
    RetryConfig config = RetryConfig.defaultApi,
    void Function(int attempt, Object error)? onRetry,
    bool Function(Object error)? isRetryable,
  }) async* {
    Object? lastError;
    int attempt = 0;

    while (attempt <= config.maxRetries) {
      try {
        final stream = streamFactory();
        bool hasEmitted = false;

        await for (final event in stream) {
          hasEmitted = true;
          yield event;
        }

        if (hasEmitted) {
          return;
        }
        throw Exception('Stream completed without emitting any events');
      } catch (e) {
        lastError = e;
        attempt++;

        if (attempt > config.maxRetries) {
          break;
        }

        final shouldRetry =
            isRetryable?.call(e) ?? _isRetryableByDefault(e, config);
        if (!shouldRetry) {
          break;
        }

        final delay = _calculateDelay(attempt, config);

        if (onRetry != null) {
          onRetry(attempt, e);
        }

        debugPrint(
          '[RetryUtils] Stream attempt $attempt failed: $e. Retrying in ${delay.inMilliseconds}ms...',
        );

        await Future.delayed(delay);
      }
    }

    throw lastError ?? Exception('Retry exhausted after $attempt attempts');
  }

  static Duration _calculateDelay(int attempt, RetryConfig config) {
    // Exponential backoff: baseDelay * (multiplier ^ (attempt - 1))
    final exponentialDelay =
        config.baseDelay.inMilliseconds *
        pow(config.backoffMultiplier, attempt - 1);

    // Cap at maxDelay
    final cappedDelay = min(
      exponentialDelay,
      config.maxDelay.inMilliseconds,
    ).toInt();

    // Add jitter: ±jitterFactor * cappedDelay
    final jitterRange = (cappedDelay * config.jitterFactor).toInt();
    final jitter = jitterRange > 0
        ? Random().nextInt(jitterRange * 2) - jitterRange
        : 0;

    final finalDelay = (cappedDelay + jitter).clamp(
      config.baseDelay.inMilliseconds,
      config.maxDelay.inMilliseconds,
    );

    return Duration(milliseconds: finalDelay);
  }

  static bool _isRetryableByDefault(Object error, RetryConfig config) {
    final errorString = error.toString().toLowerCase();

    // TOOLS_NOT_SUPPORTED حتمي لنفس (الموديل + الأدوات): إعادة المحاولة
    // بنفس الطلب ستفشل حتماً — ثُبتت فعلياً عاصفة (طبقتا إعادة × فواصل
    // 10-22 ثانية لعدة دقائق) على موديلات NVIDIA غير الداعمة للأدوات
    if (errorString.contains('tools_not_supported')) {
      return false;
    }

    // Check for network-related errors
    if (error is Exception) {
      if (error.toString().contains('SocketException') ||
          error.toString().contains('ClientException') ||
          error.toString().contains('TimeoutException') ||
          error.toString().contains('HttpException')) {
        return true;
      }
    }

    // Upstream idle timeout (شائع جداً مع Gemini وOpenAI)
    if (errorString.contains('upstream idle timeout') ||
        errorString.contains('idle timeout') ||
        errorString.contains('stream_idle_timeout')) {
      return true;
    }

    // Check for specific error codes in the error message
    for (final code in config.retryableErrorCodes) {
      if (errorString.contains(code.toLowerCase())) {
        return true;
      }
    }

    // Check for HTTP status codes in error message
    for (final code in config.retryableStatusCodes) {
      if (errorString.contains(code.toString())) {
        return true;
      }
    }

    return false;
  }

  /// يستخرج سبباً إنسانياً مختصراً من خطأ الشبكة
  static String _extractHumanReadableReason(Object error) {
    final msg = error.toString();
    if (msg.contains('TOOLS_NOT_SUPPORTED')) {
      return 'هذا الموديل لا يدعم استدعاء الأدوات — بدّل الموديل أو استخدم وضع الاستفسار (نص فقط)';
    }
    if (msg.contains('upstream idle timeout') ||
        msg.contains('idle timeout') ||
        msg.contains('stream_idle_timeout')) {
      return 'انقطاع الاتصال (Stream idle timeout — 90s لا نشاط)';
    }
    if (msg.contains('SocketException')) {
      return 'خطأ في الشبكة (Socket)';
    }
    if (msg.contains('ClientException')) {
      return 'خطأ في الاتصال (Client)';
    }
    if (msg.contains('TimeoutException')) {
      return 'انتهت مهلة الانتظار';
    }
    if (msg.contains('429')) {
      return 'تجاوز حد الطلبات (Rate limit)';
    }
    if (msg.contains('503') || msg.contains('502')) {
      return 'الخادم غير متاح مؤقتاً';
    }
    if (msg.contains('500')) {
      return 'خطأ داخلي في الخادم';
    }
    // عرض أول 60 حرف فقط
    return msg.length > 60 ? '${msg.substring(0, 60)}...' : msg;
  }
}

/// Extension to add retry capability to any Future
extension RetryExtension<T> on Future<T> {
  Future<RetryResult<T>> withRetry({
    RetryConfig config = RetryConfig.defaultApi,
    void Function(int attempt, Object error)? onRetry,
    bool Function(Object error)? isRetryable,
  }) {
    return RetryUtils.executeWithRetry(
      operation: () => this,
      config: config,
      onRetry: onRetry,
      isRetryable: isRetryable,
    );
  }
}
