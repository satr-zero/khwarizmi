import 'dart:async';

import 'package:khwarizmi/core/logging.dart';

/// يراقب انقطاع البث التدفقي (SSE) ويُنهي الانتظار بمهلة إذا سكت المصدر.
class AgentStreamWatchdog {
  AgentStreamWatchdog({
    this.idleTimeout = const Duration(seconds: 90),
    this.onIdleTimeout,
    this.onCancelStream,
    this.correlationId,
    this.context,
  });

  final Duration idleTimeout;
  final void Function()? onIdleTimeout;
  final void Function()? onCancelStream;
  final String? correlationId;
  final String? context;

  Timer? _timer;
  bool _fired = false;
  final _log = Logger.instance;
  final _cid = Logger.instance.newCorrelationId();

  void onEvent() {
    _timer?.cancel();
    _timer = Timer(idleTimeout, () {
      if (_fired) return;
      _fired = true;
      _log.warn(
        context ?? 'AgentStreamWatchdog',
        'Idle timeout fired — no events for ${idleTimeout.inSeconds}s',
        correlationId: correlationId ?? _cid,
        meta: {'idleTimeoutSeconds': idleTimeout.inSeconds},
      );
      onIdleTimeout?.call();
      // Attempt to cancel the underlying stream subscription
      onCancelStream?.call();
    });
    _log.trace(
      context ?? 'AgentStreamWatchdog',
      'Event received — timer reset',
      correlationId: correlationId ?? _cid,
      meta: {'idleTimeoutSeconds': idleTimeout.inSeconds},
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _log.trace(
      context ?? 'AgentStreamWatchdog',
      'Disposed',
      correlationId: correlationId ?? _cid,
    );
  }

  bool get hasTimedOut => _fired;
}
