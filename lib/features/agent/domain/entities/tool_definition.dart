class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // OpenAPI 3.0 / JSON Schema

  /// إذا كانت true، هذه الأداة تُعترض من [TaskExecutionEngine] ولا تصل لـ [ToolRegistry]
  final bool isControlTool;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.isControlTool = false,
  });

  /// Schema for Google Gemini tools
  Map<String, dynamic> toGeminiSchema() {
    return {
      'name': name,
      'description': description,
      'parameters': parameters,
    };
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
