import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:khwarizmi/core/theme/design_tokens.dart';

// ── Layout Mode ───────────────────────────────────────────────────────────────

enum LayoutMode {
  /// < 900px — شريط مطوي تلقائياً، لوحات كـ overlay
  compact,
  /// 900–1400px — شريط كامل قابل للطي، عمودان كحد أقصى
  standard,
  /// > 1400px — ثلاثة أعمدة مسموحة
  wide,
}

LayoutMode layoutModeFromWidth(double width) {
  if (width < DesignTokens.breakpointCompact) return LayoutMode.compact;
  if (width > DesignTokens.breakpointWide) return LayoutMode.wide;
  return LayoutMode.standard;
}

// ── Active Work Panel ─────────────────────────────────────────────────────────

enum WorkPanelTab { browser, terminal }

// ── State ─────────────────────────────────────────────────────────────────────

class LayoutState {
  /// هل الشريط الجانبي مطوي؟
  final bool sidebarCollapsed;

  /// عرض لوحة العمل (browser/terminal) بالبكسل
  final double workPanelWidth;

  /// هل لوحة العمل مفتوحة؟
  final bool workPanelOpen;

  /// التبويب النشط داخل لوحة العمل
  final WorkPanelTab activeWorkTab;

  /// الوضع المبسط: يخفي أقسام التفكير وبطاقات الأدوات — يُظهر النص النهائي فقط
  final bool isSimplifiedView;

  const LayoutState({
    this.sidebarCollapsed = false,
    this.workPanelWidth = DesignTokens.workPanelDefaultWidth,
    this.workPanelOpen = false,
    this.activeWorkTab = WorkPanelTab.browser,
    this.isSimplifiedView = true, // الافتراضي: مبسط (بدون ضجيج الأدوات)
  });

  LayoutState copyWith({
    bool? sidebarCollapsed,
    double? workPanelWidth,
    bool? workPanelOpen,
    WorkPanelTab? activeWorkTab,
    bool? isSimplifiedView,
  }) {
    return LayoutState(
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      workPanelWidth: workPanelWidth ?? this.workPanelWidth,
      workPanelOpen: workPanelOpen ?? this.workPanelOpen,
      activeWorkTab: activeWorkTab ?? this.activeWorkTab,
      isSimplifiedView: isSimplifiedView ?? this.isSimplifiedView,
    );
  }
}

// ── Keys ──────────────────────────────────────────────────────────────────────

const _kSidebarCollapsed = 'layout_sidebar_collapsed';
const _kWorkPanelWidth = 'layout_work_panel_width';
const _kSimplifiedView = 'layout_simplified_view';

// ── Notifier ──────────────────────────────────────────────────────────────────

class LayoutController extends StateNotifier<LayoutState> {
  LayoutController() : super(const LayoutState()) {
    _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool(_kSidebarCollapsed) ?? false;
      final panelWidth = prefs.getDouble(_kWorkPanelWidth) ??
          DesignTokens.workPanelDefaultWidth;
      final simplified = prefs.getBool(_kSimplifiedView) ?? true;
      state = state.copyWith(
        sidebarCollapsed: collapsed,
        workPanelWidth: panelWidth.clamp(
          DesignTokens.workPanelMinWidth,
          DesignTokens.workPanelMaxWidth,
        ),
        isSimplifiedView: simplified,
      );
    } catch (_) {
      // فشل القراءة — نبقى على القيم الافتراضية
    }
  }

  // ── Sidebar ─────────────────────────────────────────────────────────────

  void toggleSidebar() {
    final next = !state.sidebarCollapsed;
    state = state.copyWith(sidebarCollapsed: next);
    _saveBool(_kSidebarCollapsed, next);
  }

  void setSidebarCollapsed(bool collapsed) {
    if (state.sidebarCollapsed == collapsed) return;
    state = state.copyWith(sidebarCollapsed: collapsed);
    _saveBool(_kSidebarCollapsed, collapsed);
  }

  // ── Work Panel ──────────────────────────────────────────────────────────

  void openWorkPanel({WorkPanelTab? tab}) {
    state = state.copyWith(
      workPanelOpen: true,
      activeWorkTab: tab ?? state.activeWorkTab,
    );
  }

  void closeWorkPanel() {
    state = state.copyWith(workPanelOpen: false);
  }

  void toggleWorkPanel({WorkPanelTab? tab}) {
    if (state.workPanelOpen && (tab == null || tab == state.activeWorkTab)) {
      closeWorkPanel();
    } else {
      openWorkPanel(tab: tab);
    }
  }

  void switchTab(WorkPanelTab tab) {
    state = state.copyWith(
      activeWorkTab: tab,
      workPanelOpen: true,
    );
  }

  void setWorkPanelWidth(double width) {
    final clamped = width.clamp(
      DesignTokens.workPanelMinWidth,
      DesignTokens.workPanelMaxWidth,
    );
    if ((state.workPanelWidth - clamped).abs() < 1.0) return;
    state = state.copyWith(workPanelWidth: clamped);
    _saveDouble(_kWorkPanelWidth, clamped);
  }

  // ── Simplified View ─────────────────────────────────────────────────────

  /// يُبدّل بين الوضع المبسط والتفصيلي — يؤثر فوراً على كل المحادثة.
  void toggleSimplifiedView() {
    final next = !state.isSimplifiedView;
    state = state.copyWith(isSimplifiedView: next);
    _saveBool(_kSimplifiedView, next);
  }

  // ── Persistence Helpers ─────────────────────────────────────────────────

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _saveDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (_) {}
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final layoutProvider =
    StateNotifierProvider<LayoutController, LayoutState>((ref) {
  return LayoutController();
});
