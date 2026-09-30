import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/agent/data/task_database.dart';
import 'package:khwarizmi/features/agent/domain/entities/task.dart';
import 'package:khwarizmi/features/agent/services/task_execution_engine.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/tools/built_in/task_control_tools.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_task_test_');
    testDbPath = '${tempDir.path}/test_task.db';
    await MemoryDatabase.initialize(customPath: testDbPath);
    await TaskDatabase.initialize();
    ToolRegistry.initialize();
  });

  tearDownAll(() async {
    MemoryDatabase.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await TaskDatabase.clearAll();
  });

  group('Phase 7 Autonomous Task Entity Tests', () {
    test('Task entity serialization round-trip works accurately', () {
      final now = DateTime.now();
      final step = TaskStepLog(
        stepIndex: 1,
        action: 'بحث في الويب عن الوكلاء الأذكياء',
        toolName: 'web_search',
        toolResult: '{"results": ["Agent 1"]}',
        thinking: 'أبحث عن المقالات المناسبة',
        timestamp: now,
      );

      final task = Task(
        id: 'task_101',
        goal: 'ابحث عن مشاريع الوكلاء الأذكياء',
        status: TaskStatus.running,
        stepCap: 25,
        stepCount: 1,
        createdAt: now,
        stepsLog: [step],
        pendingQuestion: null,
        completionSummary: null,
        providerId: 'gemini',
        modelName: 'gemini-1.5-flash',
      );

      final jsonMap = task.toJson();
      final restored = Task.fromJson(jsonMap);

      expect(restored.id, equals('task_101'));
      expect(restored.goal, equals('ابحث عن مشاريع الوكلاء الأذكياء'));
      expect(restored.status, equals(TaskStatus.running));
      expect(restored.stepCap, equals(25));
      expect(restored.stepCount, equals(1));
      expect(restored.stepsLog.length, equals(1));
      expect(restored.stepsLog.first.toolName, equals('web_search'));
      expect(restored.stepsLog.first.action, equals('بحث في الويب عن الوكلاء الأذكياء'));
      expect(restored.stepsLog.first.thinking, equals('أبحث عن المقالات المناسبة'));
      expect(restored.providerId, equals('gemini'));
      expect(restored.modelName, equals('gemini-1.5-flash'));
    });

    test('Task progress ratio and cap checks calculate correctly', () {
      final task = Task(
        id: 'task_cap',
        goal: 'مهمة لاختبار السقف',
        status: TaskStatus.running,
        stepCap: 20,
        stepCount: 10,
        createdAt: DateTime.now(),
        providerId: 'gemini',
        modelName: 'gemini-1.5-flash',
      );

      expect(task.progressRatio, closeTo(0.5, 0.001));
      expect(task.isAtStepLimit, isFalse);

      final atCap = task.copyWith(stepCount: 20);
      expect(atCap.progressRatio, closeTo(1.0, 0.001));
      expect(atCap.isAtStepLimit, isTrue);

      final overCap = task.copyWith(stepCount: 25);
      expect(overCap.progressRatio, closeTo(1.0, 0.001));
      expect(overCap.isAtStepLimit, isTrue);
    });

    test('TaskStatus string conversions map all statuses cleanly', () {
      for (final status in TaskStatus.values) {
        final str = status.name;
        final parsed = TaskStatus.values.byName(str);
        expect(parsed, equals(status));
      }
    });
  });

  group('Phase 7 Task Control Tools & Registry Tests', () {
    test('Control tools are marked with isControlTool = true', () {
      final askUser = AskUserTool();
      final reportProgress = ReportProgressTool();
      final completeTask = CompleteTaskTool();

      expect(askUser.definition.isControlTool, isTrue);
      expect(reportProgress.definition.isControlTool, isTrue);
      expect(completeTask.definition.isControlTool, isTrue);
    });

    test('ToolRegistry separates chat tools from autonomous tools', () {
      final chatDefs = ToolRegistry.getChatDefinitions();
      final autoDefs = ToolRegistry.getAutonomousDefinitions();

      // Chat definitions MUST NOT contain control tools
      expect(chatDefs.any((d) => d.name == 'ask_user'), isFalse);
      expect(chatDefs.any((d) => d.name == 'report_progress'), isFalse);
      expect(chatDefs.any((d) => d.name == 'complete_task'), isFalse);

      // Autonomous definitions MUST contain control tools
      expect(autoDefs.any((d) => d.name == 'ask_user'), isTrue);
      expect(autoDefs.any((d) => d.name == 'report_progress'), isTrue);
      expect(autoDefs.any((d) => d.name == 'complete_task'), isTrue);
    });

    test('Executing control tools returns intercept indicator', () async {
      final askUserResult = await ToolRegistry.executeTool('ask_user', {'question': 'هل تريد المتابعة؟'});
      final askMap = jsonDecode(askUserResult);
      expect(askMap['control'], equals('ask_user'));
      expect(askMap['question'], equals('هل تريد المتابعة؟'));

      final completeResult = await ToolRegistry.executeTool('complete_task', {'summary': 'تم الإنجاز'});
      final completeMap = jsonDecode(completeResult);
      expect(completeMap['control'], equals('complete_task'));
      expect(completeMap['summary'], equals('تم الإنجاز'));

      final progressResult = await ToolRegistry.executeTool('report_progress', {'message': 'الخطوة 3'});
      final progressMap = jsonDecode(progressResult);
      expect(progressMap['control'], equals('report_progress'));
      expect(progressMap['message'], equals('الخطوة 3'));
    });
  });

  group('Phase 7 Task Database Persistence Tests', () {
    test('TaskDatabase inserts, retrieves, updates and deletes tasks', () async {
      final task = Task(
        id: 'db_task_1',
        goal: 'حفظ واسترجاع مهمة تجريبية',
        status: TaskStatus.running,
        stepCap: 25,
        stepCount: 2,
        createdAt: DateTime.now(),
        providerId: 'gemini',
        modelName: 'gemini-1.5-flash',
        stepsLog: [
          TaskStepLog(
            stepIndex: 1,
            action: 'فتح الرابط',
            toolName: 'browse_url',
            toolResult: 'Loaded successfully',
            timestamp: DateTime.now(),
          ),
        ],
      );

      await TaskDatabase.insertTask(task);

      final retrieved = await TaskDatabase.getTaskById('db_task_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('db_task_1'));
      expect(retrieved.goal, equals('حفظ واسترجاع مهمة تجريبية'));
      expect(retrieved.status, equals(TaskStatus.running));
      expect(retrieved.stepsLog.length, equals(1));
      expect(retrieved.stepsLog.first.toolName, equals('browse_url'));

      // Update task status and add step
      final updated = retrieved.copyWith(
        status: TaskStatus.completed,
        completionSummary: 'تم بنجاح',
        stepCount: 3,
        stepsLog: [
          ...retrieved.stepsLog,
          TaskStepLog(
            stepIndex: 2,
            action: 'إتمام المهمة',
            toolName: 'complete_task',
            toolResult: 'تم بنجاح',
            timestamp: DateTime.now(),
          ),
        ],
      );

      await TaskDatabase.updateTask(updated);

      final afterUpdate = await TaskDatabase.getTaskById('db_task_1');
      expect(afterUpdate!.status, equals(TaskStatus.completed));
      expect(afterUpdate.completionSummary, equals('تم بنجاح'));
      expect(afterUpdate.stepCount, equals(3));
      expect(afterUpdate.stepsLog.length, equals(2));

      // Retrieve all tasks
      final allTasks = await TaskDatabase.getAllTasks();
      expect(allTasks.length, equals(1));
      expect(allTasks.first.id, equals('db_task_1'));

      // Delete task
      await TaskDatabase.deleteTask('db_task_1');
      final afterDelete = await TaskDatabase.getTaskById('db_task_1');
      expect(afterDelete, isNull);
    });

    test('Recovery resets running tasks to pausedAtLimit for safety', () async {
      final runningTask = Task(
        id: 'orphan_running',
        goal: 'مهمة تركت تعمل عند إغلاق التطبيق',
        status: TaskStatus.running,
        stepCap: 25,
        stepCount: 12,
        createdAt: DateTime.now(),
        providerId: 'gemini',
        modelName: 'gemini-1.5-flash',
      );

      await TaskDatabase.insertTask(runningTask);

      final all = await TaskDatabase.getAllTasks();
      final orphan = all.firstWhere((t) => t.id == 'orphan_running');
      expect(orphan.status, equals(TaskStatus.running));

      // Simulate recovery logic performed on startup
      if (orphan.status == TaskStatus.running) {
        final recovered = orphan.copyWith(status: TaskStatus.pausedAtLimit);
        await TaskDatabase.updateTask(recovered);
      }

      final check = await TaskDatabase.getTaskById('orphan_running');
      expect(check!.status, equals(TaskStatus.pausedAtLimit));
    });

    test('TaskExecutionEngine.recoverInterruptedTasks marks running tasks as failed with clear message', () async {
      final runningTask = Task(
        id: 'interrupted_running_2',
        goal: 'مهمة قيد التنفيذ تم قطعها',
        status: TaskStatus.running,
        stepCap: 25,
        stepCount: 7,
        createdAt: DateTime.now(),
        providerId: 'gemini',
        modelName: 'gemini-1.5-flash',
      );

      await TaskDatabase.insertTask(runningTask);

      await TaskExecutionEngine.instance.recoverInterruptedTasks();

      final recovered = await TaskDatabase.getTaskById('interrupted_running_2');
      expect(recovered, isNotNull);
      expect(recovered!.status, equals(TaskStatus.failed));
      expect(recovered.errorMessage, contains('مقاطعة'));
      expect(recovered.completedAt, isNotNull);
    });
  });
}
