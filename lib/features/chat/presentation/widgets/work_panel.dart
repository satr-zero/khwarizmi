import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';
import 'package:khwarizmi/features/agent/presentation/widgets/live_browser_panel.dart';
import 'package:khwarizmi/features/chat/presentation/controllers/layout_controller.dart';
import 'package:khwarizmi/features/projects/presentation/widgets/live_terminal_panel.dart';

/// لوحة العمل الموحّدة — تجمع المتصفح الحي والترمينال في مكوّن واحد بتبويبات.
///
/// الاستخدام:
/// - في وضع [LayoutMode.wide]: تُوضع كعمود ثالث مجاور للمحادثة
/// - في وضع [LayoutMode.compact/standard]: تُفتح كـ overlay فوق المحادثة
///
/// تدعم:
/// - سحب الفاصل (draggable divider) لتغيير العرض
/// - تبديل التبويبات بين المتصفح والترمينال
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
            index: layout.activeWorkTab.index,
            children: const [
              // تبويب 0: المتصفح الحي
              _BrowserContent(),
              // تبويب 1: الترمينال الحي
              _TerminalContent(),
            ],
          ),
        ),
      ],
    );

    if (widget.isOverlay) {
      // وضع overlay: نافذة طافية فوق المحادثة
      return Positioned(
        top: DesignTokens.topBarHeight + DesignTokens.space8,
        bottom: DesignTokens.space8,
        right: DesignTokens.space8,
        width: layout.workPanelWidth,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: panelContent,
        ),
      );
    }

    // وضع عمود: مع فاصل قابل للسحب على الجانب الأيسر (RTL: أيمن)
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // فاصل قابل للسحب
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              _dragStartX = d.globalPosition.dx;
              _dragStartWidth = layout.workPanelWidth;
            },
            onHorizontalDragUpdate: (d) {
              // في تخطيط RTL الحركة معكوسة: سحب يساراً = توسيع
              final delta = _dragStartX - d.globalPosition.dx;
              ref
                  .read(layoutProvider.notifier)
                  .setWorkPanelWidth(_dragStartWidth + delta);
            },
            child: Container(
              width: 4,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: DesignTokens.hairline,
                  color: border,
                ),
              ),
            ),
          ),
        ),

        // محتوى اللوحة
        SizedBox(
          width: layout.workPanelWidth,
          child: panelContent,
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

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space12,
          vertical: DesignTokens.space8,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? primary : Colors.transparent,
              width: 1.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? primary : secondary,
            ),
            const SizedBox(width: DesignTokens.space4),
            Text(
              label,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? primary : secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Browser Content Wrapper ───────────────────────────────────────────────────

/// غلاف للمتصفح الحي داخل لوحة العمل — يُعيد استخدام LiveBrowserPanel
/// لكن بدون عرض ثابت (العرض يُحدَّد من WorkPanel الأب)
class _BrowserContent extends ConsumerStatefulWidget {
  const _BrowserContent();

  @override
  ConsumerState<_BrowserContent> createState() => _BrowserContentState();
}

class _BrowserContentState extends ConsumerState<_BrowserContent> {
  @override
  Widget build(BuildContext context) {
    // LiveBrowserPanel يُحدِّد عرضه بنفسه — نُلفّه بـ SizedBox.expand ليملأ الأب
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
