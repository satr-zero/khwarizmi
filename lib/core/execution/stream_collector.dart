import 'dart:async';

import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/core/execution/execution_types.dart';
import 'package:khwarizmi/core/execution/execution_watchdog.dart';
import 'package:khwarizmi/features/agent/domain/entities/agent_event.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';

// ─────────────────────────────────────────────────────────────────────────────
// جامع البث الموحّد — المستهلك الوحيد لبث المزوّدين في التطبيق كله.
//
// ميكانيكية opencode (لا قتل للبث الصامت):
// - الاشتراك الوحيد في بث المزوّد يحدث هنا — لا مكان آخر.
// - السكوت وحده لا يُلغي البث أبداً: النماذج الضخمة تولّد على الخادم
//   دقائق بلا أحداث ثم يصل الرد كاملاً — يُرسل نبض إحاطة فقط
//   (onIdleAdvisory) ليعرف المستخدم أن الطلب حي ويعمل.
// - [ExecutionWatchdog] بمراحله يقرر: السقف المطلق فقط هو الحماية
//   من التعليق الحقيقي، والاكتمال يتفوق دائماً على الإلغاء.
// - عند الإلغاء الحقيقي: النص الجزئي المُستقبَل يُحفظ ولا يُهدر أبداً.
// ─────────────────────────────────────────────────────────────────────────────

/// نتيجة جمع بث واحد من المزوّد
class StreamCollectionResult {
  /// النص الكامل المتراكم من الرد
  final String text;

  /// نص التفكير الداخلي المتراكم (إن وجد)
  final String thinking;

  /// استدعاءات الأدوات التي طلبها النموذج
  final List<ToolCallInfo> toolCalls;

  /// هل اكتمل البث صالحاً (وصل Done أو أُغلق بشكل طبيعي)؟
  final bool completed;

  /// سبب عدم الاكتمال إن لم يكتمل — فشل مُصنَّف
  final ExecutionFailure? failure;

  const StreamCollectionResult({
    required this.text,
    required this.thinking,
    required this.toolCalls,
    required this.completed,
    this.failure,
  });

  /// هل الرد يحتوي محتوى قابلاً للاستخدام (نص أو أدوات)؟
  bool get hasUsableContent => text.trim().isNotEmpty || toolCalls.isNotEmpty;
}

/// جامع البث — يشترك مرة واحدة، يجمع كل الأحداث، ويحسم النتيجة حتمياً.
class StreamCollector {
  StreamCollector({
    this.idleAdvisoryThreshold = TaskExecutionEngineDefaults.idleTimeout,
    this.advisoryInterval = TaskExecutionEngineDefaults.idleTimeout,
    this.absoluteCap = TaskExecutionEngineDefaults.absoluteStreamCap,
    this.correlationId,
    this.context = 'StreamCollector',
  });

  /// عتبة السكوت قبل أول نبض إحاطة (لا إلغاء — البث الصامت حي)
  final Duration idleAdvisoryThreshold;

  /// الفاصل بين نبضات الإحاطة المتكررة أثناء استمرار السكوت
  final Duration advisoryInterval;

  /// السقف المطلق لانتظار بث واحد — الحماية الوحيدة من التعليق
  final Duration absoluteCap;

  final String? correlationId;
  final String context;

  final _log = Logger.instance;

