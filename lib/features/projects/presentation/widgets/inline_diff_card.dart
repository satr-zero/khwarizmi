import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/core/utils/path_utils.dart';
import 'package:khwarizmi/features/projects/domain/entities/pending_file_change.dart';
import 'package:khwarizmi/features/projects/presentation/controllers/project_provider.dart';
import 'package:khwarizmi/features/projects/services/diff_service.dart';

/// بطاقة مخصصة لعرض الـ Diff المنسق مباشرة ضمن تسلسل الشات (Inline Diff Card).
///
/// تدعم:
/// - اسم الملف بوضوح بالأعلى
/// - عدّاد صريح لأسطر الإضافة (+X بالأخضر) وأسطر الحذف (-Y بالأحمر)
/// - تبديل طريقة العرض (Unified موحد / Side-by-Side جنبًا إلى جنب)
/// - تمييز بصري للأسطر المضافة بخلفية خضراء والمحذوفة بخلفية حمراء
/// - أزرار موافقة/رفض مباشرة على البطاقة نفسها
class InlineDiffCard extends ConsumerStatefulWidget {
  final String filePath;
  final String? newContent;
  final String? oldContent;
  final String? changeId;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const InlineDiffCard({
    super.key,
    required this.filePath,
    this.newContent,
    this.oldContent,
    this.changeId,
    this.onApprove,
    this.onReject,
  });

  @override
  ConsumerState<InlineDiffCard> createState() => _InlineDiffCardState();
}

class _InlineDiffCardState extends ConsumerState<InlineDiffCard> {
  bool _isSideBySide = false;
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primary = isDark
        ? DesignTokens.textPrimaryDark
        : DesignTokens.textPrimaryLight;
    final secondary = isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;
    final surface = isDark
        ? DesignTokens.surfaceDark
        : DesignTokens.surfaceLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    // محاولة إيجاد التعديل المعلّق من ProjectManager
    // إصلاح 05: المطابقة عبر isSameFilePath بدل endsWith الخام — النموذج
    // يرسل المسار بصيغة POSIX (lib/main.dart) بينما يخزّن Windows المسار
    // المطلق بشرطة خلفية، فكانت المطابقة تفشل ويظهر الـ Diff فارغاً.
    final pendingChanges = ref.watch(pendingChangesProvider);
    final PendingFileChange? change = pendingChanges
        .cast<PendingFileChange?>()
        .firstWhere(
          (c) =>
              c != null &&
              (c.id == widget.changeId ||
                  isSameFilePath(c.absolutePath, widget.filePath)),
          orElse: () => null,
        );

    // حساب الـ diff lines
    final List<DiffLine> diffLines;
    if (change != null) {
      diffLines = change.diffLines;
    } else if (widget.newContent != null) {
      diffLines = DiffService.computeDiff(
        newText: widget.newContent!,
        oldText: widget.oldContent,
      );
    } else {
      diffLines = const [];
    }

    final addedCount = diffLines
        .where((l) => l.type == DiffLineType.added)
        .length;
    final removedCount = diffLines
        .where((l) => l.type == DiffLineType.removed)
        .length;

