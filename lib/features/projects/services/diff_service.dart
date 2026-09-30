import 'package:khwarizmi/features/projects/domain/entities/pending_file_change.dart';

/// خدمة حساب الـ Diff بين نسختين من نص.
///
/// تستخدم خوارزمية Longest Common Subsequence (LCS) المبسّطة على مستوى السطور.
/// الناتج قائمة [DiffLine] مع سطور سياق (context lines) للمساعدة على الفهم.
class DiffService {
  DiffService._();

  /// عدد سطور السياق المعروضة قبل وبعد كل تغيير.
  static const int _contextLines = 3;

  /// يحسب الـ Diff بين [oldText] و[newText] ويرجع قائمة [DiffLine].
  ///
  /// إذا كان [oldText] فارغًا/null → يُعامَل كملف جديد (كل السطور مضافة).
  static List<DiffLine> computeDiff({
    required String newText,
    String? oldText,
  }) {
    // ملف جديد بالكامل
    if (oldText == null || oldText.isEmpty) {
      final lines = _splitLines(newText);
      return [
        for (int i = 0; i < lines.length; i++)
          DiffLine(
            type: DiffLineType.added,
            content: lines[i],
            newLineNumber: i + 1,
          ),
      ];
    }

    final oldLines = _splitLines(oldText);
    final newLines = _splitLines(newText);

    // حساب LCS
    final lcs = _computeLCS(oldLines, newLines);

    // بناء سطور الـ Diff من نتيجة LCS
    final rawDiff = _buildDiffLines(oldLines, newLines, lcs);

    // إضافة سطور السياق
    return _addContextLines(rawDiff, oldLines, newLines);
  }

  // ── LCS ──────────────────────────────────────────────────────────────────

  static List<List<int>> _computeLCS(
    List<String> oldLines,
    List<String> newLines,
  ) {
    final m = oldLines.length;
    final n = newLines.length;

    // جدول DP
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (oldLines[i - 1] == newLines[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    // استخراج مؤشرات LCS
    final lcsIndices = <List<int>>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (oldLines[i - 1] == newLines[j - 1]) {
        lcsIndices.add([i - 1, j - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    return lcsIndices.reversed.toList();
  }

  // ── Build Diff ────────────────────────────────────────────────────────────

  static List<_RawDiffEntry> _buildDiffLines(
    List<String> oldLines,
    List<String> newLines,
    List<List<int>> lcs,
  ) {
    final result = <_RawDiffEntry>[];
    int oi = 0, ni = 0, li = 0;

    while (oi < oldLines.length || ni < newLines.length) {
      final lcsOld = li < lcs.length ? lcs[li][0] : -1;
      final lcsNew = li < lcs.length ? lcs[li][1] : -1;

      if (li < lcs.length && oi == lcsOld && ni == lcsNew) {
        // سطر مشترك (context)
        result.add(_RawDiffEntry(
          type: DiffLineType.context,
          content: oldLines[oi],
          oldIndex: oi,
          newIndex: ni,
        ));
        oi++;
        ni++;
        li++;
      } else if (oi < oldLines.length && (li >= lcs.length || oi < lcsOld)) {
        // سطر محذوف
        result.add(_RawDiffEntry(
          type: DiffLineType.removed,
          content: oldLines[oi],
          oldIndex: oi,
          newIndex: -1,
        ));
        oi++;
      } else if (ni < newLines.length) {
        // سطر مضاف
        result.add(_RawDiffEntry(
          type: DiffLineType.added,
          content: newLines[ni],
          oldIndex: -1,
          newIndex: ni,
        ));
        ni++;
      }
    }

    return result;
  }

  // ── Context Lines ─────────────────────────────────────────────────────────

  static List<DiffLine> _addContextLines(
    List<_RawDiffEntry> raw,
    List<String> oldLines,
    List<String> newLines,
  ) {
    // تحديد موقع التغييرات
    final changedIndices = <int>{};
    for (int i = 0; i < raw.length; i++) {
      if (raw[i].type != DiffLineType.context) {
        for (int c = (i - _contextLines).clamp(0, raw.length - 1);
            c <= (i + _contextLines).clamp(0, raw.length - 1);
            c++) {
          changedIndices.add(c);
        }
      }
    }

    final result = <DiffLine>[];
    int oldLineNum = 1, newLineNum = 1;
    bool lastWasOmitted = false;

    for (int i = 0; i < raw.length; i++) {
      final entry = raw[i];

      if (!changedIndices.contains(i) && entry.type == DiffLineType.context) {
        if (!lastWasOmitted && result.isNotEmpty) {
          // سطر ... للإشارة إلى محتوى محذوف من العرض
        }
        lastWasOmitted = true;
        if (entry.oldIndex >= 0) oldLineNum++;
        if (entry.newIndex >= 0) newLineNum++;
        continue;
      }

      lastWasOmitted = false;

      switch (entry.type) {
        case DiffLineType.context:
          result.add(DiffLine(
            type: DiffLineType.context,
            content: entry.content,
            oldLineNumber: oldLineNum++,
            newLineNumber: newLineNum++,
          ));
        case DiffLineType.removed:
          result.add(DiffLine(
            type: DiffLineType.removed,
            content: entry.content,
            oldLineNumber: oldLineNum++,
          ));
        case DiffLineType.added:
          result.add(DiffLine(
            type: DiffLineType.added,
            content: entry.content,
            newLineNumber: newLineNum++,
          ));
      }
    }

    return result;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<String> _splitLines(String text) {
    return text.split('\n');
  }
}

/// سطر خام في الـ Diff الداخلي قبل إضافة سطور السياق.
class _RawDiffEntry {
  final DiffLineType type;
  final String content;
  final int oldIndex; // -1 إن لم ينتمِ للنسخة القديمة
  final int newIndex; // -1 إن لم ينتمِ للنسخة الجديدة

  const _RawDiffEntry({
    required this.type,
    required this.content,
    required this.oldIndex,
    required this.newIndex,
  });
}
