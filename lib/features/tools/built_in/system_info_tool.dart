import 'package:intl/intl.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

class SystemTimeTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'get_system_time',
    description: 'Returns the exact current local system time, date, and day of week on Windows.',
    parameters: {
      'type': 'OBJECT',
      'properties': {},
    },
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final dayName = DateFormat('EEEE').format(now);
    return '{"current_time": "${formatter.format(now)}", "day": "$dayName", "timezone": "${now.timeZoneName}"}';
  }
}