    final fileName = widget.filePath.split(RegExp(r'[/\\]')).last;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: DesignTokens.space8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: border, width: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── رأس البطاقة ─────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(DesignTokens.radiusMd),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.space12,
                vertical: DesignTokens.space12,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.difference_rounded,
                    size: 16,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  ),
                  const SizedBox(width: DesignTokens.space8),

                  // اسم الملف
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeSm,
                            fontWeight: FontWeight.w700,
                            fontFamily: DesignTokens.fontFamilyMono,
                            fontFamilyFallback: DesignTokens.monoFallbacks,
                            color: primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.filePath,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeXs,
                            color: secondary,
                            fontFamily: DesignTokens.fontFamilyMono,
                            fontFamilyFallback: DesignTokens.monoFallbacks,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // عدّاد الإضافة والحذف
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF16381E)
                          : const Color(0xFFE6F4EA),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+$addedCount',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF81C995)
                            : const Color(0xFF137333),
                        fontFamily: DesignTokens.fontFamilyMono,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3C1818)
                          : const Color(0xFFFCE8E6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-$removedCount',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFF28B82)
                            : const Color(0xFFC5221F),
                        fontFamily: DesignTokens.fontFamilyMono,
                      ),
                    ),
                  ),

                  const SizedBox(width: DesignTokens.space8),

                  // زر تبديل Unified / Side-by-Side
                  InkWell(
                    onTap: () => setState(() => _isSideBySide = !_isSideBySide),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? DesignTokens.bgDark
                            : DesignTokens.surfaceInputLight,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: border,
                          width: DesignTokens.hairline,
                        ),
                      ),
                      child: Text(
                        _isSideBySide ? 'Side-by-Side' : 'Unified',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          color: secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: DesignTokens.space4),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: secondary,
                  ),
                ],
              ),
            ),
          ),

          // ── عرض أسطر الـ Diff ────────────────────────────────────────────────
          if (_isExpanded && diffLines.isNotEmpty) ...[
            Divider(height: DesignTokens.hairline, color: border),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _isSideBySide
                      ? _buildSideBySideView(
                          diffLines,
                          isDark,
                          primary,
                          secondary,
                        )
                      : _buildUnifiedView(
                          diffLines,
                          isDark,
                          primary,
                          secondary,
                        ),
                ),
              ),
            ),
          ],

          // ── أزرار الموافقة والرفض المباشرة ─────────────────────────────────────
          if (change != null || widget.onApprove != null) ...[
            Divider(height: DesignTokens.hairline, color: border),
            Padding(
              padding: const EdgeInsets.all(DesignTokens.space8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text('تجاهل التعديل'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? const Color(0xFFF28B82)
                          : const Color(0xFFC5221F),
                    ),
                    onPressed: () {
                      if (change != null) {
                        ref
                            .read(projectProvider.notifier)
                            .rejectChange(change.id);
                      }
                      widget.onReject?.call();
                    },
                  ),
                  const SizedBox(width: DesignTokens.space8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 14),
                    label: const Text('تطبيق التعديل على الملف'),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF1E4620)
                          : const Color(0xFF137333),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      if (change != null) {
                        ref
                            .read(projectProvider.notifier)
                            .applyChange(change.id);
                      }
                      widget.onApprove?.call();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Unified Diff View ───────────────────────────────────────────────────────
  Widget _buildUnifiedView(
    List<DiffLine> lines,
    bool isDark,
    Color primary,
    Color secondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final Color rowBg;
        final Color rowFg;
        final String prefix;

        switch (line.type) {
          case DiffLineType.added:
            rowBg = isDark ? const Color(0xFF142B18) : const Color(0xFFE8F5E9);
            rowFg = isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20);
            prefix = '+';
            break;
          case DiffLineType.removed:
            rowBg = isDark ? const Color(0xFF331414) : const Color(0xFFFFEBEE);
            rowFg = isDark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C);
            prefix = '-';
            break;
          case DiffLineType.context:
            rowBg = Colors.transparent;
            rowFg = secondary;
            prefix = ' ';
            break;
        }

        final lineNum = line.newLineNumber ?? line.oldLineNumber;

        return Container(
          color: rowBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  lineNum != null ? '$lineNum' : '',
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: secondary.withValues(alpha: 0.6),
                    fontFamily: DesignTokens.fontFamilyMono,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 14,
                child: Text(
                  prefix,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: rowFg,
                    fontWeight: FontWeight.bold,
                    fontFamily: DesignTokens.fontFamilyMono,
                  ),
                ),
              ),
              Text(
                line.content,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  fontFamily: DesignTokens.fontFamilyMono,
                  fontFamilyFallback: DesignTokens.monoFallbacks,
                  color: rowFg,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Side-by-Side Diff View ──────────────────────────────────────────────────
  Widget _buildSideBySideView(
    List<DiffLine> lines,
    bool isDark,
    Color primary,
    Color secondary,
  ) {
    final removedLines = lines
        .where((l) => l.type != DiffLineType.added)
        .toList();
    final addedLines = lines
        .where((l) => l.type != DiffLineType.removed)
        .toList();
    final maxLen = removedLines.length > addedLines.length
        ? removedLines.length
        : addedLines.length;

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: List.generate(maxLen, (i) {
        final leftLine = i < removedLines.length ? removedLines[i] : null;
        final rightLine = i < addedLines.length ? addedLines[i] : null;

        return TableRow(
          children: [
            _buildSideCell(leftLine, isDark, secondary, isLeft: true),
            _buildSideCell(rightLine, isDark, secondary, isLeft: false),
          ],
        );
      }),
    );
  }

  Widget _buildSideCell(
    DiffLine? line,
    bool isDark,
    Color secondary, {
    required bool isLeft,
  }) {
    if (line == null) {
      return Container(
        height: 20,
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9F9F9),
      );
    }

    final Color cellBg;
    final Color cellFg;

    if (line.type == DiffLineType.removed) {
      cellBg = isDark ? const Color(0xFF331414) : const Color(0xFFFFEBEE);
      cellFg = isDark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C);
    } else if (line.type == DiffLineType.added) {
      cellBg = isDark ? const Color(0xFF142B18) : const Color(0xFFE8F5E9);
      cellFg = isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20);
    } else {
      cellBg = Colors.transparent;
      cellFg = secondary;
    }

    final numVal = isLeft ? line.oldLineNumber : line.newLineNumber;

    return Container(
      color: cellBg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              numVal != null ? '$numVal' : '',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: secondary.withValues(alpha: 0.6),
                fontFamily: DesignTokens.fontFamilyMono,
              ),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            line.content,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              fontFamily: DesignTokens.fontFamilyMono,
              fontFamilyFallback: DesignTokens.monoFallbacks,
              color: cellFg,
            ),
          ),
        ],
      ),
    );
  }
}
