import 'dart:async';
import 'dart:math' as math;

import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/core/execution/execution_types.dart';

// ─────────────────────────────────────────────────────────────────────────────
// سياسة إعادة المحاولة الموحّدة — مصممة للمزوّد المجاني غير الموثوق
// (NVIDIA Nemotron وغيره): 429/5xx متكررة، انقطاعات شبكة، سكوت SSE.
//
// المبادئ:
// 1. تصنيف حتمي: [ExecutionFailure.isRetryable] يقرر — لا تخمين نصي.
// 2. Backoff أُسّي مع Jitter — مثل Claude Code / opencode.
// 3. **حفظ المحتوى الجزئي عبر المحاولات**: إن فشلت محاولة بعد نص جزئي،
//    يُحمل النص الجزئي للمحاولة التالية فلا يُهدر شيء (متطلب #4).
// 4. إشعار الواجهة قبل كل انتظار — [ExecutionRetryScheduled].
// ─────────────────────────────────────────────────────────────────────────────

/// سياسة إعادة المحاولة
class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.2,
  });

  /// الحد الأقصى لإعادة المحاولات (إضافة للمحاولة الأولى)
  final int maxRetries;

  /// تأخير المحاولة الأولى
  final Duration baseDelay;

  /// سقف التأخير
  final Duration maxDelay;

  /// معامل النمو الأُسّي
  final double backoffMultiplier;

  /// نسبة العشوائية (0.0–1.0) لتفادي مزامنة العواصف
  final double jitterFactor;

  /// السياسة القياسية لبث الـ API (مثل Zoo Code: 3 محاولات، 10 ثوانٍ)
  static const RetryPolicy apiStream = RetryPolicy(
    maxRetries: 3,
    baseDelay: Duration(seconds: 10),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 1.5,
  );

  /// سياسة أعدوانية للنماذج المحلية (Ollama/LM Studio)
  static const RetryPolicy localModel = RetryPolicy(
    maxRetries: 5,
    baseDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 60),
    backoffMultiplier: 2.0,
    jitterFactor: 0.2,
  );

  /// يحسب تأخير المحاولة رقم [attempt] (يبدأ من 1) مع Jitter.
  Duration delayFor(int attempt) {
    final exponential =
        baseDelay.inMilliseconds *
        math.pow(backoffMultiplier, attempt - 1).toDouble();
    final jitter = exponential * jitterFactor * (_random.nextDouble() * 2 - 1);
    final ms = (exponential + jitter)
        .clamp(baseDelay.inMilliseconds, maxDelay.inMilliseconds)
        .toInt();
    return Duration(milliseconds: ms);
  }

  static final math.Random _random = math.Random();
}

/// نتيجة عملية مُعاد تجربتها مع الحفاظ على المحتوى الجزئي
class RetryOutcome<T> {
  /// النتيجة الناجحة إن نجحت
  final T? value;

  /// الفشل النهائي إن فشلت
  final ExecutionFailure? failure;

  /// عدد المحاولات المستهلكة
  final int attempts;

  /// **المحتوى الجزئي المتراكم عبر كل المحاولات** — لا يُهدر أبداً
  final String accumulatedPartialContent;

  const RetryOutcome({
    this.value,
    this.failure,
    required this.attempts,
    this.accumulatedPartialContent = '',
  });

  bool get succeeded => failure == null && value != null;
}

/// منفّذ سياسة إعادة المحاولة — الطبقة الوحيدة التي تعيد محاولة البث.
class RetryExecutor {
  RetryExecutor({this.context = 'RetryExecutor'});

  final String context;
  final _log = Logger.instance;

  /// ينفّذ عملية مع إعادة محاولة حتمية وحفظ المحتوى الجزئي.
  ///
  /// [operation] تُستدعى لكل محاولة وتعيد [RetryOutcome] — إن فشلت بمحتوى
  /// جزئي، يُدمج في [RetryOutcome.accumulatedPartialContent] للمحاولة التالية.
  /// [onRetryScheduled] يُستدعى قبل كل انتظار (بانر الواجهة).
  Future<RetryOutcome<T>> execute<T>({
    required RetryPolicy policy,
    required Future<RetryOutcome<T>> Function(int attempt) operation,
    void Function(ExecutionRetryScheduled event)? onRetryScheduled,
    String? correlationId,
  }) async {
    final cid = correlationId ?? _log.newCorrelationId();
    var accumulated = '';
    var attempt = 0;

    while (true) {
      attempt++;
      final outcome = await operation(attempt);

      if (outcome.succeeded) {
        return outcome;
      }

      final failure = outcome.failure!;
      // دمج المحتوى الجزئي من هذه المحاولة في المتراكم الكلي
      if (failure.partialContent != null &&
          failure.partialContent!.trim().isNotEmpty) {
        accumulated = accumulated.isEmpty
            ? failure.partialContent!
            : '$accumulated\n${failure.partialContent}';
      }

      // غير قابل لإعادة المحاولة أو استنفدنا المحاولات → فشل نهائي
      // مع المحتوى الجزئي المتراكم كاملاً
      if (!failure.isRetryable || attempt > policy.maxRetries) {
        _log.error(
          context,
          failure.isRetryable
              ? 'Max retries exhausted'
              : 'Non-retryable failure',
          correlationId: cid,
          meta: {
            'attempts': attempt,
            'code': failure.code.name,
            'partialContentLength': accumulated.length,
          },
        );
        return RetryOutcome(
          failure: ExecutionFailure(
            code: failure.code,
            detail: '${failure.detail}\n(بعد $attempt محاولة/محاولات)',
            partialContent: accumulated.trim().isEmpty ? null : accumulated,
            isRetryable: false,
          ),
          attempts: attempt,
          accumulatedPartialContent: accumulated,
        );
      }

      // جدولة إعادة المحاولة مع Backoff + Jitter
      final delay = policy.delayFor(attempt);
      final event = ExecutionRetryScheduled(
        attempt: attempt,
        maxAttempts: policy.maxRetries,
        delay: delay,
        reason: failure.code.userMessage,
      );
      onRetryScheduled?.call(event);

      _log.warn(
        context,
        'Retry scheduled',
        correlationId: cid,
        meta: {
          'attempt': attempt,
          'maxRetries': policy.maxRetries,
          'delayMs': delay.inMilliseconds,
          'code': failure.code.name,
        },
      );

      await Future.delayed(delay);
    }
  }
}
