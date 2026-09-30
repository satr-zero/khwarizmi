import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/memory/data/memory_database.dart';
import 'package:khwarizmi/features/projects/data/project_database.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';
import 'package:khwarizmi/features/tools/domain/tool_cancellation_token.dart';
import 'package:khwarizmi/features/tools/tool_registry.dart';

/// أداة زائفة "طويلة" تنتظر إلغاء رمزها المسجل في السجل ثم ترمي
/// [ToolCancelledException] — تحاكي أداة قابلة للإلغاء عبر
/// [ToolRegistry.activeTokenFor] (نفس نمط run_terminal_command).
class _FakeLongTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'fake_long_test_tool',
    description: 'أداة اختبار: تنتظر الإلغاء ثم ترمي استثناء الإلغاء.',
    parameters: {'type': 'OBJECT', 'properties': {}},
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final token = ToolRegistry.activeTokenFor('fake_long_test_tool');
    if (token == null) {
      return '{"error": "no active token"}';
    }
    final reason = await token.whenCancelled;
    throw ToolCancelledException(reason);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fix 10: ToolCancellationToken unit behavior', () {
    test('cancel runs registered handlers exactly once with the reason', () {
      final token = ToolCancellationToken();
      var calls = 0;
      late String receivedReason;
      token.onCancel((reason) {
        calls++;
        receivedReason = reason;
      });

      token.cancel('stop-request');
      token.cancel('second-call-ignored');

      expect(token.isCancelled, isTrue);
      expect(calls, 1, reason: 'المعالجات يجب أن تعمل مرة واحدة فقط');
      expect(receivedReason, 'stop-request');
      expect(token.reason, 'stop-request');
    });

    test('onCancel registered after cancellation runs immediately', () {
      final token = ToolCancellationToken();
      token.cancel('already-stopped');

      var ran = false;
      token.onCancel((reason) => ran = true);

      expect(ran, isTrue, reason: 'التسجيل على رمز ملغى يجب أن يُنفَّذ فوراً');
    });

    test('whenCancelled completes with reason on cancel', () async {
      final token = ToolCancellationToken();
      final reasonFuture = token.whenCancelled;
      expect(token.isCancelled, isFalse);

      Future<void>.delayed(const Duration(milliseconds: 20), () {
        token.cancel('user-stop');
      });

      final reason = await reasonFuture;
      expect(reason, 'user-stop');
    });

    test('throwIfCancelled throws only after cancel', () {
      final token = ToolCancellationToken();
      expect(() => token.throwIfCancelled(), returnsNormally);

      token.cancel();
      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<ToolCancelledException>()),
      );
    });

    test(
      'handler exceptions inside cancel are swallowed and do not block others',
      () {
        final token = ToolCancellationToken();
        var secondRan = false;
        token.onCancel((_) => throw StateError('boom'));
        token.onCancel((_) => secondRan = true);

        token.cancel('x');

        expect(
          secondRan,
          isTrue,
          reason: 'فشل معالج لا يجب أن يمنع تنفيذ بقية المعالجات',
        );
      },
    );
  });

  group('Fix 10: ToolRegistry cancellation support', () {
    tearDown(() {
      ToolRegistry.clear();
    });

    test(
      'executeTool registers token during run and cleans it up after',
      () async {
        ToolRegistry.clear();
        ToolRegistry.registerTool(_FakeLongTool());

        final future = ToolRegistry.executeTool('fake_long_test_tool', {});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // أثناء التنفيذ: الرمز مسجل وقابل للوصول
        expect(ToolRegistry.activeTokenFor('fake_long_test_tool'), isNotNull);

        ToolRegistry.cancelActiveTools('stop');
        final result = jsonDecode(await future) as Map<String, dynamic>;

        expect(result['cancelled'], isTrue);
        expect(result['reason'], 'stop');
        // بعد انتهاء التنفيذ: الرمز يُزال من السجل
        expect(ToolRegistry.activeTokenFor('fake_long_test_tool'), isNull);
      },
    );

    test(
      'cancelActiveTools returns the number of in-flight executions',
      () async {
        ToolRegistry.clear();
        ToolRegistry.registerTool(_FakeLongTool());

        expect(
          ToolRegistry.cancelActiveTools(),
          equals(0),
          reason: 'لا تنفيذات جارية',
        );

        final future = ToolRegistry.executeTool('fake_long_test_tool', {});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(ToolRegistry.cancelActiveTools('user-stop'), equals(1));
        final result = jsonDecode(await future) as Map<String, dynamic>;
        expect(result['cancelled'], isTrue);
      },
    );
  });

  group(
    'Fix 10: ProjectManager.runTerminalCommand cancellation (real process)',
    () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'khwarizmi_cancel_test_',
        );
        final dbPath = p.join(tempDir.path, 'cancel_test.db');
        await MemoryDatabase.initialize(customPath: dbPath);
        await ProjectDatabase.initialize();
        await ProjectManager.instance.openProject(tempDir.path);
      });

      tearDown(() async {
        MemoryDatabase.close();
        ProjectManager.instance.closeProject();
        // على ويندوز قد تبقى مقابض عملية قيد الإطفاء محتجزة للمجلد للحظة —
        // نعيد محاولة الحذف بدل الفشل الفوري.
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

      test('cancelling the token kills the running command instead of waiting it out', () async {
        final token = ToolCancellationToken();

        // Start-Sleep يعمل داخل عملية PowerShell نفسها (cmdlet بلا عملية
        // ابنة) — قتله يقتل الأمر كاملاً في نطاق إصلاح 10. (قتل شجرة
        // العمليات للأوامر ذات عمليات أبناء هو نطاق إصلاح 09 لاحقاً.)
        final stopwatch = Stopwatch()..start();
        final future = ProjectManager.instance.runTerminalCommand(
          'Start-Sleep -Seconds 30',
          cancellationToken: token,
        );

        // نمنح الأمر فرصة البدء فعلياً ثم نلغي — كما يفعل زر الإيقاف.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        token.cancel('تم الإيقاف بواسطة المستخدم');

        final raw = await future.timeout(const Duration(seconds: 15));
        stopwatch.stop();

        final result = jsonDecode(raw) as Map<String, dynamic>;
        expect(
          result['cancelled'],
          isTrue,
          reason: 'النتيجة يجب أن تحمل علامة إلغاء صريحة',
        );
        expect(result['reason'], 'تم الإيقاف بواسطة المستخدم');
        expect(
          stopwatch.elapsed.inSeconds,
          lessThan(10),
          reason:
              'الأمر (~30 ثانية) يجب أن يُقطع فوراً لا أن يُنتظر حتى النهاية',
        );
      }, timeout: const Timeout(Duration(seconds: 60)));

      test(
        'an already-cancelled token prevents the command from starting at all',
        () async {
          final token = ToolCancellationToken();
          token.cancel('إلغاء مبكر');

          final raw = await ProjectManager.instance.runTerminalCommand(
            'ping -n 2 127.0.0.1',
            cancellationToken: token,
          );

          final result = jsonDecode(raw) as Map<String, dynamic>;
          expect(result['cancelled'], isTrue);
          expect(
            result.containsKey('exit_code'),
            isFalse,
            reason: 'يجب ألا تبدأ العملية أصلاً فلا يوجد exit_code',
          );
        },
      );

      test(
        'without a token the command still runs to completion normally',
        () async {
          final raw = await ProjectManager.instance.runTerminalCommand(
            'ping -n 2 127.0.0.1',
          );
          final result = jsonDecode(raw) as Map<String, dynamic>;

          expect(result.containsKey('cancelled'), isFalse);
          expect(result['exit_code'], 0);
          expect(result['success'], isTrue);
        },
      );

      test('Fix 18: huge line count gets capped to the last 200 lines with an explicit notice', () async {
        // 500 سطر مميز L001..L500 — أكبر من سقف 200 سطر بكثير
        final raw = await ProjectManager.instance.runTerminalCommand(
          '1..500 | ForEach-Object { "L" + \$_.ToString("000") }',
        );
        final result = jsonDecode(raw) as Map<String, dynamic>;
        final out = result['output'] as String;

        expect(
          out,
          contains('اختُصر'),
          reason: 'إصلاح 18: يجب أن يتضمن الناتج إشعار اختصار صريحاً',
        );
        expect(out, contains('L500'), reason: 'آخر سطر يجب أن يبقى محفوظاً');
        expect(
          out,
          isNot(contains('L001')),
          reason: 'الأسطر الأولى خارج آخر 200 يجب أن تُحذف',
        );
        final keptLines = out
            .split('\n')
            .where((l) => l.startsWith('L'))
            .length;
        expect(keptLines, lessThanOrEqualTo(200));
      });

      test('Fix 18: byte cap trims from the top even when line count is near the cap', () async {
        // 220 سطراً × ~254 حرفاً ≈ 56KB — فوق سقف 50KB رغم قرب عدد الأسطر
        final raw = await ProjectManager.instance.runTerminalCommand(
          '1..220 | ForEach-Object { "L" + \$_.ToString("000") + ("x" * 250) }',
        );
        final result = jsonDecode(raw) as Map<String, dynamic>;
        final out = result['output'] as String;

        expect(out, contains('اختُصر'));
        expect(out, contains('L220'));
        expect(
          out.length,
          lessThan(60 * 1024),
          reason: 'الناتج النهائي يجب أن يبقى قريباً من حد 50KB',
        );
      });
    },
  );

  group('Fix 06: dynamic per-tool timeout', () {
    tearDown(() {
      ToolRegistry.clear();
    });

    test('timeoutFor defaults to 60s when the tool defines no override', () {
      ToolRegistry.clear();
      ToolRegistry.registerTool(_FakeLongTool());
      expect(
        ToolRegistry.timeoutFor('fake_long_test_tool'),
        const Duration(seconds: 60),
      );
      // أداة غير مسجلة أصلاً → الافتراضي أيضاً
      expect(
        ToolRegistry.timeoutFor('unregistered_tool'),
        const Duration(seconds: 60),
      );
    });

    test('timeoutFor returns the tool-defined timeoutSeconds override', () {
      ToolRegistry.clear();
      ToolRegistry.registerTool(_TimedFakeTool());
      expect(
        ToolRegistry.timeoutFor('timed_fake_tool'),
        const Duration(seconds: 150),
      );
    });

    test(
      'run_terminal_command timeout covers its internal 120s command budget',
      () {
        ToolRegistry.clear();
        ToolRegistry.initialize();
        expect(
          ToolRegistry.timeoutFor('run_terminal_command'),
          const Duration(seconds: 150),
          reason: 'إصلاح 06: مهلة الأداة يجب أن تتسع للمهلة الداخلية (120ث)',
        );
        ToolRegistry.clear();
      },
    );

    test(
      'outer timeout cancels the in-flight execution via its token',
      () async {
        ToolRegistry.clear();
        ToolRegistry.registerTool(_FakeLongTool());

        final future = ToolRegistry.executeTool('fake_long_test_tool', {});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // المحاكاة: انتهاء المهلة الخارجية → onTimeout يستدعي
        // cancelToolExecution — يجب أن يلغي الرمز الجاري فعلياً.
        final stillRunning = ToolRegistry.activeTokenFor('fake_long_test_tool');
        expect(stillRunning, isNotNull);
        ToolRegistry.cancelToolExecution(
          'fake_long_test_tool',
          'انتهت مهلة الأداة',
        );

        final result = jsonDecode(await future) as Map<String, dynamic>;
        expect(
          result['cancelled'],
          isTrue,
          reason: 'إصلاح 06: انتهاء المهلة يجب أن يلغي التنفيذ فعلياً',
        );
        expect(result['reason'], 'انتهت مهلة الأداة');
      },
    );

    test('cancelToolExecution on a non-running tool is a harmless no-op', () {
      ToolRegistry.clear();
      expect(
        () => ToolRegistry.cancelToolExecution('nothing_running', 'x'),
        returnsNormally,
      );
    });
  });
}

/// أداة زائفة تحدد مهلتها الخاصة — للتحقق من timeoutSeconds الديناميكية.
class _TimedFakeTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'timed_fake_tool',
    description: 'أداة اختبار بمهلة 150 ثانية.',
    parameters: {'type': 'OBJECT', 'properties': {}},
    timeoutSeconds: 150,
  );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    return '{"ok": true}';
  }
}
