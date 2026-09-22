import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:khwarizmi/features/skills/domain/entities/skill_manifest.dart';

/// يدير دورة حياة العمليات الفرعية المستقلة (Sidecar Processes) الخاصة بالـ Skills.
class SidecarProcessManager {
  static final SidecarProcessManager instance = SidecarProcessManager._();
  SidecarProcessManager._();

  /// العمليات الجارية حالياً مفهرسة باسم الـ Skill
  final Map<String, Process> _runningProcesses = {};

  /// عدد محاولات إعادة التشغيل التلقائي إثر انهيار غير متوقع (الحد الأقصى: 1)
  final Map<String, int> _crashRetries = {};

  /// المهارات التي تم إيقافها عمداً لمنع تفعيل آلية إعادة التشغيل
  final Set<String> _intentionalStops = {};

  /// رد نداء عند تعطيل الـ Skill تلقائياً بسبب تكرار الانهيار
  void Function(String skillName, String error)? onSkillAutoDisabled;

  /// فحص ما إذا كانت العملية قيد التشغيل حالياً
  bool isRunning(String skillName) => _runningProcesses.containsKey(skillName);

  /// تشغيل الـ Sidecar للـ Skill إذا كان يحتوي على [startCommand]
  Future<bool> startProcess(SkillManifest manifest) async {
    final command = manifest.startCommand?.trim();
    if (command == null || command.isEmpty) {
      debugPrint('[SidecarProcessManager] No start_command for "${manifest.name}". Assuming external endpoint.');
      return true;
    }

    // إذا كانت تعمل مسبقاً، لا نعيد تشغيلها
    if (_runningProcesses.containsKey(manifest.name)) {
      debugPrint('[SidecarProcessManager] "${manifest.name}" is already running.');
      return true;
    }

    _intentionalStops.remove(manifest.name);

    try {
      final parts = _parseCommandLine(command);
      if (parts.isEmpty) {
        throw FormatException('Empty start_command for "${manifest.name}"');
      }

      final executable = parts.first;
      final arguments = parts.length > 1 ? parts.sublist(1) : <String>[];

      debugPrint('[SidecarProcessManager] Launching sidecar for "${manifest.name}": $command in ${manifest.folderPath}');

      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: manifest.folderPath.isNotEmpty ? manifest.folderPath : null,
        runInShell: true,
      );

      _runningProcesses[manifest.name] = process;

      // التقاط المخرجات للتشخيص وتفادي امتلاء المخزن المؤقت (Buffer)
      process.stdout.transform(utf8.decoder).listen(
        (data) => debugPrint('[Sidecar:${manifest.name}:stdout] ${data.trim()}'),
        onError: (err) => debugPrint('[Sidecar:${manifest.name}:stdout:error] $err'),
      );

      process.stderr.transform(utf8.decoder).listen(
        (data) => debugPrint('[Sidecar:${manifest.name}:stderr] ${data.trim()}'),
        onError: (err) => debugPrint('[Sidecar:${manifest.name}:stderr:error] $err'),
      );

      // مراقبة انتهاء أو انهيار العملية
      process.exitCode.then((exitCode) {
        _runningProcesses.remove(manifest.name);
        _handleProcessExit(manifest, exitCode);
      });

      return true;
    } catch (e) {
      debugPrint('[SidecarProcessManager] Failed to start sidecar for "${manifest.name}": $e');
      _runningProcesses.remove(manifest.name);
      return false;
    }
  }

  /// إيقاف العملية الفرعية عمداً وبشكل نظيف
  Future<void> stopProcess(String skillName) async {
    _intentionalStops.add(skillName);
    _crashRetries.remove(skillName);

    final process = _runningProcesses.remove(skillName);
    if (process != null) {
      debugPrint('[SidecarProcessManager] Stopping sidecar for "$skillName"...');
      try {
        process.kill(ProcessSignal.sigterm);
        // ننتظر برهة قصيرة ثم نتحقق من الإنهاء
        await process.exitCode.timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () {
            debugPrint('[SidecarProcessManager] Force killing sidecar for "$skillName"...');
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (e) {
        debugPrint('[SidecarProcessManager] Error stopping process for "$skillName": $e');
      }
    }
  }

  /// إيقاف جميع العمليات الجارية (يُستدعى عند إغلاق التطبيق)
  Future<void> stopAll() async {
    final names = _runningProcesses.keys.toList();
    for (final name in names) {
      await stopProcess(name);
    }
    _runningProcesses.clear();
    _crashRetries.clear();
    _intentionalStops.clear();
  }

  /// معالجة خروج العملية والتعامل مع الانهيارات غير المتوقعة
  void _handleProcessExit(SkillManifest manifest, int exitCode) {
    debugPrint('[SidecarProcessManager] Sidecar "${manifest.name}" exited with code $exitCode');

    // إذا كان الإيقاف متعمداً من قبل المستخدم أو النظام، نتجاهل
    if (_intentionalStops.contains(manifest.name)) {
      _intentionalStops.remove(manifest.name);
      return;
    }

    // خروج غير متوقع: التحقق من عدد المحاولات
    final currentRetries = _crashRetries[manifest.name] ?? 0;
    if (currentRetries < 1) {
      _crashRetries[manifest.name] = currentRetries + 1;
      debugPrint(
        '[SidecarProcessManager] "${manifest.name}" crashed unexpectedly (exit $exitCode). Retrying once in 1.5s...',
      );
      Timer(const Duration(milliseconds: 1500), () async {
        final restarted = await startProcess(manifest);
        if (!restarted) {
          _disableCrashedSkill(manifest, exitCode);
        }
      });
    } else {
      // الانهيار تكرر للمرة الثانية: تعطيل فوري
      _disableCrashedSkill(manifest, exitCode);
    }
  }

  void _disableCrashedSkill(SkillManifest manifest, int exitCode) {
    debugPrint('[SidecarProcessManager] "${manifest.name}" crashed repeatedly. Disabling skill permanently.');
    _crashRetries.remove(manifest.name);
    final errorMsg = 'انهارت العملية الفرعية مرتين متتاليتين (رمز الخروج: $exitCode). تم تعطيل الأداة تلقائياً للحفاظ على استقرار النظام.';
    onSkillAutoDisabled?.call(manifest.name, errorMsg);
  }

  /// تقسيم سطر الأوامر مع مراعاة علامات الاقتباس
  static List<String> _parseCommandLine(String commandLine) {
    final List<String> args = [];
    final StringBuffer current = StringBuffer();
    bool inSingleQuote = false;
    bool inDoubleQuote = false;

    for (int i = 0; i < commandLine.length; i++) {
      final char = commandLine[i];
      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
      } else if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
      } else if (char == ' ' && !inSingleQuote && !inDoubleQuote) {
        if (current.isNotEmpty) {
          args.add(current.toString());
          current.clear();
        }
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) {
      args.add(current.toString());
    }
    return args;
  }
}
