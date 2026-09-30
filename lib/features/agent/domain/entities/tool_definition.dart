class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // OpenAPI 3.0 / JSON Schema

  /// إذا كانت true، هذه الأداة تُعترض من [TaskExecutionEngine] ولا تصل لـ [ToolRegistry]
  final bool isControlTool;

  /// مهلة تنفيذ الأداة بالثواني — إصلاح 06: مهلة ديناميكية لكل أداة بدل
  /// 60 ثانية ثابتة للجميع. null يعني الافتراضي (60). الأدوات طويلة
  /// التشغيل (مثل run_terminal_command) تحدد قيماً أعلى لتتسع لأوامرها
  /// الداخلية وإلا تُقتل قبل أن تبدأ فعلياً.
  final int? timeoutSeconds;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.isControlTool = false,
    this.timeoutSeconds,
  });

  /// Schema for Google Gemini tools
  Map<String, dynamic> toGeminiSchema() {
    return {'name': name, 'description': description, 'parameters': parameters};
  }

  /// Schema for OpenAI / OpenAI-compatible tools
  Map<String, dynamic> toOpenAiSchema() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }

  /// Schema for Anthropic Claude tools
  Map<String, dynamic> toClaudeSchema() {
    return {
      'name': name,
      'description': description,
      'input_schema': parameters,
    };
  }
}
