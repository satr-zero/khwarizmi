import 'dart:convert';

import 'package:khwarizmi/core/logging.dart';
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/tools/built_in/autonomous_chat_tools.dart';
import 'package:khwarizmi/features/tools/built_in/browser_tools.dart';
import 'package:khwarizmi/features/tools/built_in/deliver_file_tool.dart';
import 'package:khwarizmi/features/tools/built_in/filesystem_tools.dart';
import 'package:khwarizmi/features/tools/built_in/memory_tools.dart';
import 'package:khwarizmi/features/tools/built_in/reminder_tools.dart';
import 'package:khwarizmi/features/tools/built_in/system_info_tool.dart';
import 'package:khwarizmi/features/tools/built_in/task_control_tools.dart';
import 'package:khwarizmi/features/tools/built_in/web_search_tool.dart';
import 'package:khwarizmi/features/skills/domain/load_text_skill_tool.dart';
import 'package:khwarizmi/features/tools/built_in/project_tools.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';
import 'package:khwarizmi/features/tools/domain/tool_cancellation_token.dart';

class ToolRegistry {
  static final Map<String, AgentTool> _tools = {};
  static final Set<String> _builtInToolNames = {};

  /// رموز إلغاء التنفيذات الجارية — المفتاح هو اسم الأداة.
  /// إصلاح 10: زر الإيقاف/إلغاء المهمة كانا يقطعان بث الأحداث فقط بينما
  /// استدعاء الأداة الجاري (مثل أمر ترمينال طويل) يستمر حتى نهايته.
  static final Map<String, ToolCancellationToken> _activeTokens = {};

  static final _log = Logger.instance;

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
    _registerBuiltIn(DeliverFileTool());
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
    _registerBuiltIn(ProposeFilePatchTool());
    _registerBuiltIn(RunTerminalCommandTool());
    _registerBuiltIn(ReadProjectFileTool());
    _registerBuiltIn(ListProjectFilesTool());
    _registerBuiltIn(RefreshProjectMapTool());
    _registerBuiltIn(SearchProjectCodeTool());
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
      print(
        '[ToolRegistry] ERROR: Tool name "$name" is a reserved built-in tool. External registration rejected.',
      );
      return false;
    }
    if (_tools.containsKey(name) && !overwrite) {
      // ignore: avoid_print
      print(
        '[ToolRegistry] WARNING: Collision detected for tool "$name". A tool with this name is already registered. Registration rejected.',
      );
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
    _activeTokens.clear();
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

  /// ينفّذ أداة بالاسم مع دعم الإلغاء. يسجّل رمز الإلغاء طوال التنفيذ
  /// لتتمكن الأداة (عبر [activeTokenFor]) من الاستجابة لزر الإيقاف.
  static Future<String> executeTool(
    String name,
    Map<String, dynamic> arguments, {
    ToolCancellationToken? cancellationToken,
    String? correlationId,
    String? taskId,
  }) async {
    final cid = correlationId ?? Logger.instance.newCorrelationId();
    final startTime = DateTime.now();

    _log.info(
      'ToolRegistry.executeTool',
      'Tool execution started',
      correlationId: cid,
      taskId: taskId,
      meta: {'tool': name, 'args': _sanitizeArgs(arguments)},
    );

    final tool = _tools[name];
    if (tool == null) {
      _log.error(
        'ToolRegistry.executeTool',
        'Tool not found in registry',
        correlationId: cid,
        taskId: taskId,
        meta: {'tool': name, 'availableTools': _tools.keys.toList()},
      );
      return '{"error": "Tool \'$name\' not found in registry."}';
    }
    final token = cancellationToken ?? ToolCancellationToken();
    _activeTokens[name] = token;
    try {
      final result = await tool.execute(arguments);
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      _log.info(
        'ToolRegistry.executeTool',
        'Tool execution completed',
        correlationId: cid,
        taskId: taskId,
        meta: {
          'tool': name,
          'durationMs': duration,
          'resultLength': result.length,
          'success': true,
        },
      );
      return result;
    } on ToolCancelledException catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      _log.warn(
        'ToolRegistry.executeTool',
        'Tool execution cancelled',
        correlationId: cid,
        taskId: taskId,
        meta: {'tool': name, 'durationMs': duration, 'reason': e.reason},
      );
      return jsonEncode({'cancelled': true, 'reason': e.reason});
    } catch (e, st) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      _log.error(
        'ToolRegistry.executeTool',
        'Tool execution failed: ${e.toString()}',
        correlationId: cid,
        taskId: taskId,
        stackTrace: st,
        meta: {'tool': name, 'durationMs': duration, 'error': e.toString()},
      );
      return '{"error": "Failed executing tool \'$name\': $e"}';
    } finally {
      if (identical(_activeTokens[name], token)) {
        _activeTokens.remove(name);
      }
    }
  }

  /// Sanitizes arguments for logging (removes sensitive data)
  static Map<String, dynamic> _sanitizeArgs(Map<String, dynamic> args) {
    final sanitized = <String, dynamic>{};
    for (final entry in args.entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('password') ||
          key.contains('secret') ||
          key.contains('token') ||
          key.contains('key') ||
          key.contains('auth') ||
          key.contains('credential')) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is String &&
          (entry.value as String).length > 500) {
        sanitized[entry.key] =
            '${(entry.value as String).substring(0, 500)}... [truncated ${(entry.value as String).length} chars]';
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  /// رمز الإلغاء الجاري لأداة بالاسم — تستخدمه الأدوات القابلة للإلغاء
  /// (مثل run_terminal_command) للوصول إلى رمز تنفيذها الحالي.
  static ToolCancellationToken? activeTokenFor(String name) =>
      _activeTokens[name];

  /// يلغي كل الأدوات قيد التنفيذ فوراً — يُستدعى من زر الإيقاف في المحادثة
  /// ومن إلغاء المهام المستقلة. يُرجع عدد التنفيذات التي شملها الإلغاء.
  static int cancelActiveTools([String reason = 'cancelled']) {
    final tokens = List<ToolCancellationToken>.of(_activeTokens.values);
    for (final token in tokens) {
      token.cancel(reason);
    }
    return tokens.length;
  }

  /// إلغاء تنفيذ أداة واحدة بالاسم — إصلاح 06: عند انتهاء المهلة الخارجية
  /// يجب إلغاء التنفيذ فعلياً (قتل العملية الداخلية للأدوات القابلة
  /// للإلغاء) لا الاكتفاء بتجاهل نتيجتها.
  static void cancelToolExecution(String name, [String reason = 'cancelled']) {
    _activeTokens[name]?.cancel(reason);
  }

  /// مهلة تنفيذ الأداة بالاسم — إصلاح 06: قيمة ديناميكية من تعريف الأداة
  /// (timeoutSeconds) بدل 60 ثانية ثابتة للجميع. الأدوات التي لا تحدد
  /// قيمة تبقى على الافتراضي 60.
  static Duration timeoutFor(String name) {
    final seconds = _tools[name]?.definition.timeoutSeconds;
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    return const Duration(seconds: 60);
  }
}
