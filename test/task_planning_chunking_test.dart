import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/features/agent/data/task_database.dart';
import 'package:khwarizmi/features/agent/data/task_plan_database.dart';
import 'package:khwarizmi/features/agent/domain/entities/task_plan.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_plan_test_');
    testDbPath = '${tempDir.path}/test_plan.db';
    await MemoryDatabase.initialize(customPath: testDbPath);
    await TaskDatabase.initialize();
    await TaskPlanDatabase.initialize();
  });

  tearDownAll(() async {
    MemoryDatabase.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Planning & Chunking Entity Tests', () {
    test('SubTask serialization & copyWith work correctly', () {
      final now = DateTime.now();
      final subTask = SubTask(
        id: 'sub_1',
        index: 0,
        description: 'إنشاء ملف الإعدادات الأساسي',
        status: SubTaskStatus.pending,
        retryCount: 0,
        maxRetries: 3,
      );

      expect(subTask.canExecute, isTrue);
      expect(subTask.isExhausted, isFalse);

      final running = subTask.copyWith(
        status: SubTaskStatus.inProgress,
        startedAt: now,
      );
      expect(running.status, equals(SubTaskStatus.inProgress));
      expect(running.startedAt, equals(now));

      final failed = running.copyWith(
        retryCount: 3,
        status: SubTaskStatus.failed,
        errorMessage: 'Connection timeout',
      );
      expect(failed.isExhausted, isTrue);
      expect(failed.errorMessage, equals('Connection timeout'));

      final json = failed.toJson();
      final restored = SubTask.fromJson(json);
      expect(restored.id, equals('sub_1'));
      expect(restored.description, equals('إنشاء ملف الإعدادات الأساسي'));
      expect(restored.status, equals(SubTaskStatus.failed));
      expect(restored.retryCount, equals(3));
      expect(restored.errorMessage, equals('Connection timeout'));
    });

    test('TaskPlan progress tracking & state calculation', () {
      final subTasks = [
        SubTask(
          id: '1',
          index: 0,
          description: 'خطوة 1',
          status: SubTaskStatus.completed,
          result: 'تم بنجاح',
        ),
        SubTask(
          id: '2',
          index: 1,
          description: 'خطوة 2',
          status: SubTaskStatus.inProgress,
        ),
        SubTask(
          id: '3',
          index: 2,
          description: 'خطوة 3',
          status: SubTaskStatus.pending,
        ),
      ];

      final plan = TaskPlan(
        taskId: 'task_abc',
        goal: 'بناء تطبيق كامل',
        taskList: subTasks,
        createdAt: DateTime.now(),
        planSummary: 'خطة من ثلاث خطوات',
      );

      expect(plan.isFullyCompleted, isFalse);
      expect(plan.hasFailedTask, isFalse);
      expect(plan.completedCount, equals(1));
      expect(plan.nextPendingTask?.id, equals('2'));
      expect(plan.completionRatio, closeTo(1 / 3, 0.01));

      final allDone = plan.copyWith(
        taskList: subTasks
            .map((s) => s.copyWith(status: SubTaskStatus.completed))
            .toList(),
      );
      expect(allDone.isFullyCompleted, isTrue);
      expect(allDone.completionRatio, equals(1.0));
      expect(allDone.nextPendingTask, isNull);
    });
  });

  group('TaskPlanDatabase Persistence Tests', () {
    test('upsertPlan, updateTaskList and getPlanByTaskId persist checkpoints', () async {
      final taskId = 'task_persist_1';
      final plan = TaskPlan(
        taskId: taskId,
        goal: 'مهمة تحليل البيانات',
        taskList: [
          SubTask(id: 's1', index: 0, description: 'جمع البيانات'),
          SubTask(id: 's2', index: 1, description: 'تنظيف البيانات'),
          SubTask(id: 's3', index: 2, description: 'استخراج النتائج'),
        ],
        createdAt: DateTime.now(),
        planSummary: 'خطة تحليل ثلاثية',
      );

      // حفظ الخطة المبدئية
      await TaskPlanDatabase.upsertPlan(plan);

      // استرجاع الخطة والتحقق
      final fetched = await TaskPlanDatabase.getPlanByTaskId(taskId);
      expect(fetched, isNotNull);
      expect(fetched!.taskId, equals(taskId));
      expect(fetched.goal, equals('مهمة تحليل البيانات'));
      expect(fetched.taskList.length, equals(3));
      expect(fetched.taskList[0].description, equals('جمع البيانات'));
      expect(fetched.taskList[0].status, equals(SubTaskStatus.pending));

      // تحديث حالة خطوة وتخزين الـ Checkpoint
      final updatedPlan = fetched.updateSubTask(
        0,
        fetched.taskList[0].copyWith(
          status: SubTaskStatus.completed,
          result: 'تم جمع 100 سجل بنجاح',
        ),
      );
      await TaskPlanDatabase.updateTaskList(taskId, updatedPlan);

      // قراءة الـ Checkpoint
      final checkpointFetched = await TaskPlanDatabase.getPlanByTaskId(taskId);
      expect(checkpointFetched, isNotNull);
      expect(checkpointFetched!.taskList[0].status, equals(SubTaskStatus.completed));
      expect(checkpointFetched.taskList[0].result, equals('تم جمع 100 سجل بنجاح'));
      expect(checkpointFetched.taskList[1].status, equals(SubTaskStatus.pending));

      // حذف الخطة
      await TaskPlanDatabase.deletePlan(taskId);
      final afterDelete = await TaskPlanDatabase.getPlanByTaskId(taskId);
      expect(afterDelete, isNull);
    });
  });
}
