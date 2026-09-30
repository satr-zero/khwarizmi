import 'dart:async';

import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/core/execution/execution_types.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Watchdog الميكانيكية الجديدة (نمط opencode):
//
// المشكلة القديمة: قتل البث «الحي لكن الصامت» بعد 90+30 ثانية سكوت.
// النماذج الضخمة (مثل nemotron-550b) تولّد الرد على الخادم دفعة واحدة
// وتؤجل الإرسال — فيبقى الاتصال حياً ويعمل بلا أحداث لعدة دقائق، ثم
// يصل الرد الكامل. القتل المبكر كان يهدر الرد الصحيح ويعيد الطلب كاملاً.
//
// الفلسفة الجديدة:
//   1. السكوت لا يقتل البث أبداً — فقط «نبض إحاطة» يُظهر للمستخدم أن
//      الطلب ما زال حياً ويعمل ("الخادم يعالج منذ X ثانية").
//   2. السقف المطلق (absoluteCap = 10 دقائق) هو الحماية الوحيدة من
//      التعليق الحقيقي — بعده فقط يُسمح بالإلغاء التلقائي.
//   3. إيقاف المستخدم يعمل فوراً في أي لحظة (خارج هذا الـ Watchdog).
//
// القاعدة الذهبية تبقى: **الاكتمال يتفوق دائماً على الإلغاء**.
// ─────────────────────────────────────────────────────────────────────────────

/// مراحل الـ Watchdog
enum WatchdogPhase {
  /// مسلّح ويراقب — لم تُدرك عتبة السكوت بعد
  armed,

  /// سكوت تجاوز عتبة الإحاطة — البث ما زال حياً ومفتوحاً (لا إلغاء)
  idleAdvisory,

  /// تجاوز السقف المطلق — الإلغاء التلقائي الوحيد المسموح
  expired,
}

/// نتيجة فحص الـ Watchdog عند طلب الإلغاء — تمنع السباق بنيوياً.
enum WatchdogVerdict {
  /// لا إلغاء — وصل اكتمال صالح، أو ما زلنا تحت السقف المطلق
  deliverResult,

  /// إلغاء مسموح — تجاوز البث السقف المطلق
  cancelStream,
}

/// Watchdog بسقف مطلق ونبض إحاطة — ميكانيكية opencode.
///
/// الاستخدام داخل [StreamCollector]:
/// 1. `onEvent()` عند كل حدث بث — يعيد التسليح ويعلّق الإحاطة.
/// 2. `markCompleted()` فور اكتمال صالح — يُجمّد كل شيء نهائياً.
/// 3. `requestCancellation()` قبل أي إلغاء — يفحص الحالة ويعيد الحكم.
class ExecutionWatchdog {
  ExecutionWatchdog({
    this.idleAdvisoryThreshold = TaskExecutionEngineDefaults.idleTimeout,
    this.advisoryInterval = TaskExecutionEngineDefaults.idleTimeout,
    this.absoluteCap = TaskExecutionEngineDefaults.absoluteStreamCap,
    this.onPhaseChanged,
    this.onIdleAdvisory,
    this.correlationId,
    this.context = 'ExecutionWatchdog',
  });

  /// عتبة السكوت قبل أول نبض إحاطة (الافتراضي 90 ثانية) — لا إلغاء
  final Duration idleAdvisoryThreshold;

  /// الفاصل الزمني بين نبضات الإحاطة المتكررة أثناء استمرار السكوت
  final Duration advisoryInterval;

  /// السقف المطلق لانتظار بث واحد — الحماية الوحيدة من التعليق (10 دقائق)
  final Duration absoluteCap;

  /// يُستدعى عند تغيّر المرحلة
  final void Function(WatchdogPhase phase)? onPhaseChanged;

  /// نبض الإحاطة — يُستدعى عند بلوغ عتبة السكوت ثم دورياً طوال استمراره:
  /// "الخادم يعالج منذ X ثانية — البث ما زال مفتوحاً". لا يُلغي شيئاً.
  final void Function(int idleSeconds)? onIdleAdvisory;

  final String? correlationId;
  final String context;

  Timer? _idleTimer;
  Timer? _advisoryTimer;
  Timer? _absoluteTimer;
  DateTime _startedAt = DateTime.now();

  WatchdogPhase _phase = WatchdogPhase.armed;
  bool _completed = false;
  bool _disposed = false;

  final _log = Logger.instance;
  final String _cid = Logger.instance.newCorrelationId();

  /// المرحلة الحالية
  WatchdogPhase get phase => _phase;

  /// هل اكتمل البث صالحاً؟ (الاكتمال يتفوق على أي إلغاء لاحق)
  bool get isCompleted => _completed;

  /// هل تجاوز البث السقف المطلق (المرحلة الوحيدة المسموح فيها الإلغاء)؟
  bool get isExpired => _phase == WatchdogPhase.expired;

  /// يبدأ المراقبة — يُستدعى تلقائياً من المُنشئ؟ لا: يجب استدعاؤه بعد
  /// إنشاء الاشتراك. السقف المطلق يبدأ من هنا ولا يُعاد ضبطه أبداً.
  void arm() {
    if (_disposed || _absoluteTimer != null) return;
    _startedAt = DateTime.now();
    _idleTimer = Timer(idleAdvisoryThreshold, _onIdleAdvisoryThreshold);
    _absoluteTimer = Timer(absoluteCap, _onAbsoluteCapExpired);
  }

