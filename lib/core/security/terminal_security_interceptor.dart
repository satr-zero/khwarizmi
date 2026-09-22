/// Programmatic Safety Barrier for Terminal Commands — Phase 9.
///
/// CRITICAL ARCHITECTURAL NOTE:
/// This class enforces a code-level defense-in-depth safety barrier against
/// destructive or irreversible terminal commands. Every command passes through
/// this interceptor BEFORE any Process.start() call.
///
/// LIMITATION NOTICE:
/// This detection is heuristic and precautionary; it reliably intercepts
/// known destructive patterns (mass deletion, dangerous git operations, system
/// commands) but CANNOT guarantee detection of every conceivable destructive
/// command or obfuscated variant. This is documented intentionally.
/// Users should always verify terminal output critically.
///
/// SECURITY PRINCIPLE:
/// When in doubt → requiresConfirmation. Err on the side of caution.
library;

/// نتيجة فحص أمان الأمر.
sealed class InterceptionResult {
  const InterceptionResult();
}

/// الأمر آمن للتنفيذ الفوري.
class SafeCommand extends InterceptionResult {
  const SafeCommand();
}

/// الأمر يحتاج تأكيد صريح من المستخدم قبل التنفيذ.
class RequiresConfirmation extends InterceptionResult {
  final String reason;
  final String category;
  const RequiresConfirmation({required this.reason, required this.category});
}

/// الأمر مرفوض فورياً (محاولة الوصول خارج مجلد المشروع).
class RejectedCommand extends InterceptionResult {
  final String reason;
  const RejectedCommand({required this.reason});
}

/// حاجز أمان أوامر الترمينال — المرحلة 9.
class TerminalSecurityInterceptor {
  TerminalSecurityInterceptor._();

  // ── أنماط الحذف الجماعي ───────────────────────────────────────────────────

  /// أنماط PowerShell/CMD تحذف بشكل جماعي / لا رجعة فيه.
  static const List<String> _massDeletePatterns = [
    r'rm\s+-rf',         // Unix/bash (WSL)
    r'rm\s+.*-rf',
    r'rm\s+.*--force',
    r'del\s+/s',         // CMD del /s
    r'del\s+/q',
    r'rmdir\s+/s',       // CMD rmdir /s
    r'Remove-Item.*-Recurse.*-Force', // PowerShell
    r'Remove-Item.*-Force.*-Recurse',
    r'ri\s+.*-r',        // PowerShell alias
    r'rd\s+/s',
  ];

  // ── أوامر Git الخطيرة ─────────────────────────────────────────────────────

  static const List<String> _dangerousGitPatterns = [
    r'git\s+push\s+.*--force',   // git push --force
    r'git\s+push\s+.*-f\b',      // git push -f
    r'git\s+reset\s+--hard',     // git reset --hard
    r'git\s+clean\s+.*-f',       // git clean -f / -fd / -xfd
    r'git\s+clean\s+.*-x',       // git clean -x / -xfd
  ];

  // ── أوامر النظام الحساسة ──────────────────────────────────────────────────

  static const List<String> _systemSensitivePatterns = [
    r'\bformat\s+[a-zA-Z]:',             // format C: (disk format)
    r'\bdiskpart\b',                      // diskpart
    r'\bmkfs\b',                          // Linux mkfs (WSL)
    // تعديل متغيرات بيئة النظام العامة (Machine scope)
    r'\[System\.Environment\]::SetEnvironmentVariable.*Machine',
    r'setx\s+.*\s+/M\b',                  // setx /M
    // تعديل حسابات المستخدمين
    r'net\s+user\s+\S+\s+\S+',           // net user <name> <action>
    r'Add-LocalGroupMember',
    r'Remove-LocalUser',
  ];

  // ── أنماط تسريب المعلومات الحساسة ────────────────────────────────────────

  static const List<String> _dataExfiltrationPatterns = [
    r'cat\s+.*\.ssh',
    r'type\s+.*\.ssh',
    r'Get-Content.*\.ssh',
    r'env\s*\|.*curl',
    r'printenv\s*\|.*curl',
    r'\$env.*\|.*curl',
  ];

