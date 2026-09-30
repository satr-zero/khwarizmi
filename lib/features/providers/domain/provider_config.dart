class ProviderConfig {
  final String id;
  final String displayName;
  final String type; // 'gemini', 'claude', 'openai_compatible'
  final String baseUrl;
  final String defaultModel;
  final List<String> availableModels;
  final bool isCustom;

  /// معاملات إضافية تُدمَج تلقائياً في جسم كل طلب لهذا المزوّد.
  /// مفيد للمزوّدين الذين يدعمون حقولاً خارج صيغة OpenAI القياسية
  /// مثال NVIDIA: {"reasoning_effort": "max"}
  final Map<String, dynamic> extraBodyParams;

  /// هل هذا المزوّد يدعم Extended Thinking بشكل عام؟ (ميزانية ثابتة)
  final bool supportsThinking;

  /// هل هذا المزوّد يدعم الوضع التكيّفي للتفكير؟ (Adaptive Thinking)
  /// حقل منفصل لأن ليس كل موديل يدعم التفكير يدعم الوضع التكيّفي
  final bool supportsAdaptiveThinking;

  /// قائمة الموديلات (بالاسم الكامل) التي تدعم التفكير الموسَّع ضمن هذا المزوّد.
  /// إن كانت فارغة مع [supportsThinking]=true، يعني كل موديلاته داعمة.
  final List<String> thinkingModelIds;

  /// هل اجتاز هذا المزوّد اختبار قدرة استدعاء الأدوات؟
  /// null = لم يُختبر بعد، true = اجتاز، false = فشل.
  final bool? toolCallCapable;

  const ProviderConfig({
    required this.id,
    required this.displayName,
    required this.type,
    required this.baseUrl,
    required this.defaultModel,
    this.availableModels = const [],
    this.isCustom = false,
    this.extraBodyParams = const {},
    this.supportsThinking = false,
    this.supportsAdaptiveThinking = false,
    this.thinkingModelIds = const [],
    this.toolCallCapable,
  });

  /// هل الموديل المحدد يدعم التفكير الموسَّع (ميزانية ثابتة)؟
  bool doesModelSupportThinking(String modelId) {
    if (!supportsThinking) return false;
    if (thinkingModelIds.isEmpty) return true; // كل الموديلات داعمة
    return thinkingModelIds.any(
      (m) => modelId.contains(m) || m.contains(modelId),
    );
  }

  /// هل الموديل المحدد يدعم الوضع التكيّفي للتفكير؟
  bool doesModelSupportAdaptiveThinking(String modelId) {
    if (!supportsAdaptiveThinking) return false;
    if (thinkingModelIds.isEmpty) {
      return true; // كل الموديلات الداعمة للتفكير تدعم التكيفي أيضاً
    }
    return thinkingModelIds.any(
      (m) => modelId.contains(m) || m.contains(modelId),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'type': type,
    'baseUrl': baseUrl,
    'defaultModel': defaultModel,
    'availableModels': availableModels,
    'isCustom': isCustom,
    'extraBodyParams': extraBodyParams,
    'supportsThinking': supportsThinking,
    'supportsAdaptiveThinking': supportsAdaptiveThinking,
    'thinkingModelIds': thinkingModelIds,
    if (toolCallCapable != null) 'toolCallCapable': toolCallCapable,
  };

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    type: json['type'] as String? ?? 'openai_compatible',
    baseUrl: json['baseUrl'] as String? ?? '',
    defaultModel: json['defaultModel'] as String? ?? '',
    availableModels:
        (json['availableModels'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    isCustom: json['isCustom'] as bool? ?? false,
    extraBodyParams: (json['extraBodyParams'] as Map<String, dynamic>?) ?? {},
    supportsThinking: json['supportsThinking'] as bool? ?? false,
    supportsAdaptiveThinking:
        json['supportsAdaptiveThinking'] as bool? ?? false,
    thinkingModelIds:
        (json['thinkingModelIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    toolCallCapable: json['toolCallCapable'] as bool?,
  );

  ProviderConfig copyWith({
    bool? toolCallCapable,
    bool setToolCallCapableNull = false,
    bool? supportsAdaptiveThinking,
  }) {
    return ProviderConfig(
      id: id,
      displayName: displayName,
      type: type,
      baseUrl: baseUrl,
      defaultModel: defaultModel,
      availableModels: availableModels,
      isCustom: isCustom,
      extraBodyParams: extraBodyParams,
      supportsThinking: supportsThinking,
      supportsAdaptiveThinking:
          supportsAdaptiveThinking ?? this.supportsAdaptiveThinking,
      thinkingModelIds: thinkingModelIds,
      toolCallCapable: setToolCallCapableNull
          ? null
          : (toolCallCapable ?? this.toolCallCapable),
    );
  }
}
