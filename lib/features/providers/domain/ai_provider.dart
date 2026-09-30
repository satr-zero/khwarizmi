import '../../agent/domain/entities/agent_event.dart';
import '../../agent/domain/entities/chat_message.dart';
import '../../agent/domain/entities/tool_definition.dart';

/// نمط التفكير: ميزانية ثابتة أو تكيّفي (يقرر النموذج العمق)
enum ThinkingMode { fixedBudget, adaptive }

/// إعداد التفكير الموسَّع (Extended Thinking) — موحَّد عبر جميع المزوّدين.
///
/// كل مزوّد يترجم هذا الإعداد بصيغته الخاصة:
/// - Gemini: `thinkingConfig.thinkingBudget` (fixed) أو `thinkingBudget: -1` / `thinkingLevel` (adaptive)
/// - Claude: `thinking.type=enabled, budget_tokens` (fixed) أو `thinking.type=adaptive` (adaptive)
/// - OpenAI o-series: `reasoning_effort` (adaptive by nature)
/// - مزوّد لا يدعم التفكير: يُتجاهَل صامتًا في الطلب
class ThinkingConfig {
  /// هل التفكير الموسَّع مفعَّل لهذا الطلب؟
  final bool enabled;

  /// نمط التفكير: fixedBudget (ميزانية توكن محددة) أو adaptive (يقرر النموذج)
  final ThinkingMode mode;

  /// ميزانية التفكير بالتوكنات — يُستخدم فقط عند mode == fixedBudget
  final int? budgetTokens;

  /// مستوى الجهد للوضع التكيّفي: "low" / "medium" / "high" / "max"
  /// يُستخدم فقط عند mode == adaptive
  final String? effortLevel;

  const ThinkingConfig({
    required this.enabled,
    this.mode = ThinkingMode.fixedBudget,
    this.budgetTokens,
    this.effortLevel,
  });

  /// إعداد افتراضي للمحادثة العادية (ميزانية ثابتة 8000)
  static const regular = ThinkingConfig(
    enabled: true,
    mode: ThinkingMode.fixedBudget,
    budgetTokens: 8000,
  );

  /// إعداد موسَّع لوضع الكود (ميزانية ثابتة 16000)
  static const coding = ThinkingConfig(
    enabled: true,
    mode: ThinkingMode.fixedBudget,
    budgetTokens: 16000,
  );

  /// إعداد تكيّفي للمحادثة العادية (مستوى جهد high)
  static const adaptiveRegular = ThinkingConfig(
    enabled: true,
    mode: ThinkingMode.adaptive,
    effortLevel: 'high',
  );

  /// إعداد تكيّفي لوضع الكود (أقصى جهد max)
  static const adaptiveCoding = ThinkingConfig(
    enabled: true,
    mode: ThinkingMode.adaptive,
    effortLevel: 'max',
  );
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

