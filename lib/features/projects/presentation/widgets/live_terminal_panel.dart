import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/projects/presentation/controllers/project_provider.dart';

/// لوحة الترمينال الحية — المرحلة 9.
///
/// تُعرض كعمود جانبي في [ChatScreen] بنفس نمط [LiveBrowserPanel] من المرحلة 6.
/// تبث ناتج أوامر PowerShell حيًا لحظة بلحظة أثناء التنفيذ.
class LiveTerminalPanel extends ConsumerStatefulWidget {
  const LiveTerminalPanel({super.key});

  @override
  ConsumerState<LiveTerminalPanel> createState() => _LiveTerminalPanelState();
}

class _LiveTerminalPanelState extends ConsumerState<LiveTerminalPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DesignTokens.borderDark : DesignTokens.borderLight;
    final surface = isDark ? DesignTokens.surfaceDark : DesignTokens.surfaceLight;
    final bg = isDark ? DesignTokens.bgDark : DesignTokens.bgLight;
    final secondary = isDark ? DesignTokens.textSecondaryDark : DesignTokens.textSecondaryLight;
    final primary = isDark ? DesignTokens.textPrimaryDark : DesignTokens.textPrimaryLight;

    final projectState = ref.watch(projectProvider);
    final project = projectState.activeProject;
    final lines = projectState.terminalOutput;
    final isRunning = projectState.isRunningCommand;
    final exitCode = projectState.lastExitCode;

    // تمرير تلقائي عند وصول سطر جديد
    ref.listen(
      projectProvider.select((s) => s.terminalOutput.length),
      (_, _) => _scrollToBottom(),
    );

    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: border, width: DesignTokens.hairline),
        ),
      ),
      child: Column(
        children: [
          // ── شريط العنوان ──────────────────────────────────────────────────
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space8),
            color: surface,
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 14, color: secondary),
                const SizedBox(width: DesignTokens.space8),
                Expanded(
                  child: Text(
                    project != null
                        ? 'ترمينال: ${project.name}'
                        : 'الترمينال',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      color: primary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // مؤشر الحالة
                if (isRunning) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                ] else if (exitCode != null) ...[
                  Icon(
                    exitCode == 0
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 14,
                    color: exitCode == 0
                        ? (isDark ? DesignTokens.statusSuccessDark : DesignTokens.statusSuccessLight)
                        : (isDark ? DesignTokens.statusErrorDark : DesignTokens.statusErrorLight),
                  ),
                  const SizedBox(width: DesignTokens.space4),
                  Text(
                    exitCode == 0 ? 'نجاح' : 'exit $exitCode',
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeXs,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.space8),
                ],

                // زر نسخ
                IconButton(
                  icon: Icon(Icons.content_copy_outlined, size: 14, color: secondary),
                  tooltip: 'نسخ الناتج',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: lines.isEmpty
                      ? null
                      : () {
                          final text = lines.map((l) => l.content).join();
                          Clipboard.setData(ClipboardData(text: text));
                        },
                ),

                // زر مسح
                IconButton(
                  icon: Icon(Icons.clear_all_rounded, size: 14, color: secondary),
                  tooltip: 'مسح',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => ref.read(projectProvider.notifier).clearTerminal(),
                ),

                // زر إغلاق اللوحة
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 14, color: secondary),
                  tooltip: 'إغلاق الترمينال',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => ref.read(projectProvider.notifier).clearTerminal(),
                ),
              ],
            ),
          ),

          Container(height: DesignTokens.hairline, color: border),

          // ── منطقة الناتج ──────────────────────────────────────────────────
          Expanded(
            child: lines.isEmpty && !isRunning
                ? Center(
                    child: Text(
                      'جاهز — في انتظار أوامر خوارزمي',
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeSm,
                        color: secondary,
                        fontFamily: DesignTokens.fontFamilyMono,
                      ),
                    ),
                  )
                : Container(
                    color: isDark
                        ? const Color(0xFF0D0D0D)
                        : const Color(0xFFF5F5F5),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(DesignTokens.space8),
                      itemCount: lines.length + (isRunning ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == lines.length && isRunning) {
                          // مؤشر وميض نهاية السطر
                          return _BlinkingCursor(isDark: isDark);
                        }

                        final line = lines[index];
                        final content = line.content;
                        final isErr = line.isStderr;

                        return SelectableText(
                          content,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: DesignTokens.fontFamilyMono,
                            color: isErr
                                ? (isDark
                                    ? const Color(0xFFBBBBBB)
                                    : const Color(0xFF555555))
                                : (isDark
                                    ? DesignTokens.textPrimaryDark
                                    : DesignTokens.textPrimaryLight),
                            height: 1.5,
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // ── شريط جذر المشروع ──────────────────────────────────────────────
          if (project != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.space8,
                vertical: 4,
              ),
              color: surface,
              child: Row(
                children: [
                  Icon(Icons.folder_open_outlined, size: 11, color: secondary),
                  const SizedBox(width: DesignTokens.space4),
                  Expanded(
                    child: Text(
                      project.rootPath,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        color: secondary,
                        fontFamily: DesignTokens.fontFamilyMono,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// مؤشر وميض بسيط في نهاية ناتج الترمينال.
class _BlinkingCursor extends StatefulWidget {
  final bool isDark;
  const _BlinkingCursor({required this.isDark});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isDark
        ? DesignTokens.textSecondaryDark
        : DesignTokens.textSecondaryLight;

    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        height: 14,
        width: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