  /// يُستدعى عند وصول أي حدث بث (نص، أداة، تفكير، حالة...) — يعيد التسليح
  /// ويعلّق نبض الإحاطة.
  void onEvent() {
    if (_completed || _disposed) return;

    _idleTimer?.cancel();
    _idleTimer = Timer(idleAdvisoryThreshold, _onIdleAdvisoryThreshold);
    _advisoryTimer?.cancel();
    _advisoryTimer = null;

    if (_phase == WatchdogPhase.idleAdvisory) {
      _log.info(
        context,
        'Stream recovered after silent period — re-arming watchdog',
        correlationId: correlationId ?? _cid,
      );
      _setPhase(WatchdogPhase.armed);
    }
  }

  /// يُستدعى فور وصول اكتمال صالح — **يُجمّد كل المؤقتات نهائياً**.
  ///
  /// بعد هذه النقطة لا يمكن لأي مهلة أن تُلغي شيئاً: النتيجة تُسلَّم.
  void markCompleted() {
    if (_completed) return;
    _completed = true;
    _cancelAllTimers();
    _log.info(
      context,
      'Stream completed — watchdog frozen, result will be delivered',
      correlationId: correlationId ?? _cid,
      meta: {'elapsedMs': DateTime.now().difference(_startedAt).inMilliseconds},
    );
  }

  /// **نقطة منع السباق**: يُستدعى قبل أي إلغاء ويعيد حكماً حتمياً.
  ///
  /// - إن اكتمل البث → [WatchdogVerdict.deliverResult] — لا يُلغى شيء.
  /// - إن تجاوز البث السقف المطلق → [WatchdogVerdict.cancelStream].
  /// - ما دون السقف المطلق → لا إلغاء إطلاقاً: البث الصامت حي حتى إشعار
  ///   آخر، والسكوت وحده ليس دليلاً موت (النماذج الضخمة تصمت دقائق).
  WatchdogVerdict requestCancellation() {
    if (_completed) {
      _log.info(
        context,
        'Cancellation requested but stream already completed — delivering result',
        correlationId: correlationId ?? _cid,
      );
      return WatchdogVerdict.deliverResult;
    }
    if (_phase == WatchdogPhase.expired) {
      _log.warn(
        context,
        'Cancellation approved — stream exceeded absolute cap',
        correlationId: correlationId ?? _cid,
        meta: {
          'absoluteCapMinutes': absoluteCap.inMinutes,
          'elapsedMs': DateTime.now().difference(_startedAt).inMilliseconds,
        },
      );
      return WatchdogVerdict.cancelStream;
    }
    // تحت السقف المطلق: لا إلغاء — البث صامت لكنه حي ومفتوح.
    _log.info(
      context,
      'Cancellation denied — stream still within absolute cap, waiting',
      correlationId: correlationId ?? _cid,
      meta: {
        'phase': _phase.name,
        'elapsedMs': DateTime.now().difference(_startedAt).inMilliseconds,
      },
    );
    return WatchdogVerdict.deliverResult;
  }

  /// يُجمّد الـ Watchdog دون اكتمال (إلغاء مستخدم أو تنظيف) — يوقف المؤقتات فقط.
  void dispose() {
    _disposed = true;
    _cancelAllTimers();
  }

  // ── الداخلية ──────────────────────────────────────────────────────────────

  void _onIdleAdvisoryThreshold() {
    if (_completed || _disposed) return;
    _setPhase(WatchdogPhase.idleAdvisory);
    _emitAdvisory();

    // نبضات متكررة طوال استمرار السكوت — المستخدم يرى أن الطلب حي
    var ticks = 0;
    _advisoryTimer = Timer.periodic(advisoryInterval, (_) {
      if (_completed || _disposed) {
        _advisoryTimer?.cancel();
        return;
      }
      ticks++;
      _emitAdvisory(extraSeconds: ticks * advisoryInterval.inSeconds);
    });
  }

  void _emitAdvisory({int extraSeconds = 0}) {
    final idleSeconds =
        idleAdvisoryThreshold.inSeconds + extraSeconds;
    _log.info(
      context,
      'Silent-but-alive stream — advisory heartbeat (no cancellation)',
      correlationId: correlationId ?? _cid,
      meta: {'idleSeconds': idleSeconds},
    );
    onIdleAdvisory?.call(idleSeconds);
  }

  void _onAbsoluteCapExpired() {
    if (_completed || _disposed) return;
    _log.warn(
      context,
      'Absolute stream cap exceeded — cancellation now permitted',
      correlationId: correlationId ?? _cid,
      meta: {
        'absoluteCapMinutes': absoluteCap.inMinutes,
        'totalElapsedMs': DateTime.now().difference(_startedAt).inMilliseconds,
      },
    );
    _setPhase(WatchdogPhase.expired);
  }

  void _setPhase(WatchdogPhase newPhase) {
    if (_phase == newPhase) return;
    _phase = newPhase;
    onPhaseChanged?.call(newPhase);
  }

  void _cancelAllTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _advisoryTimer?.cancel();
    _advisoryTimer = null;
    _absoluteTimer?.cancel();
    _absoluteTimer = null;
  }
}