  // ── فحص المسار (Path Containment) ────────────────────────────────────────

  /// يفحص ما إذا كان الأمر يحتوي مسارات مطلقة أو مسارات UNC تخرج عن [projectRootPath].
  static bool _commandContainsPathOutsideRoot(
    String command,
    String projectRootPath,
  ) {
    final normalizedRoot = _normalizePath(projectRootPath);

    // 1) فحص مسارات UNC
    // مسارات Windows UNC: \\server\share
    final uncPattern = RegExp(r'''(^|[\s"'\`;|&])(\\\\[^\s"'\`;|&]+)''');
    if (uncPattern.hasMatch(command)) {
      return true;
    }
    // مسارات UNC بصيغة //server/share (مع استبعاد روابط http:// و https://)
    final forwardUncPattern = RegExp(r'''(^|[\s"'\`;|&])\/\/[a-zA-Z0-9_\.\-]+[/\\][^\s"'\`;|&]+''');
    for (final match in forwardUncPattern.allMatches(command)) {
      final start = match.start;
      if (start > 0 && command[start - 1] == ':') continue; // URL scheme like http://
      return true;
    }

    // 2) فحص path traversal بـ ..
    if (command.contains('..')) {
      final traversalPatterns = [
        RegExp(r'\.\.[/\\]\.\.[/\\]'), // ../../
        RegExp(r'\.\.[/\\][a-zA-Z0-9_]'),  // ../something
        RegExp(r'\.\.[/\\]$'),
        RegExp(r'''(^|[\s"'`])\.\.[/\\]'''), // ../ or ..\ at token start
      ];
      for (final p in traversalPatterns) {
        if (p.hasMatch(command)) return true;
      }
    }

    // 3) فحص المسارات المطلقة لـ Windows في الأمر (C:\...) مع تجنب بروتوكولات URL مثل http:// و https://
    final absolutePathPattern = RegExp(r'''(^|[\s"'`=])([A-Za-z]:[/\\][^\s"']*)''');
    final matches = absolutePathPattern.allMatches(command);

    for (final match in matches) {
      final pathStr = match.group(2)!;
      final foundPath = _normalizePath(pathStr);
      if (!foundPath.startsWith(normalizedRoot)) {
        return true;
      }
    }

    // 4) فحص مسارات Unix (WSL)
    final unixPathPattern = RegExp(r'''/[a-z]+/[^\s"']+''');
    final unixMatches = unixPathPattern.allMatches(command);
    for (final match in unixMatches) {
      final p = match.group(0)!;
      // مسارات /home, /etc, /usr, /var, /root → خارج المشروع
      if (p.startsWith('/home/') ||
          p.startsWith('/etc/') ||
          p.startsWith('/usr/') ||
          p.startsWith('/var/') ||
          p.startsWith('/root/')) {
        return true;
      }
    }

    return false;
  }

