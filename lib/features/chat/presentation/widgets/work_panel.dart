import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/presentation/widgets/live_browser_panel.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/layout_controller.dart';
import 'package:khwarizmi/features/filesystem/services/file_system_service.dart';
import 'package:khwarizmi/features/projects/presentation/widgets/live_terminal_panel.dart';
import 'package:khwarizmi/features/projects/services/project_manager.dart';

/// لوحة العمل الموحّدة — تجمع المتصفح الحي والترمينال ومعاينة الملفات في مكوّن واحد بتبويبات.
///
/// الاستخدام:
/// - في وضع [LayoutMode.wide]: تُوضع كعمود ثالث مجاور للمحادثة
/// - في وضع [LayoutMode.compact/standard]: تُفتح كـ overlay فوق المحادثة
///
/// تدعم:
/// - سحب الفاصل (draggable divider) لتغيير العرض
/// - تبديل التبويبات بين المتصفح، الترمينال، ومعاينة الملفات
/// - زر إغلاق دائم في الرأس
class WorkPanel extends ConsumerStatefulWidget {
  /// هل تُعرض كـ overlay (حدود دائرية + ظل) أم كعمود مباشر؟
  final bool isOverlay;

  const WorkPanel({super.key, this.isOverlay = false});

  @override
  ConsumerState<WorkPanel> createState() => _WorkPanelState();
}

class _WorkPanelState extends ConsumerState<WorkPanel> {
  double _dragStartWidth = DesignTokens.workPanelDefaultWidth;
  double _dragStartX = 0;

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(layoutProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;

    final panelContent = Column(
      children: [
        // ── رأس اللوحة ───────────────────────────────────────────────────
        Container(
          height: DesignTokens.topBarHeight,
          decoration: BoxDecoration(
            color: surface,
            border: Border(
              bottom: BorderSide(color: border, width: DesignTokens.hairline),
            ),
          ),
          child: Row(
            children: [
              // تبويب المتصفح
              _TabButton(
                icon: Icons.language_outlined,
                label: 'المتصفح',
                isActive: layout.activeWorkTab == WorkPanelTab.browser,
                isDark: isDark,
                onTap: () => ref.read(layoutProvider.notifier).switchTab(WorkPanelTab.browser),
              ),
              // تبويب الترمينال
              _TabButton(
                icon: Icons.terminal_rounded,
                label: 'الترمينال',
                isActive: layout.activeWorkTab == WorkPanelTab.terminal,
                isDark: isDark,
                onTap: () => ref.read(layoutProvider.notifier).switchTab(WorkPanelTab.terminal),
              ),
              // تبويب معاينة الملف
              if (layout.previewFilePath != null || layout.activeWorkTab == WorkPanelTab.file)
                _TabButton(
                  icon: Icons.description_outlined,
                  label: layout.previewFilePath != null
                      ? p.basename(layout.previewFilePath!)
                      : 'معاينة الملف',
                  isActive: layout.activeWorkTab == WorkPanelTab.file,
                  isDark: isDark,
                  onTap: () => ref.read(layoutProvider.notifier).switchTab(WorkPanelTab.file),
                ),
              const Spacer(),
              // زر الإغلاق
              IconButton(
                icon: Icon(Icons.close_rounded, size: 16, color: secondary),
                tooltip: 'إغلاق اللوحة',
                visualDensity: VisualDensity.compact,
                onPressed: () => ref.read(layoutProvider.notifier).closeWorkPanel(),
              ),
              const SizedBox(width: DesignTokens.space4),
            ],
          ),
        ),

        // ── محتوى التبويب النشط ──────────────────────────────────────────
        Expanded(
          child: IndexedStack(
            index: layout.activeWorkTab.index.clamp(0, 2),
            children: [
              // تبويب 0: المتصفح الحي
              const _BrowserContent(),
              // تبويب 1: الترمينال الحي
              const _TerminalContent(),
              // تبويب 2: معاينة الملف
              _FilePreviewContent(
                filePath: layout.previewFilePath,
                initialContent: layout.previewFileContent,
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.isOverlay) {
      // وضع overlay: نافذة طافية فوق المحادثة
      return Positioned(
        top: 0,
        bottom: 0,
        left: 0, // تظهر من اليسار في الواجهة العربية
        width: layout.workPanelWidth,
        child: Material(
          elevation: 16,
          color: surface,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(DesignTokens.radiusLg),
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: border, width: DesignTokens.hairline),
              ),
            ),
            child: panelContent,
          ),
        ),
      );
    }

    // وضع العمود المباشر (wide layout): مع فاصل قابل للسحب
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // فاصل السحب
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (details) {
              _dragStartWidth = layout.workPanelWidth;
              _dragStartX = details.globalPosition.dx;
            },
            onHorizontalDragUpdate: (details) {
              // في الواجهة العربية (RTL): السحب يميناً يُصغّر اللوحة، يساراً يُكبّرها
              final delta = _dragStartX - details.globalPosition.dx;
              ref
                  .read(layoutProvider.notifier)
                  .setWorkPanelWidth(_dragStartWidth + delta);
            },
            child: Container(
              width: 5,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: 1,
                  color: border,
                ),
              ),
            ),
          ),
        ),
        // محتوى اللوحة بالعرض المخصص
        SizedBox(
          width: layout.workPanelWidth,
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              border: Border(
                left: BorderSide(color: border, width: DesignTokens.hairline),
              ),
            ),
            child: panelContent,
          ),
        ),
      ],
    );
  }
}

