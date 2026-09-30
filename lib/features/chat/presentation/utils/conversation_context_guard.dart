import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/agent/domain/entities/chat_message.dart';

/// ضغط تلقائي للسياق عند الاقتراب من سقف الأحرف لتجنب تجمد النموذج.
abstract final class ConversationContextGuard {
  /// حد تقريبي للأحرف قبل بدء الضغط (قابل للضبط).
  static const int defaultCharBudget = 120_000;

  static List<ChatMessage> compressIfNeeded(
    List<ChatMessage> history, {
    int charBudget = defaultCharBudget,
  }) {
    var total = _estimateChars(history);
    if (total <= charBudget) return history;

    debugPrint(
      '[ConversationContextGuard] Compressing context: ~$total chars > $charBudget',
    );

    final kept = <ChatMessage>[];
    ChatMessage? rollingSummary;

    for (final msg in history) {
      if (msg.role == MessageRole.system &&
          msg.content.startsWith('[ملخص سياق مضغوط]')) {
        rollingSummary = msg;
        continue;
      }
      kept.add(msg);
    }

    final dropCount = (kept.length * 0.35).ceil().clamp(2, kept.length - 4);
    final removed = kept.take(dropCount).toList();
    kept.removeRange(0, dropCount);

    final summaryText = StringBuffer('[ملخص سياق مضغوط — تم حذف $dropCount رسالة قديمة]\n');
    for (final m in removed) {
      if (m.role == MessageRole.user || m.role == MessageRole.assistant) {
        final snippet = m.content.length > 280
            ? '${m.content.substring(0, 280)}…'
            : m.content;
        summaryText.writeln('- ${m.role.name}: $snippet');
      }
    }

    final summaryMsg = ChatMessage(
      id: 'ctx_summary_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.system,
      content: summaryText.toString(),
      timestamp: DateTime.now(),
    );

    if (rollingSummary != null) {
      return [rollingSummary, summaryMsg, ...kept];
    }
    return [summaryMsg, ...kept];
  }

  static int _estimateChars(List<ChatMessage> history) {
    var n = 0;
    for (final m in history) {
      n += m.content.length;
      if (m.thinkingContent != null) n += m.thinkingContent!.length;
    }
    return n;
  }
}
