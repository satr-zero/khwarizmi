import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/projects/domain/entities/pending_file_change.dart';
import 'package:khwarizmi/features/projects/presentation/controllers/project_provider.dart';

/// لوحة مراجعة الـ Diff والموافقة — المرحلة 9.
///
/// تُعرض كـ Bottom Sheet عند وجود تعديلات معلَّقة.
/// كل تعديل يُعرض مع Diff واضح + زرّا "تطبيق" و"تجاهل".
/// زر "تطبيق الكل" للموافقة دفعةً واحدة.
class DiffReviewPanel extends ConsumerWidget {
  const DiffReviewPanel({super.key});

  /// يفتح اللوحة كـ Bottom Sheet.
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DiffReviewPanel(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final bg = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final changes = ref.watch(pendingChangesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DesignTokens.radiusLg),
            ),
            border: Border(top: BorderSide(color: border, width: DesignTokens.hairline)),
          ),
          child: Column(
            children: [
              // ── مقبض السحب ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── رأس اللوحة ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.space16,
                  vertical: DesignTokens.space8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.difference_outlined, size: 16, color: secondary),
                    const SizedBox(width: DesignTokens.space8),
                    Text(
                      'مراجعة الكود — ${changes.length} تعديل معلَّق',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeBase,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                    const Spacer(),

                    // تطبيق الكل
                    if (changes.isNotEmpty)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.done_all_rounded, size: 14),
                        label: const Text('تطبيق الكل'),
                        onPressed: () {
                          ref.read(projectProvider.notifier).applyAllChanges();
                          Navigator.of(context).pop();
                        },
                      ),

                    const SizedBox(width: DesignTokens.space8),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 16, color: secondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              Divider(height: DesignTokens.hairline, color: border),

              // ── قائمة التعديلات ─────────────────────────────────────────────
              Expanded(
                child: changes.isEmpty
                    ? Center(
                        child: Text(
                          'لا توجد تعديلات معلَّقة',
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeSm,
                            color: secondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(DesignTokens.space16),
                        itemCount: changes.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: DesignTokens.space16),
                        itemBuilder: (context, index) => _DiffChangeCard(
                          change: changes[index],
                          isDark: isDark,
                          surface: surface,
                          bg: bg,
                          border: border,
                          primary: primary,
                          secondary: secondary,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── بطاقة تعديل واحد ──────────────────────────────────────────────────────────

class _DiffChangeCard extends ConsumerWidget {
  final PendingFileChange change;
  final bool isDark;
  final Color surface, bg, border, primary, secondary;

  const _DiffChangeCard({
    required this.change,
    required this.isDark,
    required this.surface,
    required this.bg,
    required this.border,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ألوان الـ Diff (monochrome — لا أخضر/أحمر تقليدي)
    final addedBg = isDark
        ? const Color(0xFF1E2A1E)  // داكن مخضر خفيف جداً
        : const Color(0xFFECF5EC); // فاتح مخضر
    final removedBg = isDark
        ? const Color(0xFF2A1E1E)  // داكن محمر خفيف جداً
        : const Color(0xFFF5ECEC); // فاتح محمر
    final contextBg = Colors.transparent;

    final addedFg = isDark ? const Color(0xFFB8D4B8) : const Color(0xFF2D6A2D);
    final removedFg = isDark ? const Color(0xFFD4B8B8) : const Color(0xFF6A2D2D);
    final contextFg = secondary;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: border, width: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── رأس التعديل ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(DesignTokens.space12),
            child: Row(
              children: [
                Icon(
                  change.isNewFile
                      ? Icons.add_circle_outline_rounded
                      : Icons.edit_outlined,
                  size: 14,
                  color: secondary,
                ),
                const SizedBox(width: DesignTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        change.fileName,
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          fontWeight: FontWeight.w600,
                          color: primary,
                          fontFamily: DesignTokens.fontFamilyMono,
                        ),
                      ),
                      Text(
                        change.isNewFile ? 'ملف جديد' : 'تعديل ملف موجود',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeXs,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // زر تطبيق
                TextButton(
                  onPressed: () {
                    ref.read(projectProvider.notifier).applyChange(change.id);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.space12,
                      vertical: DesignTokens.space4,
                    ),
                  ),
                  child: Text(
                    'تطبيق',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      color: primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // زر تجاهل
                TextButton(
                  onPressed: () {
                    ref.read(projectProvider.notifier).rejectChange(change.id);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.space12,
                      vertical: DesignTokens.space4,
                    ),
                  ),
                  child: Text(
                    'تجاهل',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      color: secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: DesignTokens.hairline, color: border),

          // ── عرض الـ Diff ──────────────────────────────────────────────────
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF8F8F8),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(DesignTokens.radiusMd),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: DesignTokens.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: change.diffLines.map((line) {
                  final Color lineBg;
                  final Color lineFg;
                  final String prefix;

                  switch (line.type) {
                    case DiffLineType.added:
                      lineBg = addedBg;
                      lineFg = addedFg;
                      prefix = '+ ';
                    case DiffLineType.removed:
                      lineBg = removedBg;
                      lineFg = removedFg;
                      prefix = '- ';
                    case DiffLineType.context:
                      lineBg = contextBg;
                      lineFg = contextFg;
                      prefix = '  ';
                  }

                  return Container(
                    color: lineBg,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // رقم السطر
                        SizedBox(
                          width: 40,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.space4,
                            ),
                            child: Text(
                              '${line.oldLineNumber ?? line.newLineNumber ?? ''}',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: DesignTokens.fontFamilyMono,
                                color: secondary.withAlpha(150),
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),

                        // نص السطر
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.space4,
                            ),
                            child: Text(
                              '$prefix${line.content}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: DesignTokens.fontFamilyMono,
                                color: lineFg,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// مربع حوار تأكيد أمر ترمينال خطر.
class TerminalConfirmationDialog extends StatelessWidget {
  final String command;
  final String reason;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const TerminalConfirmationDialog({
    super.key,
    required this.command,
    required this.reason,
    required this.onApprove,
    required this.onReject,
  });

  static Future<bool> show(
    BuildContext context, {
    required String command,
    required String reason,
  }) async {
    bool result = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TerminalConfirmationDialog(
        command: command,
        reason: reason,
        onApprove: () {
          result = true;
          Navigator.of(ctx).pop();
        },
        onReject: () {
          result = false;
          Navigator.of(ctx).pop();
        },
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(color: border),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: primary),
          const SizedBox(width: DesignTokens.space8),
          Text(
            '⚠️ تأكيد مطلوب',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeBase,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reason,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeSm,
              color: secondary,
            ),
          ),
          const SizedBox(height: DesignTokens.space12),
          Text(
            'الأمر المطلوب تأكيده:',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: secondary,
            ),
          ),
          const SizedBox(height: DesignTokens.space4),
          Container(
            padding: const EdgeInsets.all(DesignTokens.space8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: Border.all(color: border),
            ),
            child: SelectableText(
              command,
              style: TextStyle(
                fontSize: 13,
                fontFamily: DesignTokens.fontFamilyMono,
                color: primary,
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.space12),
          Text(
            'تحذير: هذا الاكتشاف احترازي — تأكد أنك تعرف تأثير هذا الأمر قبل المتابعة.',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: secondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onReject,
          child: Text(
            'رفض — لا تنفذ',
            style: TextStyle(color: secondary),
          ),
        ),
        OutlinedButton(
          onPressed: onApprove,
          child: Text(
            'تأكيد — نفّذ الأمر',
            style: TextStyle(color: primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
