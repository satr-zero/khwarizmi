import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/layout_controller.dart';
import 'package:khwarizmi/features/chat/presentation/models/file_attachment_info.dart';
import 'package:khwarizmi/features/filesystem/services/file_system_service.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';

/// بطاقة إشعار إنشاء الملفات — مصممة بأسلوب OpenCode / Cursor.
///
/// تعرض مسار الملف المُنشأ بوضوح مع زر "فتح" للمعاينة السريعة
/// وأزرار جانبية لنسخ المسار وإظهاره في مستكشف ويندوز.
class FileAttachmentCard extends ConsumerWidget {
  final FileAttachmentInfo file;

  const FileAttachmentCard({
    super.key,
    required this.file,
  });

  String _resolveAbsolutePath(String path) {
    if (p.isAbsolute(path)) return p.normalize(path);
    final activeProj = ProjectManager.instance.activeProject;
    if (activeProj != null) {
      final projPath = p.join(activeProj.rootPath, path);
      if (File(projPath).existsSync()) return p.normalize(projPath);
    }
    final sandboxed = p.join(FileSystemService.defaultAllowedDirectory, path);
    if (File(sandboxed).existsSync()) return p.normalize(sandboxed);
    if (activeProj != null) {
      return p.normalize(p.join(activeProj.rootPath, path));
    }
    return p.normalize(sandboxed);
  }

  void _openPreview(WidgetRef ref) {
    final absPath = _resolveAbsolutePath(file.path);
    ref.read(layoutProvider.notifier).openFilePreview(
          absPath,
          content: file.content,
        );
  }

  void _revealInExplorer() {
    final absPath = _resolveAbsolutePath(file.path);
    if (Platform.isWindows) {
      final winPath = absPath.replaceAll('/', '\\');
      Process.run('explorer.exe', ['/select,$winPath']);
    }
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF18181D) : const Color(0xFFF7F7FA);
    final borderColor = isDark ? const Color(0xFF282832) : const Color(0xFFE2E2E8);
    final iconBoxBg = isDark ? const Color(0xFF22222B) : const Color(0xFFEBEBF2);
    final iconBoxBorder = isDark ? const Color(0xFF33333F) : const Color(0xFFD6D6DF);
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final ext = file.fileType.toUpperCase();
    final absPath = _resolveAbsolutePath(file.path);

    return Container(
      constraints: const BoxConstraints(maxWidth: 580),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // ── أيقونة الملف مع نوعه ──────────────────────────────────────
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBoxBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: iconBoxBorder, width: 0.8),
                ),
                child: Center(
                  child: _DocumentGlyph(isDark: isDark),
                ),
              ),
              const SizedBox(width: 12),

              // ── تفاصيل المسار والاسم ─────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF16381E) : const Color(0xFFE6F4EA),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'تم الإنشاء',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF81C995) : const Color(0xFF137333),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          file.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeSm,
                            fontWeight: FontWeight.w700,
                            color: primary,
                            fontFamily: DesignTokens.fontFamilySans,
                            fontFamilyFallback: DesignTokens.sansFallbacks,
                          ),
                        ),
                        if (ext.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '· $ext',
                            style: TextStyle(
                              fontSize: 11,
                              color: secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Tooltip(
                      message: absPath,
                      child: Text(
                        file.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: secondary,
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontFamilyFallback: DesignTokens.monoFallbacks,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // ── زر نسخ المسار ─────────────────────────────────────────────
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 15, color: secondary),
                tooltip: 'نسخ المسار',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: absPath));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ مسار الملف إلى الحافظة'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),

              // ── زر إظهار في مستكشف ويندوز ──────────────────────────────────
              IconButton(
                icon: Icon(Icons.folder_open_outlined, size: 16, color: secondary),
                tooltip: 'إظهار في مستكشف الملفات',
                visualDensity: VisualDensity.compact,
                onPressed: _revealInExplorer,
              ),

              const SizedBox(width: 4),

              // ── زر "فتح" الرئيسي ───────────────────────────────────────────
              FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                label: const Text('فتح'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _openPreview(ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// أيقونة المستند مع الزاوية المطوية وخطوط النص التوضيحية
class _DocumentGlyph extends StatelessWidget {
  final bool isDark;

  const _DocumentGlyph({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final strokeColor = isDark ? const Color(0xFFB0B0BE) : const Color(0xFF4A4A55);

    return CustomPaint(
      size: const Size(18, 20),
      painter: _DocumentPainter(color: strokeColor),
    );
  }
}

class _DocumentPainter extends CustomPainter {
  final Color color;

  _DocumentPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final fold = 5.0;

    // مسار الورقة مع زاوية مطوية في الأعلى يميناً
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(path, paint);

    // خط طي الزاوية
    final foldPath = Path()
      ..moveTo(w - fold, 0)
      ..lineTo(w - fold, fold)
      ..lineTo(w, fold);
    canvas.drawPath(foldPath, paint);

    // خطوط داخلية
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final wave1 = Path()
      ..moveTo(4, h * 0.46)
      ..lineTo(w - 4, h * 0.46);
    canvas.drawPath(wave1, linePaint);

    final wave2 = Path()
      ..moveTo(4, h * 0.68)
      ..lineTo(w - 6, h * 0.68);
    canvas.drawPath(wave2, linePaint);
  }

  @override
  bool shouldRepaint(covariant _DocumentPainter oldDelegate) =>
      oldDelegate.color != color;
}
