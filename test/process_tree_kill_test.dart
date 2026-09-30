import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/core/utils/process_utils.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/projects/data/project_database.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';
import 'package:khwarizmi/features/skills/services/sidecar_process_manager.dart';
import 'package:khwarizmi/features/tools/domain/tool_cancellation_token.dart';
import 'package:path/path.dart' as p;

/// يولّد سكربت "كاتب": عملية powershell تُلحق 'tick' بالملف كل 400ms
/// لمدة ~60 ثانية. مراقبة توقف اللكات تكشف بقاء عملية يتيمة بعد القتل.
String _writerCmdContent(String markerAbsPath) =>
    '@echo off\r\n'
    'powershell -NoProfile -Command "for(\$i=0;\$i -lt 150;\$i++){Add-Content -LiteralPath \'$markerAbsPath\' -Value \'tick\';Start-Sleep -Milliseconds 400}"\r\n';

Future<int> _tickCount(File marker) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (!await marker.exists()) return 0;
      final lines = await marker.readAsLines();
      return lines.where((l) => l.trim() == 'tick').length;
    } on FileSystemException {
      // الملف قد يكون محتجزاً للحظة أثناء كتابة سطر جديد
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
  return 0;
}

Future<bool> _waitForTicks(
  File marker,
  int minTicks, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    if (await _tickCount(marker) >= minTicks) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File marker;
  late String writerCmdPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khwarizmi_tree_kill_');
    marker = File(p.join(tempDir.path, 'ticks.log'));
    writerCmdPath = p.join(tempDir.path, 'writer.cmd');
    await File(writerCmdPath).writeAsString(_writerCmdContent(marker.path));
  });

  tearDown(() async {
    // تنظيف متسامح: قد تبقى مقابض العمليات محتجزة للحظة بعد القتل
    for (var attempt = 0; attempt < 15; attempt++) {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  });

  test('Fix 09: killProcessTree terminates the whole descendant chain (no orphans)', () async {
    // runInShell:true يخلق سلسلة: cmd(غلاف) → cmd(writer) → powershell(tick).
    final process = await Process.start(writerCmdPath, [], runInShell: true);

    expect(
      await _waitForTicks(marker, 2),
      isTrue,
      reason: 'سلسلة الكاتب يجب أن تبدأ الكتابة قبل القتل',
    );

    await killProcessTree(process);
    await process.exitCode.timeout(const Duration(seconds: 10));

    // نمنح أي "يتيم" متبقٍ فرصة ظاهرة ثم نتأكد أن اللكات توقفت نهائياً.
    await Future<void>.delayed(const Duration(seconds: 2));
    final countA = await _tickCount(marker);
    await Future<void>.delayed(const Duration(seconds: 3));
    final countB = await _tickCount(marker);

    expect(countA, greaterThan(0));
    expect(
      countB,
      equals(countA),
      reason:
          'إصلاح 09: قتل الشجرة يجب أن يمنع بقاء عمليات أبناء يتيمة '
          'تستمر بالكتابة في الخلفية',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('Fix 09 via ProjectManager: cancelling a running command kills its child chain too', () async {
    final dbPath = p.join(tempDir.path, 'tree_pm.db');
    await MemoryDatabase.initialize(customPath: dbPath);
    await ProjectDatabase.initialize();
    await ProjectManager.instance.openProject(tempDir.path);

    final token = ToolCancellationToken();
    // السلسلة: powershell(ProjectManager) → cmd(writer) → powershell(tick)
    final future = ProjectManager.instance.runTerminalCommand(
      "& '$writerCmdPath'",
      cancellationToken: token,
    );

    expect(
      await _waitForTicks(marker, 2),
      isTrue,
      reason: 'الكاتب الابن يجب أن يبدأ قبل الإلغاء',
    );

    token.cancel('إيقاف المستخدم');

    final raw = await future.timeout(const Duration(seconds: 20));
    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['cancelled'], isTrue);

    await Future<void>.delayed(const Duration(seconds: 2));
    final countA = await _tickCount(marker);
    await Future<void>.delayed(const Duration(seconds: 3));
    final countB = await _tickCount(marker);

    expect(
      countB,
      equals(countA),
      reason:
          'إصلاح 09 عبر ProjectManager: إلغاء الأمر يجب أن يقتل '
          'العمليات الأبناء (writer) لا أن يتركها يتيمة تعمل',
    );

    MemoryDatabase.close();
    ProjectManager.instance.closeProject();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
    'Fix 09 in Sidecar: stopProcess kills the actual server process tree',
    () async {
      final manager = SidecarProcessManager.instance;
      // runInShell:true → السلسلة: cmd(غلاف) → cmd(writer) → powershell(tick)
      final manifest = SkillManifest(
        name: 'tree_kill_skill',
        displayName: 'اختبار قتل الشجرة',
        description: 'skill وهمي لاختبار إيقاف شجرة العمليات',
        endpoint: 'http://localhost:59999/api',
        inputSchema: const {'type': 'object'},
        folderPath: tempDir.path,
        startCommand: '"$writerCmdPath"',
      );

      final started = await manager.startProcess(manifest);
      expect(started, isTrue);
      expect(manager.isRunning('tree_kill_skill'), isTrue);

      expect(
        await _waitForTicks(marker, 2),
        isTrue,
        reason: 'الخادم الفرعي (writer) يجب أن يعمل قبل الإيقاف',
      );

      await manager.stopProcess('tree_kill_skill');
      expect(manager.isRunning('tree_kill_skill'), isFalse);

      await Future<void>.delayed(const Duration(seconds: 2));
      final countA = await _tickCount(marker);
      await Future<void>.delayed(const Duration(seconds: 3));
      final countB = await _tickCount(marker);

      expect(
        countB,
        equals(countA),
        reason:
            'إصلاح 09 في Sidecar: stopProcess يجب أن يقتل الخادم الفعلي '
            'المستضاف داخل سلسلة shell لا أن يتركه يتيماً',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