  /// يجمع بث المزوّد الواحد حتى حسم نهائي (اكتمال / فشل مُصنَّف / إلغاء).
  ///
  /// [onEvent] يُستدعى حياً مع كل حدث (لعرض النص المتدفق في الواجهة).
  /// [shouldAbort] يُفحص قبل البدء وبعد كل حدث — إلغاء المستخدم مثلاً.
  /// [onIdleAdvisory] نبض إحاطة أثناء السكوت الطويل: "الخادم يعالج منذ
  /// X ثانية" — البث ما زال مفتوحاً ولا يُلغى شيئاً (ميكانيكية opencode).
  ///
  /// الضمانات:
  /// 1. اكتمال صالح → [StreamCollectionResult.completed] = true دائماً.
  /// 2. السكوت وحده لا يقتل البث — فقط السقف المطلق أو إيقاف المستخدم.
  /// 3. لا يُرمى استثناء أبداً — كل فشل يُعاد مغلّفاً في
  ///    [StreamCollectionResult.failure].
  Future<StreamCollectionResult> collect(
    Stream<AgentEvent> stream, {
    void Function(AgentEvent event)? onEvent,
    bool Function()? shouldAbort,
    Future<void>? abortSignal,
    void Function(int idleSeconds)? onIdleAdvisory,
  }) async {
    final completer = Completer<StreamCollectionResult>();
    final cid = correlationId ?? _log.newCorrelationId();

    final buffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final toolCalls = <ToolCallInfo>[];

    StreamSubscription<AgentEvent>? subscription;
    late final ExecutionWatchdog watchdog;

    // ── حسم النتيجة — نقطة واحدة فقط تُكمل الـ Completer ──────────────────
    void settle(StreamCollectionResult result) {
      if (completer.isCompleted) return;
      watchdog.dispose();
      completer.complete(result);
    }

    // ── الإلغاء التلقائي الوحيد: تجاوز السقف المطلق ────────────────────────
    // السكوت وحده لا يلغي — النماذج الضخمة تولّد على الخادم دقائق بلا
    // أحداث ثم يصل الرد كاملاً. السقف المطلق يحمي من التعليق الحقيقي فقط.
    void attemptCancellation() {
      final verdict = watchdog.requestCancellation();
      if (verdict == WatchdogVerdict.cancelStream) {
        // تجاوز السقف المطلق — إلغاء فعلي مع حفظ الجزئي
        subscription?.cancel();
        settle(
          StreamCollectionResult(
            text: buffer.toString(),
            thinking: thinkingBuffer.toString(),
            toolCalls: List.unmodifiable(toolCalls),
            completed: false,
            failure: ExecutionFailure(
              code: ExecutionFailureCode.streamIdleTimeout,
              detail:
                  'Stream exceeded the absolute cap '
                  '(${absoluteCap.inMinutes} minutes) — presumed dead connection',
              partialContent: buffer.toString().trim().isEmpty
                  ? null
                  : buffer.toString(),
              isRetryable: true,
            ),
          ),
        );
      }
      // deliverResult → لا نفعل شيئاً: البث ما زال مفتوحاً والاكتمال وارد
    }

    watchdog = ExecutionWatchdog(
      idleAdvisoryThreshold: idleAdvisoryThreshold,
      advisoryInterval: advisoryInterval,
      absoluteCap: absoluteCap,
      correlationId: cid,
      context: context,
      // عند بلوغ السقف المطلق فقط — نحاول الإلغاء عبر حكم الـ Watchdog
      onPhaseChanged: (phase) {
        if (phase == WatchdogPhase.expired) {
          attemptCancellation();
        }
      },
      onIdleAdvisory: onIdleAdvisory,
    );
    watchdog.arm();

    // إلغاء المستخدم قبل البدء
    if (shouldAbort != null && shouldAbort()) {
      watchdog.dispose();
      return StreamCollectionResult(
        text: '',
        thinking: '',
        toolCalls: const [],
        completed: false,
        failure: const ExecutionFailure(
          code: ExecutionFailureCode.cancelledByUser,
          detail: 'Aborted before stream started',
        ),
      );
    }

    // ── إشارة إلغاء خارجية (زر الإيقاف) — تُحسم فوراً حتى أثناء السكوت ────
    // shouldAbort يُفحص فقط عند وصول أحداث؛ إشارة مستقبل مستقلة تضمن حسم
    // الطلب حتى لو كان البث صامتاً تماماً (لا أحداث تصل لتفحص shouldAbort).
    // لا حاجة لإلغاء الاشتراك هنا: الاستدعاء المتأخر محمي بـ isCompleted.
    if (abortSignal != null) {
      unawaited(
        abortSignal.then((_) {
          if (completer.isCompleted) return;
          watchdog.markCompleted(); // منع أي مؤقت لاحق من اللمس
          subscription?.cancel();
          settle(
            StreamCollectionResult(
              text: buffer.toString(),
              thinking: thinkingBuffer.toString(),
              toolCalls: List.unmodifiable(toolCalls),
              completed: false,
              failure: ExecutionFailure(
                code: ExecutionFailureCode.cancelledByUser,
                detail: 'User aborted via external signal',
                partialContent: buffer.toString().trim().isEmpty
                    ? null
                    : buffer.toString(),
              ),
            ),
          );
        }),
      );
    }

    subscription = stream.listen(
      (event) {
        if (completer.isCompleted) return;

        // إلغاء المستخدم أثناء البث — يُحسم فوراً مع حفظ الجزئي
        if (shouldAbort != null && shouldAbort()) {
          watchdog.markCompleted(); // منع أي مؤقت لاحق من اللمس
          subscription?.cancel();
          settle(
            StreamCollectionResult(
              text: buffer.toString(),
              thinking: thinkingBuffer.toString(),
              toolCalls: List.unmodifiable(toolCalls),
              completed: false,
              failure: ExecutionFailure(
                code: ExecutionFailureCode.cancelledByUser,
                detail: 'User aborted mid-stream',
                partialContent: buffer.toString().trim().isEmpty
                    ? null
                    : buffer.toString(),
              ),
            ),
          );
          return;
        }

        watchdog.onEvent();
        onEvent?.call(event);

        switch (event) {
          case AgentTextChunk(:final text):
            buffer.write(text);
          case AgentThinkingChunkEvent(:final text):
            thinkingBuffer.write(text);
          case AgentToolCallEvent(:final toolCall):
            toolCalls.add(toolCall);
          case AgentStatusEvent():
            break; // تُمرر للواجهة عبر onEvent فقط
          case AgentRetryEvent():
            // إعادة تشغيل البث من المزوّد داخلياً — تفريغ المخازن لتفادي
            // تكرار النص المتراكم عند إعادة البث من الصفر (سلوك المتحكم القديم).
            buffer
              ..clear()
              ..write('');
            thinkingBuffer.clear();
            toolCalls.clear();
          case AgentErrorEvent(:final message, :final code):
            // خطأ من المزوّد نفسه — فشل مُصنَّف مع حفظ الجزئي
            watchdog.markCompleted();
            subscription?.cancel();
            settle(
              StreamCollectionResult(
                text: buffer.toString(),
                thinking: thinkingBuffer.toString(),
                toolCalls: List.unmodifiable(toolCalls),
                completed: false,
                failure: ExecutionFailure(
                  code: _classifyProviderError(message, code),
                  detail: message,
                  partialContent: buffer.toString().trim().isEmpty
                      ? null
                      : buffer.toString(),
                  isRetryable: _isRetryableMessage(message, code),
                ),
              ),
            );
          case AgentDoneEvent():
            // ✅ اكتمال صالح — يُجمّد الـ Watchdog فوراً ويسلَّم الناتج كاملاً
            watchdog.markCompleted();
            settle(
              StreamCollectionResult(
                text: buffer.toString(),
                thinking: thinkingBuffer.toString(),
                toolCalls: List.unmodifiable(toolCalls),
                completed: true,
              ),
            );
        }
      },
      onError: (Object error) {
        if (completer.isCompleted) return;
        watchdog.markCompleted();
        settle(
          StreamCollectionResult(
            text: buffer.toString(),
            thinking: thinkingBuffer.toString(),
            toolCalls: List.unmodifiable(toolCalls),
            completed: false,
            failure: ExecutionFailure(
              code: _classifyStreamError(error),
              detail: error.toString(),
              partialContent: buffer.toString().trim().isEmpty
                  ? null
                  : buffer.toString(),
              isRetryable: _isRetryableError(error),
            ),
          ),
        );
      },
      onDone: () {
        if (completer.isCompleted) return;
        // البث أُغلق طبيعياً دون AgentDoneEvent صريح — يُعامل كاكتمال
        watchdog.markCompleted();
        settle(
          StreamCollectionResult(
            text: buffer.toString(),
            thinking: thinkingBuffer.toString(),
            toolCalls: List.unmodifiable(toolCalls),
            completed: true,
          ),
        );
      },
      cancelOnError: false,
    );

    final result = await completer.future;
    // لا ننتظر مستقبل cancel(): مع بث من مولّد async* لا يكتمل المستقبل
    // إلا بعد أن يُنهي المولّد عمله كاملاً — وقد يستمر دقائق في بث حي
    // معلّق. كان هذا يحجب تسليم النتيجة/الفشل طوال هذه المدة (ثغرة
    // حقيقية: تأخر تسليم الفشل 3 دقائق كاملة عن لحظة الحسم).
    unawaited(subscription.cancel());
    return result;
  }

