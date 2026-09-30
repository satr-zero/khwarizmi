import 'dart:io';

/// يقتل العملية وشجرتها الكاملة (كل العمليات الأبناء والأحفاد).
///
/// إصلاح 09: `Process.kill()` يقتل العملية الأم فقط ويترك أبناءها أيتاماً
/// يكملون العمل في الخلفية (مثلاً: قتل powershell يترك ping أو flutter
/// test تعمل حتى نهايتها الطبيعية). على ويندوز نستخدم `taskkill /F /T`
/// لقتل الشجرة كاملة قسراً، مع قتل مباشر كاحتياط عند فشله أو على الأنظمة
/// الأخرى.
Future<void> killProcessTree(Process process) async {
  try {
    if (Platform.isWindows) {
      // /F إنهاء قسري، /T يشمل كل شجرة العمليات الأبناء.
      final result = await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        '${process.pid}',
      ]);
      if (result.exitCode == 0) return;
      // فشل taskkill (مثلاً العملية ماتت أصلاً) — قتل مباشر احتياطي.
      process.kill();
      return;
    }
    process.kill();
  } catch (_) {
    // العملية قد تكون انتهت قبل محاولة القتل — لا شيء يجب عمله.
  }
}