// ── Tab Button ────────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? primary : Colors.transparent,
              width: 2,
            ),
            right: BorderSide(color: border, width: DesignTokens.hairline),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive ? primary : secondary,
            ),
            const SizedBox(width: DesignTokens.space4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? primary : secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Browser Content Wrapper ───────────────────────────────────────────────────

class _BrowserContent extends ConsumerStatefulWidget {
  const _BrowserContent();

  @override
  ConsumerState<_BrowserContent> createState() => _BrowserContentState();
}

class _BrowserContentState extends ConsumerState<_BrowserContent> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: LiveBrowserPanel(),
    );
  }
}

// ── Terminal Content Wrapper ──────────────────────────────────────────────────

class _TerminalContent extends ConsumerStatefulWidget {
  const _TerminalContent();

  @override
  ConsumerState<_TerminalContent> createState() => _TerminalContentState();
}

class _TerminalContentState extends ConsumerState<_TerminalContent> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: LiveTerminalPanel(),
    );
  }
}

// ── File Preview Content ──────────────────────────────────────────────────────

class _FilePreviewContent extends ConsumerStatefulWidget {
  final String? filePath;
  final String? initialContent;

  const _FilePreviewContent({
    this.filePath,
    this.initialContent,
  });

  @override
  ConsumerState<_FilePreviewContent> createState() => _FilePreviewContentState();
}