  // ── تصنيف الأخطاء ──────────────────────────────────────────────────────────

  ExecutionFailureCode _classifyProviderError(String message, String? code) {
    final m = message.toLowerCase();
    if (code == 'MISSING_API_KEY' ||
        m.contains('api key') ||
        m.contains('401')) {
      return ExecutionFailureCode.providerHttpError;
    }
    if (m.contains('429') || m.contains('rate') || m.contains('limit')) {
      return ExecutionFailureCode.providerHttpError;
    }
    if (m.contains('timeout') || m.contains('timed out')) {
      return ExecutionFailureCode.streamIdleTimeout;
    }
    return ExecutionFailureCode.unexpectedError;
  }

  bool _isRetryableMessage(String message, String? code) {
    final m = message.toLowerCase();
    return m.contains('429') ||
        m.contains('rate') ||
        m.contains('limit') ||
        m.contains('500') ||
        m.contains('502') ||
        m.contains('503') ||
        m.contains('504') ||
        m.contains('timeout') ||
        m.contains('network');
  }

  ExecutionFailureCode _classifyStreamError(Object error) {
    final e = error.toString().toLowerCase();
    if (e.contains('socket') ||
        e.contains('connection') ||
        e.contains('network') ||
        e.contains('failed host')) {
      return ExecutionFailureCode.networkError;
    }
    if (e.contains('http_4') || e.contains('http_5')) {
      return ExecutionFailureCode.providerHttpError;
    }
    if (e.contains('timeout')) {
      return ExecutionFailureCode.streamIdleTimeout;
    }
    return ExecutionFailureCode.unexpectedError;
  }

  bool _isRetryableError(Object error) {
    final e = error.toString().toLowerCase();
    return e.contains('socket') ||
        e.contains('connection') ||
        e.contains('network') ||
        e.contains('timeout') ||
        e.contains('http_429') ||
        e.contains('http_500') ||
        e.contains('http_502') ||
        e.contains('http_503') ||
        e.contains('http_504');
  }
}
