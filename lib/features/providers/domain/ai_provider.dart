import '../../agent/domain/entities/agent_event.dart';
import '../../agent/domain/entities/chat_message.dart';
import '../../agent/domain/entities/tool_definition.dart';

/// إعداد التفكير الموسَّع (Extended Thinking) — موحَّد عبر جميع المزوّدين.
///
/// كل مزوّد يترجم هذا الإعداد بصيغته الخاصة:
/// - Gemini: `thinkingConfig.thinkingBudget`
/// - Claude: `thinking.type=enabled, budget_tokens`
/// - OpenAI o-series: `reasoning_effort=high` (عبر extraBodyParams)
/// - مزوّد لا يدعم التفكير: يُتجاهَل صامتًا في الطلب
class ThinkingConfig {
  /// هل التفكير الموسَّع مفعَّل لهذا الطلب؟
  final bool enabled;

  /// ميزانية التفكير بالتوكنات (الحد الأقصى للتفكير الداخلي).
  /// - محادثة عادية: 8000
  /// - وضع الكود: 16000
  final int budgetTokens;

  const ThinkingConfig({
    required this.enabled,
    this.budgetTokens = 8000,
  });

  /// إعداد افتراضي للمحادثة العادية
  static const regular = ThinkingConfig(enabled: true, budgetTokens: 8000);

  /// إعداد موسَّع لوضع الكود (الحد الأقصى المتاح)
  static const coding = ThinkingConfig(enabled: true, budgetTokens: 16000);
}

abstract class AiProvider {
  String get id;
  String get displayName;
  List<String> get availableModels;
  String get defaultModel;

  /// Dynamically fetches available models from the provider's official /models endpoint.
  /// Falls back to [availableModels] if the call fails, times out, or is unsupported.
  Future<List<String>> fetchModels(String apiKey);

  Stream<AgentEvent> sendMessage({
    required List<ChatMessage> history,
    required List<ToolDefinition> availableTools,
    required String systemPrompt,
    required String apiKey,
    String? modelName,
    ThinkingConfig? thinking,
  });
}

