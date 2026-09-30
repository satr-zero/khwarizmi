import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';

abstract class AgentTool {
  ToolDefinition get definition;
  Future<String> execute(Map<String, dynamic> arguments);
}