  static String _normalizePath(String path) {
    return path
        .toLowerCase()
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'\\+'), '\\')
        .trimRight();
  }

  /// يفكك الأمر المركب (&&, ||, ;, |, \n) خارج علامات الاقتباس إلى أجزاء مستقلة.
  static List<String> _splitCompoundCommand(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    bool inSingleQuote = false;
    bool inDoubleQuote = false;

    for (int i = 0; i < command.length; i++) {
      final char = command[i];
      final nextChar = (i + 1 < command.length) ? command[i + 1] : '';

      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
        buffer.write(char);
      } else if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        buffer.write(char);
      } else if (!inSingleQuote && !inDoubleQuote) {
        if ((char == '&' && nextChar == '&') || (char == '|' && nextChar == '|')) {
          if (buffer.isNotEmpty) {
            segments.add(buffer.toString().trim());
            buffer.clear();
          }
          i++; // تجاوز الحرف الثاني من المعامل
        } else if (char == ';' || char == '|' || char == '\n' || char == '\r') {
          if (buffer.isNotEmpty) {
            segments.add(buffer.toString().trim());
            buffer.clear();
          }
        } else {
          buffer.write(char);
        }
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      segments.add(buffer.toString().trim());
    }

    return segments.where((s) => s.isNotEmpty).toList();
  }

  /// فحص جزء منفرد من الأمر.
  static InterceptionResult _checkSingleSegment({
    required String segment,
    required String projectRootPath,
  }) {
    final cmd = segment.trim();
    final cmdLower = cmd.toLowerCase();

    // 1) فحص خروج المسار عن الجذر أو مسارات UNC → رفض فوري
    if (_commandContainsPathOutsideRoot(cmd, projectRootPath)) {
      return const RejectedCommand(
        reason: 'الأمر يحاول الوصول لمسار خارج مجلد المشروع النشط — مرفوض تلقائياً.',
      );
    }

    // 2) أنماط الحذف الجماعي
    for (final pattern in _massDeletePatterns) {
      if (RegExp(pattern, caseSensitive: false, multiLine: true).hasMatch(cmd)) {
        return RequiresConfirmation(
          reason: 'أمر حذف جماعي / لا رجعة فيه: `$cmd`\n\nهذا الأمر قد يمسح ملفات أو مجلدات نهائياً.',
          category: 'mass_deletion',
        );
      }
    }

    // 3) أوامر Git الخطيرة
    for (final pattern in _dangerousGitPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(cmdLower)) {
        return RequiresConfirmation(
          reason: 'أمر Git خطير لا رجعة فيه: `$cmd`\n\nقد يُعيد كتابة التاريخ أو يمسح تغييرات غير محفوظة.',
          category: 'dangerous_git',
        );
      }
    }

    // 4) أوامر النظام الحساسة
    for (final pattern in _systemSensitivePatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(cmd)) {
        return RequiresConfirmation(
          reason: 'أمر نظام حساس: `$cmd`\n\nقد يُعدّل إعدادات النظام أو بيانات الاعتماد.',
          category: 'system_sensitive',
        );
      }
    }

    // 5) تسريب بيانات حساسة
    for (final pattern in _dataExfiltrationPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(cmd)) {
        return RequiresConfirmation(
          reason: 'أمر قد يُسرّب بيانات حساسة: `$cmd`',
          category: 'data_exfiltration',
        );
      }
    }

    return const SafeCommand();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// يفحص [command] ويرجع نتيجة الاعتراض.
  ///
  /// [projectRootPath] — مسار جذر المشروع النشط للتحقق من احتواء المسار.
  static InterceptionResult check({
    required String command,
    required String projectRootPath,
  }) {
    final cmd = command.trim();

    // 1) فحص خروج المسار أو مسار UNC على كامل الأمر أولاً
    if (_commandContainsPathOutsideRoot(cmd, projectRootPath)) {
      return const RejectedCommand(
        reason: 'الأمر يحاول الوصول لمسار خارج مجلد المشروع النشط — مرفوض تلقائياً.',
      );
    }

    // 2) تفكيك الأوامر المركبة وفحص كل جزء
    final segments = _splitCompoundCommand(cmd);

    RequiresConfirmation? firstConfirmation;

    for (final segment in segments) {
      final result = _checkSingleSegment(
        segment: segment,
        projectRootPath: projectRootPath,
      );

      if (result is RejectedCommand) {
        return result; // الرفض له أولوية عليا
      }

      if (result is RequiresConfirmation && firstConfirmation == null) {
        firstConfirmation = result;
      }
    }

    if (firstConfirmation != null) {
      return firstConfirmation;
    }

    // 3) فحص الأمر ككل تحسباً لأي نمط يمتد عبر الأجزاء
    return _checkSingleSegment(
      segment: cmd,
      projectRootPath: projectRootPath,
    );
  }

  /// يرجع قائمة بأسماء الفئات التي تُعترض لأغراض الاختبار.
  static List<String> get interceptedCategories => [
        'mass_deletion',
        'dangerous_git',
        'system_sensitive',
        'data_exfiltration',
        'path_outside_root',
      ];
}