class _FilePreviewContentState extends ConsumerState<_FilePreviewContent> {
  String? _loadedContent;
  bool _isLoading = false;
  String? _error;
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _FilePreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.initialContent != widget.initialContent) {
      _loadIfNeeded();
    }
  }

  Future<void> _loadIfNeeded() async {
    if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
      setState(() {
        _loadedContent = widget.initialContent;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    if (widget.filePath == null || widget.filePath!.isEmpty) {
      setState(() {
        _loadedContent = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final resolved = _resolvePath(widget.filePath!);
      final file = File(resolved);
      if (await file.exists()) {
        final text = await file.readAsString();
        setState(() {
          _loadedContent = text;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'الملف غير موجود على القرص:\n${p.basename(resolved)}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'تعذر قراءة الملف: $e';
        _isLoading = false;
      });
    }
  }

  String _resolvePath(String path) {
    if (p.isAbsolute(path)) return p.normalize(path);
    final activeProject = ProjectManager.instance.activeProject;
    if (activeProject != null) {
      final projPath = p.join(activeProject.rootPath, path);
      if (File(projPath).existsSync()) return p.normalize(projPath);
    }
    final sandboxed = p.join(FileSystemService.defaultAllowedDirectory, path);
    if (File(sandboxed).existsSync()) return p.normalize(sandboxed);
    if (activeProject != null) {
      return p.normalize(p.join(activeProject.rootPath, path));
    }
    return p.normalize(sandboxed);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;

    if (widget.filePath == null && _loadedContent == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 48, color: secondary.withValues(alpha: 0.5)),
            const SizedBox(height: DesignTokens.space12),
            Text(
              'لا يوجد ملف محدد للمعاينة',
              style: TextStyle(color: secondary, fontSize: DesignTokens.fontSizeSm),
            ),
          ],
        ),
      );
    }

    final rawPath = widget.filePath ?? 'document.txt';
    final fileName = p.basename(rawPath);
    final ext = p.extension(fileName).replaceAll('.', '').toLowerCase();
    final isMarkdown = ext == 'md' || ext == 'markdown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── شريط أدوات المعاينة ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space12,
            vertical: 6.0,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E24) : const Color(0xFFF0F0F5),
            border: Border(bottom: BorderSide(color: border, width: DesignTokens.hairline)),
          ),
          child: Row(
            children: [
              Icon(Icons.article_outlined, size: 16, color: primary),
              const SizedBox(width: DesignTokens.space8),
              Expanded(
                child: Tooltip(
                  message: widget.filePath ?? fileName,
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C36) : const Color(0xFFE2E2EA),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ext.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: secondary,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.space8),

              // زر التبديل بين المعاينة المنسقة والكود الخام لملفات الماركداون
              if (isMarkdown)
                IconButton(
                  icon: Icon(
                    _showRaw ? Icons.visibility_outlined : Icons.code_rounded,
                    size: 15,
                    color: secondary,
                  ),
                  tooltip: _showRaw ? 'عرض المعاينة المنسقة' : 'عرض النص المصدري الخام',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showRaw = !_showRaw),
                ),

              // زر نسخ المحتوى
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 15, color: secondary),
                tooltip: 'نسخ محتوى الملف',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  if (_loadedContent != null) {
                    Clipboard.setData(ClipboardData(text: _loadedContent!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم نسخ محتوى الملف إلى الحافظة'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),

              // زر فتح في مستكشف الملفات
              if (widget.filePath != null)
                IconButton(
                  icon: Icon(Icons.folder_open_outlined, size: 16, color: secondary),
                  tooltip: 'إظهار الملف في المجلد',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final resolved = _resolvePath(widget.filePath!);
                    if (Platform.isWindows) {
                      final winPath = resolved.replaceAll('/', '\\');
                      Process.run('explorer.exe', ['/select,$winPath']);
                    }
                  },
                ),
            ],
          ),
        ),

        // ── محتوى الملف ──────────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(DesignTokens.space16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 36, color: Colors.orange.shade400),
                            const SizedBox(height: DesignTokens.space8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: secondary, fontSize: DesignTokens.fontSizeXs),
                            ),
                            const SizedBox(height: DesignTokens.space12),
                            TextButton.icon(
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: const Text('إعادة المحاولة'),
                              onPressed: _loadIfNeeded,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _loadedContent == null || _loadedContent!.isEmpty
                      ? Center(
                          child: Text(
                            'الملف فارغ',
                            style: TextStyle(color: secondary, fontSize: DesignTokens.fontSizeSm),
                          ),
                        )
                      : isMarkdown && !_showRaw
                          ? _buildMarkdownViewer(_loadedContent!, isDark, primary, surface)
                          : _buildCodeViewer(_loadedContent!, isDark, primary, secondary),
        ),
      ],
    );
  }

  Widget _buildMarkdownViewer(String content, bool isDark, Color textColor, Color surface) {
    final codeBg = isDark ? const Color(0xFF141418) : const Color(0xFFF3F3F7);
    final borderColor = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.space16),
      child: MarkdownBody(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            color: textColor,
            fontSize: DesignTokens.fontSizeBase,
            height: 1.6,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
          h1: TextStyle(
            color: textColor,
            fontSize: DesignTokens.fontSize2Xl,
            fontWeight: FontWeight.bold,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
          h2: TextStyle(
            color: textColor,
            fontSize: DesignTokens.fontSizeXl,
            fontWeight: FontWeight.bold,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
          h3: TextStyle(
            color: textColor,
            fontSize: DesignTokens.fontSizeLg,
            fontWeight: FontWeight.w600,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
          code: TextStyle(
            backgroundColor: codeBg,
            color: textColor,
            fontFamily: DesignTokens.fontFamilyMono,
            fontFamilyFallback: DesignTokens.monoFallbacks,
            fontSize: DesignTokens.fontSizeSm,
          ),
          codeblockDecoration: BoxDecoration(
            color: codeBg,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            border: Border.all(color: borderColor, width: DesignTokens.hairline),
          ),
          tableBorder: TableBorder.all(color: borderColor, width: 1),
          tableHead: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
          tableBody: TextStyle(
            color: textColor,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
        ),
      ),
    );
  }

  Widget _buildCodeViewer(String content, bool isDark, Color primary, Color secondary) {
    final lines = content.split('\n');
    final codeBg = isDark ? const Color(0xFF141417) : const Color(0xFFF7F7FA);
    final gutterColor = isDark ? const Color(0xFF222228) : const Color(0xFFEDEDF2);
    final numColor = isDark ? const Color(0xFF555562) : const Color(0xFF9E9EA8);

    return Container(
      color: codeBg,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // عمود أرقام الأسطر
              Container(
                color: gutterColor,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 1; i <= lines.length; i++)
                      Text(
                        '$i',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          fontFamily: DesignTokens.fontFamilyMono,
                          fontFamilyFallback: DesignTokens.monoFallbacks,
                          color: numColor,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // محتوى الكود
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  content,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontFamily: DesignTokens.fontFamilyMono,
                    fontFamilyFallback: DesignTokens.monoFallbacks,
                    color: primary,
                  ),
                ),
              ),
              const SizedBox(width: 24),
            ],
          ),
        ),
      ),
    );
  }
}
