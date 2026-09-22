import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/tools/built_in/autonomous_chat_tools.dart';
import 'package:khwarizmi/features/tools/built_in/browser_tools.dart';
import 'package:khwarizmi/features/tools/built_in/filesystem_tools.dart';
import 'package:khwarizmi/features/tools/built_in/memory_tools.dart';
import 'package:khwarizmi/features/tools/built_in/reminder_tools.dart';
import 'package:khwarizmi/features/tools/built_in/system_info_tool.dart';
import 'package:khwarizmi/features/tools/built_in/task_control_tools.dart';
import 'package:khwarizmi/features/tools/built_in/web_search_tool.dart';
import 'package:khwarizmi/features/skills/domain/load_text_skill_tool.dart';
import 'package:khwarizmi/features/tools/built_in/project_tools.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

class ToolRegistry {
  static final Map<String, AgentTool> _tools = {};
  static final Set<String> _builtInToolNames = {};

  static void initialize() {
    _registerBuiltIn(SystemTimeTool());
    _registerBuiltIn(StoreMemoryTool());
    _registerBuiltIn(SearchMemoryTool());
    _registerBuiltIn(ScheduleReminderTool());
    _registerBuiltIn(ListRemindersTool());
    _registerBuiltIn(CancelReminderTool());
    _registerBuiltIn(WebSearchTool());
    _registerBuiltIn(FetchUrlTool());
    // Phase 6 tools (Full Autonomous Browser):
    _registerBuiltIn(BrowseUrlTool());
    _registerBuiltIn(ScrollPageTool());
    _registerBuiltIn(InspectVisualPageTool());
    _registerBuiltIn(ClickElementTool());
    _registerBuiltIn(FillInputTool());
    _registerBuiltIn(DownloadFileTool());
    _registerBuiltIn(WriteFileTool());
    _registerBuiltIn(ReadFileTool());
    // Phase 7 — task control tools (intercepted by TaskExecutionEngine):
    _registerBuiltIn(AskUserTool());
    _registerBuiltIn(ReportProgressTool());
    _registerBuiltIn(CompleteTaskTool());
    // Chat autonomous tools:
    _registerBuiltIn(StartAutonomousTaskTool());
    _registerBuiltIn(ResumeTaskTool());
    // Phase 8: Text Skills (المهارات النصية الإرشادية):
    _registerBuiltIn(LoadTextSkillTool());
    // Phase 9: Project Coding Agent tools:
    _registerBuiltIn(ProposeFileChangeTool());
    _registerBuiltIn(RunTerminalCommandTool());
    _registerBuiltIn(ReadProjectFileTool());
    _registerBuiltIn(ListProjectFilesTool());
    _registerBuiltIn(RefreshProjectMapTool());
  }

  static void _registerBuiltIn(AgentTool tool) {
    _builtInToolNames.add(tool.definition.name);
    _tools[tool.definition.name] = tool;
  }

  /// هل الاسم محجوز كأداة مدمجة في النظام؟
  static bool isBuiltInTool(String name) => _builtInToolNames.contains(name);

  /// تسجيل أداة مع منع التصادم في الأسماء
  static bool registerTool(AgentTool tool, {bool overwrite = false}) {
    final name = tool.definition.name;
    // حماية تامة للأدوات المدمجة من الاستبدال أو التصادم
    if (_builtInToolNames.contains(name)) {
      // ignore: avoid_print
      print('[ToolRegistry] ERROR: Tool name "$name" is a reserved built-in tool. External registration rejected.');
      return false;
    }
    if (_tools.containsKey(name) && !overwrite) {
      // ignore: avoid_print
      print('[ToolRegistry] WARNING: Collision detected for tool "$name". A tool with this name is already registered. Registration rejected.');
      return false;
    }
    _tools[name] = tool;
    return true;
  }

  /// إلغاء تسجيل أداة بالاسم (مثلاً عند تعطيل Skill)
  static bool unregisterTool(String name) {
    return _tools.remove(name) != null;
  }

  /// فحص ما إذا كانت الأداة مسجلة مسبقاً
  static bool isToolRegistered(String name) {
    return _tools.containsKey(name);
  }

  /// إعادة تعيين الأدوات للاختبارات
  static void clear() {
    _tools.clear();
  }

  static List<ToolDefinition> getAvailableDefinitions() {
    return _tools.values.map((t) => t.definition).toList();
  }

  /// أدوات المحادثة العادية فقط (بدون أدوات التحكم بالمهام المستقلة)
  static List<ToolDefinition> getChatDefinitions() {
    return _tools.values
        .where((t) => !t.definition.isControlTool)
        .map((t) => t.definition)
        .toList();
  }

  /// جميع الأدوات بما فيها أدوات التحكم — للمهام المستقلة
  static List<ToolDefinition> getAutonomousDefinitions() {
    return _tools.values.map((t) => t.definition).toList();
  }

  static Future<String> executeTool(String name, Map<String, dynamic> arguments) async {
    final tool = _tools[name];
    if (tool == null) {
      return '{"error": "Tool \'$name\' not found in registry."}';
    }
    try {
      return await tool.execute(arguments);
    } catch (e) {
      return '{"error": "Failed executing tool \'$name\': $e"}';
    }
  }
}
